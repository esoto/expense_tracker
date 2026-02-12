# frozen_string_literal: true

module Services::Categorization
  # Sophisticated confidence scoring system that combines multiple signals
  # to calculate categorization confidence scores.
  #
  # The calculator uses five weighted factors:
  # - text_match (35%): Score from fuzzy text matching
  # - historical_success (25%): Pattern's historical success rate
  # - usage_frequency (15%): How frequently the pattern is used
  # - amount_similarity (15%): Expense amount vs typical amounts
  # - temporal_pattern (10%): Day/time pattern matching
  #
  # Scores are normalized to 0.0-1.0 range with sigmoid function to push
  # values toward extremes for clearer decision making.
  class ConfidenceCalculator
    include ActiveSupport::Benchmarkable

    # Factor weights (must sum to 1.0 for required factors or be recalculated)
    FACTOR_WEIGHTS = {
      text_match: 0.35,         # Required factor
      historical_success: 0.25,  # Optional factor
      usage_frequency: 0.15,     # Optional factor
      amount_similarity: 0.15,   # Optional factor
      temporal_pattern: 0.10     # Optional factor
    }.freeze

    # Factor configuration
    FACTOR_CONFIG = {
      text_match: { required: true, min: 0.0, max: 1.0 },
      historical_success: { required: false, min: 0.0, max: 1.0 },
      usage_frequency: { required: false, min: 0, max: 1000, logarithmic: true },
      amount_similarity: { required: false, min: 0.0, max: 1.0 },
      temporal_pattern: { required: false, min: 0.0, max: 1.0 }
    }.freeze

    # Sigmoid normalization parameters
    SIGMOID_STEEPNESS = 10.0  # Controls how aggressive the push to 0/1 is
    SIGMOID_MIDPOINT = 0.5    # The inflection point

    # Performance thresholds
    PERFORMANCE_THRESHOLD_MS = 1.0
    CACHE_TTL = 5.minutes

    # Amount similarity configuration
    AMOUNT_SIMILARITY_THRESHOLD = 2.0  # Standard deviations for similarity
    MIN_SAMPLES_FOR_STATS = 5         # Minimum samples for statistical calculation

    attr_reader :metrics

    def initialize(options = {})
      @options = options
      @cache = build_cache if options.fetch(:enable_caching, true)
      @metrics = { calculations: 0, cache_hits: 0, total_time_ms: 0.0 }
      @performance_tracker = PerformanceTracker.new

      Rails.logger.info "[ConfidenceCalculator] Initialized with options: #{@options.inspect}"
    end

    # Calculate confidence score for an expense categorization
    #
    # @param expense [Expense] The expense being categorized
    # @param pattern [CategorizationPattern] The pattern being matched
    # @param match_result [MatchResult, Hash] The result from fuzzy matching
    # @param options [Hash] Additional options
    # @return [ConfidenceScore] Detailed confidence calculation result
    def calculate(expense, pattern, match_result = nil, options = {})
      return ConfidenceScore.invalid("Missing expense") unless expense
      return ConfidenceScore.invalid("Missing pattern") unless pattern

      benchmark_calculation do
        # Check cache first
        cache_key = build_cache_key(expense, pattern, match_result)
        if @cache && (cached_result = @cache.read(cache_key))
          @metrics[:cache_hits] += 1
          return cached_result
        end

        # Calculate individual factors
        factors = calculate_factors(expense, pattern, match_result, options)

        # Validate required factors
        validation_result = validate_factors(factors)
        return validation_result unless validation_result.nil?

        # Calculate weighted score
        weighted_score = calculate_weighted_score(factors)

        # Apply sigmoid normalization
        normalized_score = apply_sigmoid_normalization(weighted_score)

        # Track if normalization was significant
        normalization_applied = (weighted_score - normalized_score).abs > 0.01

        # Build result
        result = ConfidenceScore.new(
          score: normalized_score,
          raw_score: weighted_score,
          factors: factors,
          pattern: pattern,
          expense: expense,
          metadata: build_metadata(factors, weighted_score, normalized_score, normalization_applied)
        )

        # Cache result
        @cache&.write(cache_key, result, expires_in: CACHE_TTL)

        @metrics[:calculations] += 1
        result
      end
    rescue => e
      Rails.logger.error "[ConfidenceCalculator] Calculation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      ConfidenceScore.error(e.message)
    end

    # Calculate confidence for multiple patterns
    #
    # @param expense [Expense] The expense being categorized
    # @param patterns [Array<CategorizationPattern>] Patterns to evaluate
    # @param match_results [Hash] Pattern ID to match result mapping
    # @return [Array<ConfidenceScore>] Sorted confidence scores
    def calculate_batch(expense, patterns, match_results = {})
      return [] unless expense && patterns.present?

      results = patterns.map do |pattern|
        match_result = match_results[pattern.id]
        calculate(expense, pattern, match_result)
      end

      # Sort by confidence score descending
      results.sort_by { |r| -r.score }
    end

    # Get detailed metrics about calculator performance
    def detailed_metrics
      {
        basic: @metrics,
        performance: @performance_tracker.summary,
        cache: cache_metrics,
        factor_stats: factor_statistics
      }
    end

    # Clear the cache
    def clear_cache
      @cache&.clear
      Rails.logger.info "[ConfidenceCalculator] Cache cleared"
    end

    # Get metrics (made public for testing)
    def metrics
      @metrics
    end

    private

    def calculate_factors(expense, pattern, match_result, options)
      factors = {}

      # Text match factor (required)
      factors[:text_match] = calculate_text_match_factor(match_result, pattern, expense)

      # Historical success factor
      factors[:historical_success] = calculate_historical_success_factor(pattern)

      # Usage frequency factor
      factors[:usage_frequency] = calculate_usage_frequency_factor(pattern)

      # Amount similarity factor
      factors[:amount_similarity] = calculate_amount_similarity_factor(expense, pattern)

      # Temporal pattern factor
      factors[:temporal_pattern] = calculate_temporal_pattern_factor(expense, pattern)

      # Track factor calculation performance
      @performance_tracker.record_factor_calculation(factors)

      factors
    end

    def calculate_text_match_factor(match_result, pattern, expense)
      # Handle different match_result types
      score = case match_result
      when Matchers::MatchResult
        match_result.best_score
      when Hash
        match_result[:adjusted_score] || match_result[:score] || 0.0
      when Numeric
        match_result
      when nil
        # Try to match pattern directly if no match result provided
        if pattern && pattern.matches?(expense)
          0.7  # Default score for direct pattern match
        else
          0.0
        end
      else
        0.0
      end

      # Ensure score is within valid range
      [ [ score, 0.0 ].max, 1.0 ].min
    end

    def calculate_historical_success_factor(pattern)
      return nil unless pattern.usage_count >= MIN_SAMPLES_FOR_STATS

      # Use the pattern's success rate directly
      # Apply a small boost for very frequently used patterns
      base_score = pattern.success_rate

      if pattern.usage_count > 100
        usage_boost = Math.log10(pattern.usage_count / 100.0) * 0.05
        [ [ base_score + usage_boost, 1.0 ].min, 0.0 ].max
      else
        base_score
      end
    end

    def calculate_usage_frequency_factor(pattern)
      return nil if pattern.usage_count < 1

      # Logarithmic scaling for usage frequency
      # Patterns used 1000+ times get maximum score
      max_usage = FACTOR_CONFIG[:usage_frequency][:max]

      if pattern.usage_count >= max_usage
        1.0
      else
        # Logarithmic scale from 1 to max_usage
        Math.log10(pattern.usage_count + 1) / Math.log10(max_usage + 1)
      end
    end

    def calculate_amount_similarity_factor(expense, pattern)
      return nil unless expense.amount && pattern.metadata.present?

      # Get historical amount statistics from pattern metadata
      amount_stats = pattern.metadata["amount_stats"]
      return nil unless amount_stats && amount_stats["count"] && amount_stats["count"] >= MIN_SAMPLES_FOR_STATS

      mean = amount_stats["mean"].to_f
      std_dev = amount_stats["std_dev"].to_f

      # Handle edge case where all amounts are the same (std_dev = 0)
      if std_dev == 0
        return expense.amount == mean ? 1.0 : 0.0
      end

      # Calculate z-score (number of standard deviations from mean)
      z_score = (expense.amount - mean).abs / std_dev

      # Convert z-score to similarity score (0-1)
      # Within 1 std dev = high similarity, beyond 3 std dev = low similarity
      if z_score <= 1.0
        1.0
      elsif z_score <= 2.0
        0.75 - (z_score - 1.0) * 0.25
      elsif z_score <= 3.0
        0.50 - (z_score - 2.0) * 0.30
      else
        [ 0.2 / z_score, 0.2 ].min  # Asymptotic approach to 0
      end
    end

    def calculate_temporal_pattern_factor(expense, pattern)
      return nil unless expense.transaction_date

      # Check if pattern is time-based
      return nil unless pattern.pattern_type == "time"

      # Direct temporal matching
      if pattern.matches?(expense.transaction_date)
        1.0
      else
        # Check for partial temporal match based on metadata
        check_partial_temporal_match(expense, pattern)
      end
    end

    def check_partial_temporal_match(expense, pattern)
      return nil unless pattern.metadata.present?

      temporal_stats = pattern.metadata["temporal_stats"]
      return nil unless temporal_stats

      transaction_hour = expense.transaction_date.hour
      transaction_day = expense.transaction_date.wday

      score = 0.0
      has_data = false

      # Check hour distribution
      if temporal_stats["hour_distribution"]
        hour_freq = temporal_stats["hour_distribution"][transaction_hour.to_s].to_f
        max_hour_freq = temporal_stats["hour_distribution"].values.max.to_f
        if max_hour_freq > 0
          score += (hour_freq / max_hour_freq) * 0.6
          has_data = true
        end
      end

      # Check day distribution
      if temporal_stats["day_distribution"]
        day_freq = temporal_stats["day_distribution"][transaction_day.to_s].to_f
        max_day_freq = temporal_stats["day_distribution"].values.max.to_f
        if max_day_freq > 0
          score += (day_freq / max_day_freq) * 0.4
          has_data = true
        end
      end

      has_data ? score : nil
    end

    def validate_factors(factors)
      # Check for required factors
      FACTOR_CONFIG.each do |factor_name, config|
        next unless config[:required]

        if factors[factor_name].nil?
          return ConfidenceScore.invalid("Missing required factor: #{factor_name}")
        end
      end

      nil  # Validation passed
    end

    def calculate_weighted_score(factors)
      # Filter out nil factors and adjust weights
      active_factors = factors.reject { |_, value| value.nil? }

      # Get weights for active factors
      active_weights = FACTOR_WEIGHTS.select { |factor, _| active_factors.key?(factor) }

      # Recalculate weights to sum to 1.0
      total_weight = active_weights.values.sum
      return 0.0 if total_weight == 0

      normalized_weights = active_weights.transform_values { |w| w / total_weight }

      # Calculate weighted sum
      weighted_sum = 0.0
      active_factors.each do |factor, value|
        weight = normalized_weights[factor] || 0.0
        weighted_sum += value * weight
      end

      weighted_sum
    end

    def apply_sigmoid_normalization(score)
      # Sigmoid function: 1 / (1 + e^(-k*(x-m)))
      # where k = steepness, m = midpoint
      # This pushes scores toward 0 or 1

      exponent = -SIGMOID_STEEPNESS * (score - SIGMOID_MIDPOINT)
      normalized = 1.0 / (1.0 + Math.exp(exponent))

      # Round to 4 decimal places for cleaner output
      normalized.round(4)
    end

    def build_metadata(factors, raw_score, normalized_score, normalization_applied = nil)
      {
        factor_count: factors.reject { |_, v| v.nil? }.size,
        factors_used: factors.keys.select { |k| factors[k].present? },
        normalization_applied: normalization_applied || (raw_score - normalized_score).abs > 0.01,
        calculation_timestamp: Time.current,
        weights_applied: calculate_applied_weights(factors)
      }
    end

    def calculate_applied_weights(factors)
      active_factors = factors.reject { |_, value| value.nil? }
      active_weights = FACTOR_WEIGHTS.select { |factor, _| active_factors.key?(factor) }

      total_weight = active_weights.values.sum
      return {} if total_weight == 0

      active_weights.transform_values { |w| (w / total_weight).round(3) }
    end

    def build_cache_key(expense, pattern, match_result)
      components = [
        "confidence",
        expense.id,
        pattern.id,
        pattern.confidence_weight,
        pattern.usage_count,
        pattern.success_rate,
        expense.amount,
        expense.transaction_date&.to_i
      ]

      if match_result
        score = case match_result
        when Matchers::MatchResult
          match_result.best_score
        when Hash
          match_result[:score]
        when Numeric
          match_result
        else
          nil
        end
        components << score&.round(3)
      end

      components.compact.join(":")
    end

    def build_cache
      if defined?(Redis) && Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
        Rails.cache
      else
        ActiveSupport::Cache::MemoryStore.new(
          size: 5.megabytes,
          compress: false,
          expires_in: CACHE_TTL
        )
      end
    end

    def benchmark_calculation(&block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = yield

      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      @metrics[:total_time_ms] += duration_ms
      @performance_tracker.record_calculation(duration_ms)

      if duration_ms > PERFORMANCE_THRESHOLD_MS
        Rails.logger.warn "[ConfidenceCalculator] Slow calculation: #{duration_ms.round(3)}ms"
      end

      result
    end

    def cache_metrics
      return {} unless @cache

      if @cache.respond_to?(:stats)
        @cache.stats
      else
        {
          size: @cache.instance_variable_get(:@data)&.size || 0,
          hit_rate: @metrics[:calculations] > 0 ?
            (@metrics[:cache_hits].to_f / @metrics[:calculations] * 100).round(2) : 0
        }
      end
    end

    def factor_statistics
      @performance_tracker.factor_statistics
    end

    # Inner class for tracking performance metrics
    class PerformanceTracker
      def initialize
        @calculations = []
        @factor_calculations = []
        @mutex = Mutex.new
      end

      def record_calculation(duration_ms)
        @mutex.synchronize do
          @calculations << duration_ms
          @calculations.shift if @calculations.size > 1000
        end
      end

      def record_factor_calculation(factors)
        @mutex.synchronize do
          @factor_calculations << factors.keys.select { |k| factors[k].present? }
          @factor_calculations.shift if @factor_calculations.size > 1000
        end
      end

      def summary
        @mutex.synchronize do
          return {} if @calculations.empty?

          {
            total_calculations: @calculations.size,
            avg_duration_ms: (@calculations.sum / @calculations.size).round(3),
            min_duration_ms: @calculations.min.round(3),
            max_duration_ms: @calculations.max.round(3),
            p95_duration_ms: percentile(@calculations, 0.95).round(3),
            p99_duration_ms: percentile(@calculations, 0.99).round(3)
          }
        end
      end

      def factor_statistics
        @mutex.synchronize do
          return {} if @factor_calculations.empty?

          factor_counts = Hash.new(0)
          @factor_calculations.flatten.each { |f| factor_counts[f] += 1 }

          total = @factor_calculations.size.to_f
          factor_counts.transform_values { |count| (count / total * 100).round(2) }
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

    # Health check for service monitoring
    def healthy?
      @healthy ||= begin
        # Test basic calculation functionality
        test_result = calculate_confidence(
          pattern_type: "merchant",
          match_score: 0.9,
          pattern_usage_count: 10,
          pattern_success_rate: 0.95
        )
        test_result.is_a?(ConfidenceScore)
      rescue => e
        Rails.logger.error "[ConfidenceCalculator] Health check failed: #{e.message}"
        false
      end
    end

    # Reset internal state
    def reset!
      @metrics_collector = MetricsCollector.new if defined?(@metrics_collector)
      @healthy = nil
      Rails.logger.info "[ConfidenceCalculator] Service reset completed"
    rescue => e
      Rails.logger.error "[ConfidenceCalculator] Reset failed: #{e.message}"
    end
  end

  # Value object representing a confidence score calculation result
  class ConfidenceScore
    attr_reader :score, :raw_score, :factors, :pattern, :expense, :metadata, :error

    def initialize(score:, raw_score: nil, factors: {}, pattern: nil, expense: nil, metadata: {}, error: nil)
      @score = score
      @raw_score = raw_score || score
      @factors = factors
      @pattern = pattern
      @expense = expense
      @metadata = metadata
      @error = error
      @created_at = Time.current
    end

    # Factory methods

    def self.invalid(reason)
      new(score: 0.0, error: reason, metadata: { valid: false })
    end

    def self.error(message)
      new(score: 0.0, error: message, metadata: { error: true })
    end

    # Query methods

    def valid?
      @error.nil?
    end

    def invalid?
      !valid?
    end

    def high_confidence?
      @score >= 0.85
    end

    def medium_confidence?
      @score >= 0.70 && @score < 0.85
    end

    def low_confidence?
      @score < 0.70
    end

    def confidence_level
      case @score
      when 0.95..1.0
        :very_high
      when 0.85...0.95
        :high
      when 0.70...0.85
        :medium
      when 0.50...0.70
        :low
      else
        :very_low
      end
    end

    # Factor analysis

    def factor_breakdown
      return {} unless @factors.present?

      breakdown = {}
      weights = @metadata[:weights_applied] || {}

      @factors.each do |factor, value|
        next if value.nil?

        weight = weights[factor] || 0.0
        contribution = value * weight

        breakdown[factor] = {
          value: value.round(4),
          weight: weight,
          contribution: contribution.round(4),
          percentage: (@raw_score > 0 ? (contribution / @raw_score * 100).round(2) : 0.0)
        }
      end

      breakdown
    end

    def dominant_factor
      breakdown = factor_breakdown
      return nil if breakdown.empty?

      breakdown.max_by { |_, details| details[:contribution] }&.first
    end

    def weakest_factor
      breakdown = factor_breakdown
      return nil if breakdown.empty?

      breakdown.select { |_, details| details[:value] > 0 }
               .min_by { |_, details| details[:value] }&.first
    end

    # Explanation generation

    def explanation
      parts = []

      parts << "Confidence: #{(score * 100).round(1)}% (#{confidence_level})"

      if valid?
        parts << "Based on #{@metadata[:factor_count]} factors:"

        factor_breakdown.each do |factor, details|
          factor_name = factor.to_s.humanize
          parts << "  - #{factor_name}: #{(details[:value] * 100).round(1)}% (#{details[:percentage].round(1)}% of score)"
        end

        if @metadata[:normalization_applied]
          parts << "Note: Score adjusted from #{(@raw_score * 100).round(1)}% for better separation"
        end
      else
        parts << "Error: #{@error}"
      end

      parts.join("\n")
    end

    def to_h
      {
        score: @score,
        raw_score: @raw_score,
        confidence_level: confidence_level,
        factors: @factors,
        factor_breakdown: factor_breakdown,
        pattern_id: @pattern&.id,
        expense_id: @expense&.id,
        metadata: @metadata,
        error: @error,
        created_at: @created_at
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Comparison operators

    def <=>(other)
      return nil unless other.is_a?(ConfidenceScore)
      @score <=> other.score
    end

    def ==(other)
      return false unless other.is_a?(ConfidenceScore)

      @score == other.score &&
        @factors == other.factors &&
        @pattern == other.pattern &&
        @expense == other.expense
    end

    # Display methods

    def inspect
      "#<ConfidenceScore score=#{@score.round(3)} level=#{confidence_level} factors=#{@factors.keys.join(',')} valid=#{valid?}>"
    end

    def to_s
      if valid?
        "#{(score * 100).round(1)}% confidence (#{confidence_level})"
      else
        "Invalid: #{@error}"
      end
    end
  end
end
