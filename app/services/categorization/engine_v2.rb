# frozen_string_literal: true

module Categorization
  # Simplified Engine v2 - Wrapper around the new Orchestrator
  # Provides backward compatibility while delegating to clean orchestrator
  #
  # This is a transitional class that:
  # - Maintains the existing Engine API for backward compatibility
  # - Delegates actual orchestration to the new Orchestrator class
  # - Handles infrastructure concerns (circuit breakers, thread pools)
  # - Will be deprecated once all consumers migrate to Orchestrator
  class EngineV2
    include ActiveSupport::Benchmarkable

    # Performance configuration
    PERFORMANCE_TARGET_MS = 10.0
    BATCH_SIZE_LIMIT = 1000

    # Error types for backward compatibility
    class CategorizationError < StandardError; end
    class ValidationError < CategorizationError; end

    attr_reader :orchestrator, :logger

    # Factory method for creating engine instances
    def self.create(options = {})
      new(options)
    end

    def initialize(options = {})
      @logger = options.fetch(:logger, Rails.logger)
      @shutdown = false
      @metrics = { total: 0, successful: 0 }

      # Create orchestrator based on environment
      @orchestrator = create_orchestrator(options)

      @logger.info "[EngineV2] Initialized with clean orchestrator pattern"
    end

    # Main categorization method - delegates to orchestrator
    def categorize(expense, options = {})
      return CategorizationResult.error("Service shutdown") if shutdown?

      track_metrics do
        @orchestrator.categorize(expense, options)
      end
    rescue StandardError => e
      @logger.error "[EngineV2] Categorization failed: #{e.message}"
      CategorizationResult.error("Categorization failed")
    end

    # Batch categorization - delegates to orchestrator
    def batch_categorize(expenses, options = {})
      return [] if expenses.blank?
      return expenses.map { CategorizationResult.error("Service shutdown") } if shutdown?

      # Enforce batch size limit
      if expenses.size > BATCH_SIZE_LIMIT
        @logger.warn "[EngineV2] Batch size #{expenses.size} exceeds limit, processing first #{BATCH_SIZE_LIMIT}"
        expenses = expenses.first(BATCH_SIZE_LIMIT)
      end

      @orchestrator.batch_categorize(expenses, options)
    rescue StandardError => e
      @logger.error "[EngineV2] Batch categorization failed: #{e.message}"
      expenses.map { CategorizationResult.error("Batch processing failed") }
    end

    # Learn from correction - delegates to orchestrator
    def learn_from_correction(expense, correct_category, predicted_category = nil, options = {})
      return LearningResult.error("Service shutdown") if shutdown?

      @orchestrator.learn_from_correction(
        expense,
        correct_category,
        predicted_category,
        options
      )
    rescue StandardError => e
      @logger.error "[EngineV2] Learning failed: #{e.message}"
      LearningResult.error("Learning failed")
    end

    # Warm up the engine
    def warm_up
      return { status: :shutdown } if shutdown?

      @logger.info "[EngineV2] Starting warm-up..."

      # Warm up pattern cache
      pattern_count = warm_pattern_cache

      @logger.info "[EngineV2] Warm-up completed"
      {
        patterns: pattern_count,
        status: :ready
      }
    rescue StandardError => e
      @logger.error "[EngineV2] Warm-up failed: #{e.message}"
      { status: :failed, error: e.message }
    end

    # Get metrics from orchestrator and engine
    def metrics
      {
        engine: {
          total_categorizations: @metrics[:total],
          successful_categorizations: @metrics[:successful],
          success_rate: calculate_success_rate,
          shutdown: shutdown?
        },
        orchestrator: @orchestrator.metrics
      }
    end

    # Check health status
    def healthy?
      !shutdown? && @orchestrator.healthy?
    end

    # Reset the engine
    def reset!
      return if shutdown?

      @orchestrator.reset!
      @metrics = { total: 0, successful: 0 }

      @logger.info "[EngineV2] Engine reset completed"
    end

    # Shutdown the engine
    def shutdown!
      return if @shutdown

      @logger.info "[EngineV2] Shutting down..."
      @shutdown = true
      @logger.info "[EngineV2] Shutdown complete"
    end

    # Check if engine is shutdown
    def shutdown?
      @shutdown
    end

    private

    def create_orchestrator(options)
      # Use factory to create appropriate orchestrator
      case Rails.env
      when "production"
        OrchestratorFactory.create_production(options)
      when "test"
        OrchestratorFactory.create_test(options)
      else
        OrchestratorFactory.create_development(options)
      end
    end

    def track_metrics
      @metrics[:total] += 1
      result = yield
      @metrics[:successful] += 1 if result.successful?
      result
    end

    def calculate_success_rate
      return 0.0 if @metrics[:total] == 0
      (@metrics[:successful].to_f / @metrics[:total] * 100).round(2)
    end

    def warm_pattern_cache
      # Load frequently used patterns
      patterns = CategorizationPattern
        .active
        .joins(:category)
        .where("usage_count > ?", 10)
        .order(usage_count: :desc)
        .limit(100)

      patterns.count
    end
  end
end
