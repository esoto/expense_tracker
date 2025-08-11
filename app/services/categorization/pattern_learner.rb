# frozen_string_literal: true

module Categorization
  # Intelligent service that learns from user corrections and feedback to improve
  # categorization patterns over time. Implements machine learning-inspired techniques
  # including pattern strengthening, weakening, creation, merging, and decay.
  #
  # Key features:
  # - Learns from manual categorizations and corrections
  # - Creates new patterns from repeated corrections
  # - Merges similar patterns to avoid duplication
  # - Decays unused patterns over time
  # - Batch processing for performance optimization
  #
  # Performance targets:
  # - Single correction: < 10ms
  # - Batch of 100 corrections: < 1s
  class PatternLearner
    include ActiveSupport::Benchmarkable

    # Learning configuration constants
    CONFIDENCE_BOOST_CORRECT = 0.15       # Boost for correct predictions
    CONFIDENCE_PENALTY_INCORRECT = -0.25  # Penalty for incorrect predictions
    CONFIDENCE_BOOST_USER_CREATED = 0.20  # Extra boost for user-created patterns
    DECAY_FACTOR = 0.9                    # Decay factor for unused patterns
    DECAY_THRESHOLD_DAYS = 30             # Days before pattern decay starts
    MIN_CONFIDENCE = 0.1                   # Minimum confidence weight
    MAX_CONFIDENCE = 5.0                   # Maximum confidence weight

    # Pattern creation thresholds
    MIN_CORRECTIONS_FOR_PATTERN = 3       # Minimum corrections to create pattern
    SIMILARITY_THRESHOLD = 0.85           # Threshold for pattern merging
    PATTERN_CREATION_CONFIDENCE = 1.2     # Initial confidence for new patterns

    # Performance thresholds
    POOR_PERFORMANCE_THRESHOLD = 0.3      # Success rate threshold for poor performance
    MIN_USAGE_FOR_EVALUATION = 10         # Minimum usage to evaluate performance

    # Batch processing configuration
    BATCH_SIZE = 100                      # Maximum batch size for processing
    TRANSACTION_TIMEOUT = 10.seconds      # Transaction timeout

    attr_reader :metrics, :logger

    def initialize(options = {})
      @options = options
      @logger = options.fetch(:logger, Rails.logger)
      @dry_run = options.fetch(:dry_run, false)
      @confidence_calculator = options.fetch(:confidence_calculator) { ConfidenceCalculator.new }
      @pattern_cache = PatternCache.instance
      @metrics = initialize_metrics
      @performance_tracker = PerformanceTracker.new
    end

    # Learn from a single correction
    #
    # @param expense [Expense] The expense that was corrected
    # @param correct_category [Category] The correct category assigned by user
    # @param predicted_category [Category, nil] The category that was predicted (if any)
    # @param options [Hash] Additional options
    # @return [LearningResult] Result of the learning operation
    def learn_from_correction(expense, correct_category, predicted_category = nil, options = {})
      return LearningResult.invalid("Missing expense") unless expense
      return LearningResult.invalid("Missing correct category") unless correct_category

      benchmark_learning("single_correction") do
        ActiveRecord::Base.transaction do
          result = process_single_correction(expense, correct_category, predicted_category, options)
          
          # Invalidate cache after learning
          @pattern_cache.invalidate_all unless @dry_run

          result
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      logger.error "[PatternLearner] Validation error: #{e.message}"
      LearningResult.error("Validation error: #{e.message}")
    rescue => e
      logger.error "[PatternLearner] Unexpected error: #{e.message}"
      logger.error e.backtrace.join("\n")
      LearningResult.error("Unexpected error: #{e.message}")
    end

    # Batch learn from multiple corrections
    #
    # @param corrections [Array<Hash>] Array of correction data
    # @return [BatchLearningResult] Result of batch learning
    def batch_learn(corrections)
      return BatchLearningResult.empty if corrections.blank?

      benchmark_learning("batch_corrections") do
        # Validate batch size
        if corrections.size > BATCH_SIZE
          corrections = corrections.first(BATCH_SIZE)
          logger.warn "[PatternLearner] Batch size limited to #{BATCH_SIZE}"
        end

        results = []
        patterns_affected = Set.new
        
        ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
          ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{TRANSACTION_TIMEOUT.to_i * 1000}ms'") if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
          
          corrections.each_with_index do |correction, index|
            expense = correction[:expense]
            correct_category = correction[:correct_category]
            predicted_category = correction[:predicted_category]
            
            result = process_single_correction(
              expense, 
              correct_category, 
              predicted_category,
              batch_index: index
            )
            
            results << result
            patterns_affected.merge(result.patterns_affected) if result.success?
          end

          # Optimize patterns after batch processing
          optimize_patterns(patterns_affected) unless @dry_run
        end

        # Invalidate cache once after batch
        @pattern_cache.invalidate_all unless @dry_run

        BatchLearningResult.new(
          total: corrections.size,
          successful: results.count(&:success?),
          failed: results.count { |r| !r.success? },
          patterns_created: results.sum { |r| r.patterns_created.size },
          patterns_updated: patterns_affected.size,
          results: results,
          metrics: @metrics
        )
      end
    rescue ActiveRecord::StatementTimeout
      logger.error "[PatternLearner] Batch transaction timeout"
      BatchLearningResult.error("Transaction timeout - batch too large")
    rescue => e
      logger.error "[PatternLearner] Batch learning error: #{e.message}"
      BatchLearningResult.error(e.message)
    end

    # Decay unused patterns
    #
    # @param options [Hash] Options for decay operation
    # @return [DecayResult] Result of decay operation
    def decay_unused_patterns(options = {})
      threshold_date = options.fetch(:threshold_date, DECAY_THRESHOLD_DAYS.days.ago)
      
      benchmark_learning("pattern_decay") do
        patterns_to_decay = CategorizationPattern
          .active
          .where("updated_at < ?", threshold_date)
          .where(user_created: false) # Don't decay user-created patterns

        # Count patterns before processing
        examined_count = patterns_to_decay.count
        decayed_count = 0
        deactivated_count = 0

        ActiveRecord::Base.transaction do
          patterns_to_decay.find_each do |pattern|
            original_confidence = pattern.confidence_weight
            
            # Apply decay
            new_confidence = (original_confidence * DECAY_FACTOR).round(3)
            new_confidence = [new_confidence, MIN_CONFIDENCE].max
            
            if new_confidence < 0.3
              # Deactivate very low confidence patterns
              pattern.update!(active: false) unless @dry_run
              deactivated_count += 1
            else
              pattern.update!(confidence_weight: new_confidence) unless @dry_run
              decayed_count += 1
            end

            logger.debug "[PatternLearner] Decayed pattern #{pattern.id}: #{original_confidence} -> #{new_confidence}"
          end
        end

        DecayResult.new(
          patterns_examined: examined_count,
          patterns_decayed: decayed_count,
          patterns_deactivated: deactivated_count
        )
      end
    end

    # Get learning metrics
    def learning_metrics
      {
        basic_metrics: @metrics,
        performance: @performance_tracker.summary,
        pattern_statistics: pattern_statistics,
        learning_effectiveness: calculate_effectiveness
      }
    end

    private

    def initialize_metrics
      {
        corrections_processed: 0,
        patterns_created: 0,
        patterns_strengthened: 0,
        patterns_weakened: 0,
        patterns_merged: 0,
        feedbacks_created: 0,
        learning_events_created: 0,
        total_processing_time_ms: 0.0
      }
    end

    def process_single_correction(expense, correct_category, predicted_category, options = {})
      patterns_affected = Set.new
      patterns_created = []
      actions_taken = []

      # Record feedback if there was a prediction
      if predicted_category
        feedback_result = record_feedback(expense, correct_category, predicted_category)
        actions_taken << feedback_result
        @metrics[:feedbacks_created] += 1 if feedback_result[:created]
      end

      # Find or create patterns based on expense attributes
      merchant_pattern = find_or_create_merchant_pattern(expense, correct_category)
      if merchant_pattern
        patterns_created << merchant_pattern if merchant_pattern.created_at > 1.minute.ago
        patterns_affected << merchant_pattern.id
      end

      keyword_patterns = find_or_create_keyword_patterns(expense, correct_category)
      keyword_patterns.each do |pattern|
        patterns_created << pattern if pattern.created_at > 1.minute.ago
        patterns_affected << pattern.id
      end

      # Update pattern strengths based on correction
      if predicted_category && predicted_category != correct_category
        # Weaken patterns that led to incorrect prediction
        weaken_patterns_for_category(expense, predicted_category, patterns_affected)
        actions_taken << { action: "weakened_incorrect_patterns", category: predicted_category.name }
      end

      # Strengthen patterns for correct category
      strengthen_patterns_for_category(expense, correct_category, patterns_affected)
      actions_taken << { action: "strengthened_correct_patterns", category: correct_category.name }

      # Record learning event
      record_learning_event(expense, correct_category, patterns_created.first || merchant_pattern)
      @metrics[:learning_events_created] += 1

      # Check for pattern merging opportunities
      if should_check_for_merging?(patterns_created)
        merged_patterns = merge_similar_patterns(correct_category, patterns_affected)
        actions_taken << { action: "merged_patterns", count: merged_patterns.size } if merged_patterns.any?
      end

      @metrics[:corrections_processed] += 1

      LearningResult.new(
        success: true,
        patterns_created: patterns_created,
        patterns_affected: patterns_affected.to_a,
        actions_taken: actions_taken,
        expense_id: expense.id,
        category_id: correct_category.id
      )
    end

    def find_or_create_merchant_pattern(expense, category)
      return nil if expense.merchant_name.blank?

      merchant_name = expense.merchant_name.downcase.strip
      
      pattern = CategorizationPattern.find_or_initialize_by(
        pattern_type: "merchant",
        pattern_value: merchant_name,
        category: category
      )

      if pattern.new_record?
        pattern.confidence_weight = PATTERN_CREATION_CONFIDENCE
        pattern.user_created = true
        pattern.metadata = build_pattern_metadata(expense, "merchant")
        pattern.save! unless @dry_run
        
        @metrics[:patterns_created] += 1
        logger.info "[PatternLearner] Created merchant pattern: #{merchant_name} -> #{category.name}"
      else
        strengthen_pattern(pattern, user_correction: true)
      end

      pattern
    end

    def find_or_create_keyword_patterns(expense, category)
      return [] if expense.description.blank?

      keywords = extract_keywords(expense.description)
      patterns = []

      keywords.each do |keyword|
        pattern = CategorizationPattern.find_or_initialize_by(
          pattern_type: "keyword",
          pattern_value: keyword,
          category: category
        )

        if pattern.new_record?
          # Check if this keyword appears frequently enough
          similar_expenses_count = count_similar_expenses(keyword, category)
          
          if similar_expenses_count >= MIN_CORRECTIONS_FOR_PATTERN
            pattern.confidence_weight = PATTERN_CREATION_CONFIDENCE
            pattern.user_created = false
            pattern.metadata = build_pattern_metadata(expense, "keyword")
            pattern.save! unless @dry_run
            
            patterns << pattern
            @metrics[:patterns_created] += 1
            logger.info "[PatternLearner] Created keyword pattern: #{keyword} -> #{category.name}"
          end
        else
          strengthen_pattern(pattern)
          patterns << pattern
        end
      end

      patterns
    end

    def strengthen_pattern(pattern, options = {})
      return if @dry_run

      boost = options[:user_correction] ? CONFIDENCE_BOOST_USER_CREATED : CONFIDENCE_BOOST_CORRECT
      
      old_confidence = pattern.confidence_weight
      new_confidence = pattern.confidence_weight + boost
      new_confidence = [new_confidence, MAX_CONFIDENCE].min
      
      pattern.update!(
        confidence_weight: new_confidence
      )
      
      # Record usage separately to avoid double counting
      pattern.record_usage(true)
      
      @metrics[:patterns_strengthened] += 1
      
      logger.debug "[PatternLearner] Strengthened pattern #{pattern.id}: #{old_confidence} -> #{new_confidence}"
    end

    def weaken_patterns_for_category(expense, category, patterns_affected)
      patterns = find_matching_patterns(expense, category)
      
      patterns.each do |pattern|
        weaken_pattern(pattern)
        patterns_affected << pattern.id
      end
    end

    def strengthen_patterns_for_category(expense, category, patterns_affected)
      patterns = find_matching_patterns(expense, category)
      
      patterns.each do |pattern|
        strengthen_pattern(pattern)
        patterns_affected << pattern.id
      end
    end

    def weaken_pattern(pattern)
      return if @dry_run

      old_confidence = pattern.confidence_weight
      new_confidence = pattern.confidence_weight + CONFIDENCE_PENALTY_INCORRECT
      new_confidence = [new_confidence, MIN_CONFIDENCE].max
      
      pattern.update!(
        confidence_weight: new_confidence
      )
      
      # Record usage as failure
      pattern.record_usage(false)
      
      @metrics[:patterns_weakened] += 1
      
      # Check if pattern should be deactivated
      pattern.check_and_deactivate_if_poor_performance
      
      logger.debug "[PatternLearner] Weakened pattern #{pattern.id}: #{old_confidence} -> #{new_confidence}"
    end

    def find_matching_patterns(expense, category)
      patterns = CategorizationPattern.active.where(category: category)
      
      matching_patterns = patterns.select do |pattern|
        pattern.matches?(expense)
      end
      
      matching_patterns
    end

    def merge_similar_patterns(category, patterns_affected)
      merged_patterns = []
      
      # Get all active patterns for the category
      patterns = CategorizationPattern.active
        .where(category: category)
        .order(usage_count: :desc)
      
      # Group by pattern type for more efficient merging
      patterns_by_type = patterns.group_by(&:pattern_type)
      
      patterns_by_type.each do |pattern_type, type_patterns|
        # Find similar patterns within each type
        type_patterns.combination(2).each do |pattern1, pattern2|
          similarity = calculate_pattern_similarity(pattern1, pattern2)
          
          if similarity >= SIMILARITY_THRESHOLD
            # Merge patterns (keep the one with higher usage)
            primary, secondary = pattern1.usage_count >= pattern2.usage_count ? 
              [pattern1, pattern2] : [pattern2, pattern1]
            
            merge_patterns(primary, secondary) unless @dry_run
            
            merged_patterns << secondary
            patterns_affected.delete(secondary.id)
            
            @metrics[:patterns_merged] += 1
            logger.info "[PatternLearner] Merged patterns: #{secondary.id} into #{primary.id}"
          end
        end
      end
      
      merged_patterns
    end

    def merge_patterns(primary, secondary)
      ActiveRecord::Base.transaction do
        # Combine usage statistics
        primary.update!(
          usage_count: primary.usage_count + secondary.usage_count,
          success_count: primary.success_count + secondary.success_count,
          confidence_weight: [
            (primary.confidence_weight * primary.usage_count + 
             secondary.confidence_weight * secondary.usage_count) / 
            (primary.usage_count + secondary.usage_count),
            MAX_CONFIDENCE
          ].min
        )
        
        # Merge metadata
        primary.metadata = merge_metadata(primary.metadata, secondary.metadata)
        primary.save!
        
        # Deactivate secondary pattern
        secondary.update!(active: false)
      end
    end

    def calculate_pattern_similarity(pattern1, pattern2)
      return 0.0 unless pattern1.pattern_type == pattern2.pattern_type
      
      case pattern1.pattern_type
      when "merchant", "keyword", "description"
        calculate_text_similarity(pattern1.pattern_value, pattern2.pattern_value)
      when "amount_range"
        calculate_range_similarity(pattern1.pattern_value, pattern2.pattern_value)
      else
        0.0
      end
    end

    def calculate_text_similarity(text1, text2)
      return 1.0 if text1 == text2
      
      # Use Levenshtein distance for similarity
      distance = levenshtein_distance(text1.downcase, text2.downcase)
      max_length = [text1.length, text2.length].max
      
      1.0 - (distance.to_f / max_length)
    end

    def levenshtein_distance(str1, str2)
      m = str1.length
      n = str2.length
      
      return n if m == 0
      return m if n == 0
      
      d = Array.new(m + 1) { Array.new(n + 1) }
      
      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }
      
      (1..n).each do |j|
        (1..m).each do |i|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,      # deletion
            d[i][j - 1] + 1,      # insertion
            d[i - 1][j - 1] + cost # substitution
          ].min
        end
      end
      
      d[m][n]
    end

    def calculate_range_similarity(range1, range2)
      # Parse ranges
      min1, max1 = range1.split("-").map(&:to_f)
      min2, max2 = range2.split("-").map(&:to_f)
      
      # Calculate overlap
      overlap_start = [min1, min2].max
      overlap_end = [max1, max2].min
      
      return 0.0 if overlap_start > overlap_end
      
      overlap = overlap_end - overlap_start
      total_range = [max1, max2].max - [min1, min2].min
      
      overlap / total_range
    end

    def extract_keywords(text)
      return [] if text.blank?
      
      # Simple keyword extraction - can be enhanced with NLP
      words = text.downcase.split(/\W+/)
      
      # Filter out common words and short words
      stop_words = %w[the a an and or but in on at to for of with from by]
      
      keywords = words.reject do |word|
        word.length < 3 || stop_words.include?(word) || word.match?(/^\d+$/)
      end
      
      keywords.uniq.first(5) # Limit to 5 keywords
    end

    def count_similar_expenses(keyword, category)
      Expense
        .joins(:pattern_feedbacks)
        .where(pattern_feedbacks: { category: category })
        .where("LOWER(expenses.description) LIKE ?", "%#{keyword.downcase}%")
        .distinct
        .count
    end

    def record_feedback(expense, correct_category, predicted_category)
      return { created: false } if @dry_run
      
      was_correct = predicted_category == correct_category
      feedback_type = was_correct ? "accepted" : "correction"
      
      feedback = PatternFeedback.create!(
        expense: expense,
        category: correct_category,
        was_correct: was_correct,
        feedback_type: feedback_type
      )
      
      { created: true, feedback_id: feedback.id, was_correct: was_correct }
    rescue => e
      logger.error "[PatternLearner] Failed to record feedback: #{e.message}"
      { created: false, error: e.message }
    end

    def record_learning_event(expense, category, pattern)
      return if @dry_run
      
      # Ensure confidence score is within valid range
      confidence = if pattern
        score = pattern.effective_confidence
        [[score, 0.0].max, 1.0].min  # Clamp between 0 and 1
      else
        1.0
      end
      
      PatternLearningEvent.create!(
        expense: expense,
        category: category,
        pattern_used: pattern ? "#{pattern.pattern_type}:#{pattern.pattern_value}" : "manual",
        was_correct: true,
        confidence_score: confidence
      )
    end

    def build_pattern_metadata(expense, pattern_type)
      {
        created_from: "user_correction",
        created_at: Time.current.iso8601,
        initial_expense_id: expense.id,
        pattern_type: pattern_type,
        amount_stats: {
          initial_amount: expense.amount,
          currency: expense.currency
        }
      }
    end

    def merge_metadata(metadata1, metadata2)
      merged = (metadata1 || {}).deep_merge(metadata2 || {})
      
      # Combine amount statistics if present
      if metadata1&.dig("amount_stats") && metadata2&.dig("amount_stats")
        # Safely extract amounts arrays
        amounts1 = metadata1.dig("amount_stats", "amounts")
        amounts1 = Array(amounts1 || metadata1.dig("amount_stats", "initial_amount"))
        
        amounts2 = metadata2.dig("amount_stats", "amounts")
        amounts2 = Array(amounts2 || metadata2.dig("amount_stats", "initial_amount"))
        
        amounts = (amounts1 + amounts2).flatten.compact
        
        if amounts.any?
          merged["amount_stats"] = {
            mean: amounts.map(&:to_f).sum / amounts.size,
            std_dev: calculate_std_dev(amounts),
            count: amounts.size,
            amounts: amounts.last(100) # Keep last 100 amounts
          }
        end
      end
      
      merged
    end

    def calculate_std_dev(values)
      return 0.0 if values.size <= 1
      
      mean = values.map(&:to_f).sum / values.size.to_f
      variance = values.map(&:to_f).sum { |v| (v.to_f - mean) ** 2 } / values.size.to_f
      Math.sqrt(variance)
    end

    def should_check_for_merging?(patterns_created)
      patterns_created.any? || rand < 0.1 # 10% chance to check even without new patterns
    end

    def optimize_patterns(pattern_ids)
      return if pattern_ids.empty?
      
      patterns = CategorizationPattern.where(id: pattern_ids.to_a)
      
      patterns.find_each do |pattern|
        # Recalculate success rate
        pattern.send(:calculate_success_rate)
        
        # Check for poor performance
        pattern.check_and_deactivate_if_poor_performance
        
        pattern.save! if pattern.changed?
      end
    end

    def pattern_statistics
      {
        total_patterns: CategorizationPattern.count,
        active_patterns: CategorizationPattern.active.count,
        user_created_patterns: CategorizationPattern.user_created.count,
        high_confidence_patterns: CategorizationPattern.high_confidence.count,
        successful_patterns: CategorizationPattern.successful.count,
        patterns_by_type: CategorizationPattern.group(:pattern_type).count
      }
    end

    def calculate_effectiveness
      return {} if @metrics[:corrections_processed] == 0
      
      {
        patterns_per_correction: (@metrics[:patterns_created].to_f / @metrics[:corrections_processed]).round(2),
        strengthen_weaken_ratio: @metrics[:patterns_weakened] > 0 ? 
          (@metrics[:patterns_strengthened].to_f / @metrics[:patterns_weakened]).round(2) : 
          @metrics[:patterns_strengthened].to_f,
        avg_processing_time_ms: (@metrics[:total_processing_time_ms] / @metrics[:corrections_processed]).round(2)
      }
    end

    def benchmark_learning(operation, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      result = yield
      
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      @metrics[:total_processing_time_ms] += duration_ms
      @performance_tracker.record_operation(operation, duration_ms)
      
      if duration_ms > (operation == "batch_corrections" ? 1000 : 10)
        logger.warn "[PatternLearner] Slow #{operation}: #{duration_ms.round(2)}ms"
      end
      
      result
    end

    # Inner class for tracking performance
    class PerformanceTracker
      def initialize
        @operations = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      def record_operation(name, duration_ms)
        @mutex.synchronize do
          @operations[name] << duration_ms
          @operations[name].shift if @operations[name].size > 1000
        end
      end

      def summary
        @mutex.synchronize do
          @operations.transform_values do |durations|
            next { count: 0 } if durations.empty?
            
            {
              count: durations.size,
              avg_ms: (durations.sum / durations.size).round(3),
              min_ms: durations.min.round(3),
              max_ms: durations.max.round(3),
              p95_ms: percentile(durations, 0.95).round(3),
              p99_ms: percentile(durations, 0.99).round(3)
            }
          end
        end
      end

      private

      def percentile(values, pct)
        return 0 if values.empty?
        sorted = values.sort
        index = (pct * sorted.size).ceil - 1
        sorted[index] || sorted.last
      end
    end
  end

  # Result classes for learning operations
  class LearningResult
    attr_reader :success, :patterns_created, :patterns_affected, :actions_taken, 
                :expense_id, :category_id, :error

    def initialize(success:, patterns_created: [], patterns_affected: [], 
                   actions_taken: [], expense_id: nil, category_id: nil, error: nil)
      @success = success
      @patterns_created = patterns_created
      @patterns_affected = patterns_affected
      @actions_taken = actions_taken
      @expense_id = expense_id
      @category_id = category_id
      @error = error
    end

    def self.invalid(reason)
      new(success: false, error: reason)
    end

    def self.error(message)
      new(success: false, error: message)
    end

    def success?
      @success
    end

    def to_h
      {
        success: @success,
        patterns_created: @patterns_created.size,
        patterns_affected: @patterns_affected.size,
        actions_taken: @actions_taken,
        expense_id: @expense_id,
        category_id: @category_id,
        error: @error
      }
    end
  end

  class BatchLearningResult
    attr_reader :total, :successful, :failed, :patterns_created, 
                :patterns_updated, :results, :metrics, :error

    def initialize(total:, successful:, failed:, patterns_created:, 
                   patterns_updated:, results: [], metrics: {}, error: nil)
      @total = total
      @successful = successful
      @failed = failed
      @patterns_created = patterns_created
      @patterns_updated = patterns_updated
      @results = results
      @metrics = metrics
      @error = error
    end

    def self.empty
      new(total: 0, successful: 0, failed: 0, patterns_created: 0, patterns_updated: 0)
    end

    def self.error(message)
      new(total: 0, successful: 0, failed: 0, patterns_created: 0, 
          patterns_updated: 0, error: message)
    end

    def success?
      @error.nil? && @failed == 0
    end

    def success_rate
      return 0.0 if @total == 0
      (@successful.to_f / @total * 100).round(2)
    end

    def to_h
      {
        total: @total,
        successful: @successful,
        failed: @failed,
        success_rate: success_rate,
        patterns_created: @patterns_created,
        patterns_updated: @patterns_updated,
        metrics: @metrics,
        error: @error
      }
    end
  end

  class DecayResult
    attr_reader :patterns_examined, :patterns_decayed, :patterns_deactivated

    def initialize(patterns_examined:, patterns_decayed:, patterns_deactivated:)
      @patterns_examined = patterns_examined
      @patterns_decayed = patterns_decayed
      @patterns_deactivated = patterns_deactivated
    end

    def to_h
      {
        patterns_examined: @patterns_examined,
        patterns_decayed: @patterns_decayed,
        patterns_deactivated: @patterns_deactivated,
        decay_rate: @patterns_examined > 0 ? 
          (@patterns_decayed.to_f / @patterns_examined * 100).round(2) : 0.0
      }
    end
  end
end