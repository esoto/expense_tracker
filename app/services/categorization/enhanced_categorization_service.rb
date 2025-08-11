# frozen_string_literal: true

module Categorization
  # Enhanced categorization service that integrates fuzzy matching
  # with the existing pattern-based categorization system
  class EnhancedCategorizationService
    include ActiveSupport::Benchmarkable

    # Service configuration
    MIN_CONFIDENCE_THRESHOLD = 0.70
    HIGH_CONFIDENCE_THRESHOLD = 0.85

    def initialize
      @pattern_cache = PatternCache.instance
      @fuzzy_matcher = Matchers::FuzzyMatcher.instance
      @metrics = { categorized: 0, fuzzy_matched: 0, cache_hits: 0 }
    end

    # Categorize an expense using enhanced fuzzy matching
    def categorize(expense)
      return nil unless expense

      benchmark("categorize_expense") do
        # Try user preferences first
        if (category = find_user_preference_category(expense))
          @metrics[:cache_hits] += 1
          return category
        end

        # Try canonical merchant matching
        if (category = find_merchant_category(expense))
          @metrics[:fuzzy_matched] += 1
          return category
        end

        # Try pattern matching with fuzzy logic
        if (category = find_pattern_category(expense))
          @metrics[:categorized] += 1
          return category
        end

        # Try composite patterns
        find_composite_category(expense)
      end
    end

    # Batch categorize multiple expenses
    def categorize_batch(expenses)
      return [] if expenses.blank?

      # Preload cache for efficiency
      @pattern_cache.preload_for_expenses(expenses)

      # Get all active patterns once
      all_patterns = @pattern_cache.get_all_active_patterns

      expenses.map do |expense|
        {
          expense: expense,
          category: categorize(expense),
          confidence: last_match_confidence
        }
      end
    end

    # Find best matching patterns for a merchant name
    def find_matching_patterns(merchant_name, options = {})
      return [] if merchant_name.blank?

      patterns = @pattern_cache.get_patterns_by_type("merchant")

      result = @fuzzy_matcher.match_pattern(
        merchant_name,
        patterns,
        options.reverse_merge(
          min_confidence: MIN_CONFIDENCE_THRESHOLD,
          max_results: 5
        )
      )

      result.success? ? result.matches : []
    end

    # Suggest categories based on fuzzy matching
    def suggest_categories(expense, max_suggestions = 3)
      suggestions = []

      # Get merchant-based suggestions
      if expense.merchant_name?
        merchant_matches = find_merchant_matches(expense.merchant_name)

        merchant_matches.each do |match|
          if match[:category]
            suggestions << {
              category: match[:category],
              confidence: match[:score],
              reason: "Merchant match: #{match[:display_name]}",
              type: :merchant
            }
          end
        end
      end

      # Get pattern-based suggestions
      pattern_matches = find_pattern_matches(expense)

      pattern_matches.each do |match|
        pattern = match[:pattern]
        next unless pattern

        suggestions << {
          category: pattern.category,
          confidence: match[:adjusted_score] || match[:score],
          reason: "Pattern match: #{pattern.pattern_type} - #{pattern.pattern_value}",
          type: :pattern
        }
      end

      # Sort by confidence and return top suggestions
      suggestions
        .sort_by { |s| -s[:confidence] }
        .first(max_suggestions)
    end

    # Learn from user feedback
    def learn_from_feedback(expense, category, was_correct)
      return unless expense && category

      # Update pattern statistics
      if @last_matched_pattern
        @last_matched_pattern.record_usage(was_correct)
      end

      # Create or update user preference if correct
      if was_correct && expense.merchant_name? && expense.email_account
        create_user_preference(expense, category)
      end

      # Record learning event
      pattern_name = if @last_matched_pattern
                       case @last_matched_pattern
                       when CategorizationPattern
                         "#{@last_matched_pattern.pattern_type}:#{@last_matched_pattern.pattern_value}"
                       when CompositePattern
                         "composite:#{@last_matched_pattern.name}"
                       else
                         @last_matched_pattern.to_s
                       end
      else
                       "unknown"
      end

      PatternLearningEvent.create!(
        expense: expense,
        category: category,
        pattern_used: pattern_name,
        was_correct: was_correct,
        confidence_score: last_match_confidence,
        context_data: {
          pattern_id: @last_matched_pattern&.id,
          pattern_class: @last_matched_pattern&.class&.name
        }
      )
    end

    # Get performance metrics
    def metrics
      {
        categorization: @metrics,
        fuzzy_matcher: @fuzzy_matcher.metrics,
        pattern_cache: @pattern_cache.metrics
      }
    end

    private

    def find_user_preference_category(expense)
      return nil unless expense.merchant_name?

      preference = @pattern_cache.get_user_preference(expense.merchant_name)
      preference&.category
    end

    def find_merchant_category(expense)
      return nil unless expense.merchant_name?

      # Find canonical merchant
      canonical = CanonicalMerchant.find_or_create_from_raw(expense.merchant_name)
      return nil unless canonical

      # Check if canonical merchant has a category hint
      if canonical.category_hint.present?
        category = Category.find_by(name: canonical.category_hint)
        return category if category
      end

      # Try fuzzy matching against patterns
      patterns = @pattern_cache.get_patterns_by_type("merchant")
      result = @fuzzy_matcher.match_pattern(canonical.name, patterns)

      if result.success? && result.best_score >= HIGH_CONFIDENCE_THRESHOLD
        @last_matched_pattern = result.best_pattern
        @last_match_confidence = result.best_score
        return result.best_pattern.category
      end

      nil
    end

    def find_pattern_category(expense)
      all_patterns = @pattern_cache.get_all_active_patterns

      # Group patterns by type for efficient matching
      patterns_by_type = all_patterns.group_by(&:pattern_type)

      best_match = nil
      best_score = 0.0

      # Check merchant patterns with fuzzy matching
      if expense.merchant_name? && patterns_by_type["merchant"]
        result = @fuzzy_matcher.match_pattern(
          expense.merchant_name,
          patterns_by_type["merchant"]
        )

        if result.success? && result.best_score > best_score
          best_match = result.best_pattern
          best_score = result.best_score
        end
      end

      # Check description patterns with fuzzy matching
      if expense.description? && patterns_by_type["description"]
        result = @fuzzy_matcher.match_pattern(
          expense.description,
          patterns_by_type["description"]
        )

        if result.success? && result.best_score > best_score
          best_match = result.best_pattern
          best_score = result.best_score
        end
      end

      # Check other pattern types (amount_range, time, etc.)
      %w[amount_range time regex].each do |pattern_type|
        next unless patterns_by_type[pattern_type]

        patterns_by_type[pattern_type].each do |pattern|
          if pattern.matches?(expense)
            score = pattern.effective_confidence
            if score > best_score
              best_match = pattern
              best_score = score
            end
          end
        end
      end

      if best_match && best_score >= MIN_CONFIDENCE_THRESHOLD
        @last_matched_pattern = best_match
        @last_match_confidence = best_score
        return best_match.category
      end

      nil
    end

    def find_composite_category(expense)
      composites = CompositePattern.active.includes(:category)

      composites.each do |composite|
        if composite.matches?(expense)
          @last_matched_pattern = composite
          @last_match_confidence = composite.confidence_weight
          return composite.category
        end
      end

      nil
    end

    def find_merchant_matches(merchant_name)
      canonical_merchants = CanonicalMerchant.popular

      result = @fuzzy_matcher.match_merchant(
        merchant_name,
        canonical_merchants,
        max_results: 3
      )

      return [] unless result.success?

      result.matches.map do |match|
        merchant = canonical_merchants.find { |m| m.id == match[:id] }
        next unless merchant

        category = merchant.suggest_category

        {
          merchant: merchant,
          category: category,
          score: match[:adjusted_score] || match[:score],
          display_name: merchant.display_name || merchant.name
        }
      end.compact
    end

    def find_pattern_matches(expense)
      all_patterns = @pattern_cache.get_all_active_patterns
      matches = []

      # Match merchant patterns
      if expense.merchant_name?
        merchant_patterns = all_patterns.select { |p| p.pattern_type == "merchant" }
        result = @fuzzy_matcher.match_pattern(expense.merchant_name, merchant_patterns)
        matches.concat(result.matches) if result.success?
      end

      # Match description patterns
      if expense.description?
        desc_patterns = all_patterns.select { |p| p.pattern_type.in?(%w[description keyword]) }
        result = @fuzzy_matcher.match_pattern(expense.description, desc_patterns)
        matches.concat(result.matches) if result.success?
      end

      # Sort by adjusted score
      matches.sort_by { |m| -(m[:adjusted_score] || m[:score]) }
    end

    def create_user_preference(expense, category)
      UserCategoryPreference.find_or_create_by(
        email_account: expense.email_account,
        context_type: "merchant",
        context_value: expense.merchant_name.downcase.strip
      ) do |pref|
        pref.category = category
        pref.preference_weight = 1
        pref.usage_count = 1
      end
    end

    def last_match_confidence
      @last_match_confidence || 0.0
    end

    def benchmark(operation, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = yield

      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      if duration_ms > 10
        Rails.logger.warn "[EnhancedCategorizationService] Slow operation: #{operation} took #{duration_ms.round(2)}ms"
      end

      result
    end
  end
end
