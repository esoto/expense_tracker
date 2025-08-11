# frozen_string_literal: true

module Categorization
  # Thread-safe improvements for Engine
  module EngineImprovements
    extend ActiveSupport::Concern

    included do
      # Thread-safe counters using Concurrent::AtomicFixnum
      attr_reader :total_categorizations_counter, :successful_categorizations_counter
    end

    def initialize_thread_safe_counters
      require "concurrent"
      @total_categorizations_counter = Concurrent::AtomicFixnum.new(0)
      @successful_categorizations_counter = Concurrent::AtomicFixnum.new(0)
      @metrics_mutex = Mutex.new
    end

    def increment_total_categorizations
      @total_categorizations_counter.increment
    end

    def increment_successful_categorizations
      @successful_categorizations_counter.increment
    end

    # Async categorization with job queue
    def categorize_async(expense, options = {})
      CategorizationJob.perform_later(
        expense_id: expense.id,
        options: options
      )
    end

    # Batch processing with connection pooling
    def batch_categorize_parallel(expenses, options = {})
      return [] if expenses.blank?

      # Use parallel processing for large batches
      if expenses.size > 100
        require "parallel"

        Parallel.map(expenses, in_threads: 4) do |expense|
          ActiveRecord::Base.connection_pool.with_connection do
            categorize(expense, options)
          end
        end
      else
        expenses.map { |expense| categorize(expense, options) }
      end
    end

    # Optimized pattern loading with preloading
    def find_pattern_matches_optimized(expense, options)
      matches = []

      # Load patterns with proper scoping and eager loading
      ActiveRecord::Base.connection_pool.with_connection do
        # Merchant patterns
        if expense.merchant_name?
          merchant_patterns = CategorizationPattern
            .active
            .where(pattern_type: "merchant")
            .includes(:category)
            .where("LOWER(pattern_value) LIKE ?", "%#{expense.merchant_name.downcase}%")
            .limit(20)

          matches.concat(process_patterns(merchant_patterns, expense))
        end

        # Keyword patterns
        if expense.description?
          keyword_patterns = CategorizationPattern
            .active
            .where(pattern_type: [ "keyword", "description" ])
            .includes(:category)
            .where("? ILIKE '%' || pattern_value || '%'", expense.description)
            .limit(20)

          matches.concat(process_patterns(keyword_patterns, expense))
        end
      end

      matches
    end

    private

    def process_patterns(patterns, expense)
      patterns.map do |pattern|
        score = calculate_pattern_score(pattern, expense)
        next if score < 0.3

        {
          pattern: pattern,
          match_score: score,
          match_type: "optimized_match"
        }
      end.compact
    end

    def calculate_pattern_score(pattern, expense)
      base_score = pattern.success_rate * pattern.confidence_weight

      # Apply text similarity if applicable
      if pattern.pattern_type == "merchant" && expense.merchant_name?
        similarity = text_similarity(pattern.pattern_value, expense.merchant_name)
        base_score *= similarity
      elsif pattern.pattern_type.in?([ "keyword", "description" ]) && expense.description?
        similarity = text_similarity(pattern.pattern_value, expense.description)
        base_score *= similarity
      end

      base_score
    end

    def text_similarity(text1, text2)
      return 0.0 if text1.blank? || text2.blank?

      # Simple Jaccard similarity for now
      words1 = text1.downcase.split(/\W+/).to_set
      words2 = text2.downcase.split(/\W+/).to_set

      return 1.0 if words1 == words2

      intersection = words1 & words2
      union = words1 | words2

      return 0.0 if union.empty?

      intersection.size.to_f / union.size
    end
  end

  # Background job for async categorization
  class CategorizationJob < ApplicationJob
    queue_as :default

    def perform(expense_id:, options: {})
      expense = Expense.find(expense_id)
      engine = Engine.new # New instance per job

      result = engine.categorize(expense, options)

      if result.successful? && result.high_confidence?
        expense.update!(
          category: result.category,
          auto_categorized: true,
          categorization_confidence: result.confidence,
          categorization_method: result.method
        )
      end

      result
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "[CategorizationJob] Expense #{expense_id} not found"
    end
  end

  # Circuit breaker for external services
  class CircuitBreaker
    attr_reader :failure_count, :last_failure_time, :state

    FAILURE_THRESHOLD = 5
    TIMEOUT_DURATION = 30.seconds

    def initialize
      @failure_count = 0
      @last_failure_time = nil
      @state = :closed
      @mutex = Mutex.new
    end

    def call
      @mutex.synchronize do
        case @state
        when :open
          if Time.current - @last_failure_time > TIMEOUT_DURATION
            @state = :half_open
            @failure_count = 0
          else
            raise CircuitOpenError, "Circuit breaker is open"
          end
        end
      end

      result = yield

      @mutex.synchronize do
        @state = :closed if @state == :half_open
        @failure_count = 0
      end

      result
    rescue => e
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.current

        if @failure_count >= FAILURE_THRESHOLD
          @state = :open
          Rails.logger.error "[CircuitBreaker] Opening circuit after #{@failure_count} failures"
        end
      end

      raise e
    end

    def reset!
      @mutex.synchronize do
        @failure_count = 0
        @last_failure_time = nil
        @state = :closed
      end
    end
  end

  class CircuitOpenError < StandardError; end
end
