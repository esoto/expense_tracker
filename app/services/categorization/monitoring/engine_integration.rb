# frozen_string_literal: true

module Categorization
  module Monitoring
    # Module to integrate monitoring capabilities into the Categorization Engine
    module EngineIntegration
      extend ActiveSupport::Concern

      included do
        alias_method :original_categorize, :categorize
        alias_method :original_learn_from_correction, :learn_from_correction
        alias_method :original_with_performance_tracking, :with_performance_tracking
      end

      # Enhanced categorize method with monitoring
      def categorize(expense, options = {})
        correlation_id = options[:correlation_id] || generate_correlation_id
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Use structured logger with correlation ID
        structured_logger.with_correlation_id(correlation_id) do |logger|
          logger.log_categorization(
            event_type: "started",
            expense: expense,
            result: nil,
            metadata: { options: options.except(:correlation_id) }
          )

          result = original_categorize(expense, options.merge(correlation_id: correlation_id))
          
          duration_ms = calculate_duration(start_time)

          # Track metrics
          track_categorization_metrics(expense, result, duration_ms, options)

          # Log result
          logger.log_categorization(
            event_type: "completed",
            expense: expense,
            result: result,
            metadata: {
              duration_ms: duration_ms,
              method: result&.method,
              confidence: result&.confidence
            }
          )

          result
        end
      rescue => e
        duration_ms = calculate_duration(start_time) rescue 0
        
        # Log error with context
        structured_logger.log_error(
          error: e,
          context: {
            expense_id: expense&.id,
            correlation_id: correlation_id,
            duration_ms: duration_ms
          }
        )

        # Track error metrics
        metrics_collector.track_error(
          error_type: e.class.name,
          context: { service: "engine", method: "categorize" }
        )

        raise
      end

      # Enhanced learn_from_correction with monitoring
      def learn_from_correction(expense, correct_category, predicted_category = nil, options = {})
        correlation_id = options[:correlation_id] || generate_correlation_id
        
        structured_logger.with_correlation_id(correlation_id) do |logger|
          # Track learning event
          logger.log_learning(
            action: "correction",
            pattern: OpenStruct.new(
              id: nil,
              pattern_text: expense.description,
              category_id: correct_category.id
            ),
            changes: {
              predicted_category_id: predicted_category&.id,
              correct_category_id: correct_category.id
            },
            metadata: { expense_id: expense.id }
          )

          result = original_learn_from_correction(
            expense,
            correct_category,
            predicted_category,
            options.merge(correlation_id: correlation_id)
          )

          # Track learning metrics
          metrics_collector.track_learning(
            action: "correction",
            pattern_type: "user_feedback",
            success: result.present?,
            confidence_change: nil
          )

          result
        end
      rescue => e
        structured_logger.log_error(
          error: e,
          context: {
            expense_id: expense&.id,
            correct_category_id: correct_category&.id,
            correlation_id: correlation_id
          }
        )

        metrics_collector.track_error(
          error_type: e.class.name,
          context: { service: "engine", method: "learn_from_correction" }
        )

        raise
      end

      # Enhanced performance tracking with metrics
      def with_performance_tracking(operation, correlation_id, &block)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = yield

        duration_ms = calculate_duration(start_time)

        # Track performance metrics
        metrics_collector.track_performance(
          metric_name: "operation.#{operation}",
          value: duration_ms,
          unit: :milliseconds
        )

        # Log performance if slow
        if duration_ms > PERFORMANCE_TARGET_MS
          structured_logger.log_performance(
            operation: operation,
            duration_ms: duration_ms,
            metadata: {
              correlation_id: correlation_id,
              slow: true,
              threshold_ms: PERFORMANCE_TARGET_MS
            }
          )
        end

        # Original tracking
        @performance_tracker.track_operation(operation) { result } if @performance_tracker

        result
      end

      # Track cache operations with monitoring
      def track_cache_operation(operation, cache_type, key, hit)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        result = yield if block_given?
        
        duration_ms = calculate_duration(start_time)

        # Track cache metrics
        metrics_collector.track_cache(
          operation: operation,
          cache_type: cache_type,
          hit: hit,
          duration_ms: duration_ms
        )

        # Log cache operation
        structured_logger.log_cache(
          operation: operation,
          cache_type: cache_type,
          key: key,
          hit: hit,
          metadata: { duration_ms: duration_ms }
        )

        result
      end

      # Get comprehensive health status
      def health_status
        health_check = HealthCheck.new
        health_check.check_all
      end

      # Check if engine is healthy
      def monitoring_healthy?
        health_status[:healthy]
      rescue
        false
      end

      private

      def track_categorization_metrics(expense, result, duration_ms, options)
        return unless metrics_collector.enabled?

        success = result&.successful? || false
        confidence = result&.confidence
        category_id = result&.category_id
        method = result&.method || options[:method]

        metrics_collector.track_categorization(
          expense_id: expense.id,
          success: success,
          confidence: confidence,
          duration_ms: duration_ms,
          category_id: category_id,
          method: method
        )
      end

      def metrics_collector
        @metrics_collector ||= MetricsCollector.instance
      end

      def structured_logger
        @structured_logger ||= StructuredLogger.new(
          logger: @logger,
          context: { service: "categorization_engine" }
        )
      end

      def calculate_duration(start_time)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      end
    end
  end
end