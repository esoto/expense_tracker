# frozen_string_literal: true

module Services::Categorization
  module Strategies
    # Strategy that categorizes expenses by matching against persisted
    # CategorizationPatterns using fuzzy matching and confidence scoring.
    #
    # This is a thin wrapper around the existing FuzzyMatcher,
    # PatternCache, and ConfidenceCalculator services. It does NOT
    # handle auto-update or pattern-usage recording -- those remain
    # in Engine.
    class PatternStrategy < BaseStrategy
      # Memory management
      PATTERN_BATCH_SIZE = 100

      # @param pattern_cache_service [PatternCache]
      # @param fuzzy_matcher [Matchers::FuzzyMatcher]
      # @param confidence_calculator [ConfidenceCalculator]
      # @param logger [Logger]
      def initialize(pattern_cache_service:, fuzzy_matcher:, confidence_calculator:, logger: Rails.logger)
        @pattern_cache_service = pattern_cache_service
        @fuzzy_matcher = fuzzy_matcher
        @confidence_calculator = confidence_calculator
        @logger = logger
      end

      # @return [String]
      def layer_name
        "pattern"
      end

      # Attempt to categorize an expense via pattern matching.
      #
      # Returns a CategorizationResult. If no patterns match or none
      # exceed +min_confidence+, returns a +no_match+ result.
      #
      # @param expense [Expense]
      # @param options [Hash]
      # @return [CategorizationResult]
      def call(expense, options = {})
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Check user preferences first (highest priority)
        if expense.merchant_name? && options.fetch(:check_user_preferences, true)
          user_result = check_user_preference(expense)
          return user_result if user_result
        end

        # Find matching patterns
        pattern_matches = find_pattern_matches(expense, options)

        if pattern_matches.empty?
          return CategorizationResult.no_match(
            processing_time_ms: duration_ms(start_time)
          )
        end

        # Score and rank
        scored_matches = score_and_rank_matches(expense, pattern_matches, options)
        best_match = scored_matches.first

        if best_match[:confidence] < options.fetch(:min_confidence, 0.5)
          return CategorizationResult.no_match(
            processing_time_ms: duration_ms(start_time)
          )
        end

        build_result(expense, best_match, scored_matches, options, duration_ms(start_time))
      end

      private

      # User preference boost constant -- mirrors Engine::USER_PREFERENCE_BOOST
      USER_PREFERENCE_BOOST = 0.15

      def check_user_preference(expense)
        preference = @pattern_cache_service.get_user_preference(expense.merchant_name)
        return nil unless preference

        base_confidence = [ preference.preference_weight / 10.0, 1.0 ].min
        confidence = [ base_confidence + USER_PREFERENCE_BOOST, 1.0 ].min

        CategorizationResult.from_user_preference(
          preference.category,
          confidence,
          processing_time_ms: 0.5
        )
      rescue => e
        @logger.warn "[PatternStrategy] User preference check failed: #{e.message}"
        nil
      end

      def find_pattern_matches(expense, options)
        matches = []

        load_patterns_in_batches(options).each do |patterns|
          matches.concat(match_merchant_patterns(expense, patterns, options))
          matches.concat(match_description_patterns(expense, patterns, options))
          matches.concat(match_other_patterns(expense, patterns))

          break if matches.size >= options.fetch(:max_results, 10) * 2
        end

        matches
      end

      def load_patterns_in_batches(options)
        patterns = CategorizationPattern
          .active
          .includes(:category)
          .order(usage_count: :desc, success_rate: :desc)

        patterns = patterns.where(pattern_type: options[:pattern_types]) if options[:pattern_types].present?

        batches = []
        patterns.find_in_batches(batch_size: PATTERN_BATCH_SIZE) do |batch|
          batches << batch
          break if batches.size >= 5
        end

        batches
      end

      def match_merchant_patterns(expense, patterns, options)
        return [] unless expense.merchant_name?

        merchant_patterns = patterns.select { |p| p.pattern_type == "merchant" }
        return [] if merchant_patterns.empty?

        result = @fuzzy_matcher.match_pattern(
          expense.merchant_name,
          merchant_patterns,
          options.slice(:min_confidence, :max_results)
        )
        process_fuzzy_matches(result)
      end

      def match_description_patterns(expense, patterns, options)
        return [] unless expense.description?

        desc_patterns = patterns.select { |p| p.pattern_type.in?(%w[keyword description]) }
        return [] if desc_patterns.empty?

        result = @fuzzy_matcher.match_pattern(
          expense.description,
          desc_patterns,
          options.slice(:min_confidence, :max_results)
        )
        process_fuzzy_matches(result)
      end

      def match_other_patterns(expense, patterns)
        patterns.each_with_object([]) do |pattern, matches|
          next if pattern.pattern_type.in?(%w[merchant keyword description])

          if pattern.matches?(expense)
            matches << {
              pattern: pattern,
              match_score: 1.0,
              match_type: pattern.pattern_type
            }
          end
        end
      end

      def process_fuzzy_matches(match_result)
        return [] unless match_result.success?

        match_result.matches.filter_map do |match|
          pattern = match[:pattern] || match[:object]
          next unless pattern.is_a?(CategorizationPattern)

          {
            pattern: pattern,
            match_score: match[:score] || 0.0,
            match_type: "fuzzy_match"
          }
        end
      end

      def score_and_rank_matches(expense, pattern_matches, options)
        scored = pattern_matches
          .group_by { |m| m[:pattern].category_id }
          .map do |_category_id, matches|
            best_match = matches.max_by { |m| m[:match_score] }
            pattern = best_match[:pattern]
            category = matches.first[:pattern].category

            confidence_score = @confidence_calculator.calculate(expense, pattern, best_match[:match_score])

            {
              category: category,
              confidence: confidence_score.score,
              confidence_score: confidence_score,
              patterns: matches.map { |m| m[:pattern] },
              match_type: best_match[:match_type]
            }
          end

        scored.sort_by! { |s| -s[:confidence] }
        scored = scored.first(options[:max_categories]) if options[:max_categories]
        scored
      end

      def build_result(expense, best_match, all_matches, options, processing_time_ms)
        alternatives = if options[:include_alternatives]
          all_matches[1..2].map do |match|
            { category: match[:category], confidence: match[:confidence] }
          end
        else
          []
        end

        CategorizationResult.new(
          category: best_match[:category],
          confidence: best_match[:confidence],
          patterns_used: best_match[:patterns].map { |p| "#{p.pattern_type}:#{p.pattern_value}" },
          confidence_breakdown: best_match[:confidence_score].factor_breakdown,
          alternative_categories: alternatives,
          processing_time_ms: processing_time_ms,
          method: best_match[:match_type] || "pattern_match",
          metadata: {
            expense_id: expense.id,
            patterns_evaluated: all_matches.sum { |m| m[:patterns].size },
            confidence_factors: best_match[:confidence_score].metadata[:factors_used],
            matched_patterns: best_match[:patterns]
          }
        )
      end

      def duration_ms(start_time)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      end
    end
  end
end
