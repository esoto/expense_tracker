# frozen_string_literal: true

module Categorization
  # Comprehensive error handling for categorization engine
  module ErrorHandling
    # Custom error classes with context
    class CategorizationError < StandardError
      attr_reader :context, :retry_after

      def initialize(message, context: {}, retry_after: nil)
        super(message)
        @context = context
        @retry_after = retry_after
      end
    end

    class PatternNotFoundError < CategorizationError; end
    class InvalidExpenseError < CategorizationError; end
    class CacheError < CategorizationError; end
    class DatabaseError < CategorizationError; end
    class TimeoutError < CategorizationError; end
    class RateLimitError < CategorizationError; end

    # Retry mechanism with exponential backoff
    class RetryHandler
      MAX_RETRIES = 3
      BASE_DELAY = 0.1 # 100ms
      MAX_DELAY = 5.0  # 5 seconds

      def self.with_retry(operation_name, &block)
        retries = 0
        last_error = nil

        begin
          yield
        rescue StandardError => e
          retries += 1
          last_error = e

          if should_retry?(e) && retries <= MAX_RETRIES
            delay = calculate_delay(retries)
            Rails.logger.warn "[RetryHandler] Retry #{retries}/#{MAX_RETRIES} for #{operation_name} after #{delay}s"

            sleep(delay)
            retry
          else
            handle_final_error(operation_name, e, retries)
          end
        end
      end

      private

      def self.should_retry?(error)
        case error
        when ActiveRecord::ConnectionTimeoutError,
             ActiveRecord::StatementTimeout,
             Redis::TimeoutError,
             Net::ReadTimeout
          true
        when DatabaseError, CacheError
          # Retry database/cache errors only if transient
          error.message.include?("connection") || error.message.include?("timeout")
        else
          false
        end
      end

      def self.calculate_delay(retry_count)
        delay = BASE_DELAY * (2 ** (retry_count - 1))
        jitter = rand * 0.1 * delay  # Add 10% jitter
        [ delay + jitter, MAX_DELAY ].min
      end

      def self.handle_final_error(operation_name, error, retries)
        Rails.logger.error "[RetryHandler] Failed after #{retries} retries for #{operation_name}: #{error.message}"

        # Report to error tracking service
        if defined?(Rollbar)
          Rollbar.error(error, operation: operation_name, retries: retries)
        elsif defined?(Sentry)
          Sentry.capture_exception(error, extra: { operation: operation_name, retries: retries })
        end

        raise error
      end
    end

    # Fallback strategies for graceful degradation
    class FallbackStrategy
      def self.execute(primary_action, fallback_action, context = {})
        primary_action.call
      rescue StandardError => e
        Rails.logger.warn "[FallbackStrategy] Primary action failed: #{e.message}, using fallback"

        # Record fallback usage for monitoring
        increment_fallback_counter(context)

        fallback_action.call
      end

      private

      def self.increment_fallback_counter(context)
        # This would integrate with metrics system
        Rails.cache.increment("fallback:#{context[:service]}:count", 1, expires_in: 1.hour)
      end
    end

    # Error recovery mechanisms
    class ErrorRecovery
      def self.recover_from_cache_failure
        Rails.logger.error "[ErrorRecovery] Cache failure detected, clearing and rebuilding"

        # Clear corrupted cache
        Rails.cache.clear

        # Rebuild critical cache entries
        CacheWarmer.warm_critical_paths

        # Return degraded service indicator
        { status: :degraded, message: "Operating without cache" }
      end

      def self.recover_from_database_failure
        Rails.logger.error "[ErrorRecovery] Database failure detected"

        # Use read replica if available
        if ActiveRecord::Base.connected_to?(role: :reading)
          Rails.logger.info "[ErrorRecovery] Switching to read replica"
          return { status: :degraded, message: "Using read replica" }
        end

        # Return cached-only mode
        { status: :degraded, message: "Database unavailable, using cache only" }
      end
    end

    # Structured error context for debugging
    class ErrorContext
      def self.build(expense:, operation:, metadata: {})
        {
          expense_id: expense&.id,
          merchant: expense&.merchant_name,
          amount: expense&.amount,
          operation: operation,
          timestamp: Time.current.iso8601,
          rails_env: Rails.env,
          host: Socket.gethostname,
          metadata: metadata
        }
      end

      def self.log_with_context(level, message, context)
        Rails.logger.tagged(context[:operation]) do
          Rails.logger.send(level, "#{message} | Context: #{context.to_json}")
        end
      end
    end

    # Health check for categorization subsystem
    class HealthCheck
      def self.check
        checks = {
          database: check_database,
          cache: check_cache,
          patterns: check_patterns,
          performance: check_performance
        }

        overall_status = if checks.values.all? { |c| c[:status] == :healthy }
          :healthy
        elsif checks.values.any? { |c| c[:status] == :critical }
          :critical
        else
          :degraded
        end

        {
          status: overall_status,
          checks: checks,
          timestamp: Time.current.iso8601
        }
      end

      private

      def self.check_database
        CategorizationPattern.limit(1).first
        { status: :healthy, response_time_ms: 1 }
      rescue StandardError => e
        { status: :critical, error: e.message }
      end

      def self.check_cache
        Rails.cache.write("health_check", "ok", expires_in: 1.minute)
        Rails.cache.read("health_check") == "ok" ?
          { status: :healthy } :
          { status: :degraded }
      rescue StandardError => e
        { status: :critical, error: e.message }
      end

      def self.check_patterns
        count = CategorizationPattern.active.count
        if count > 0
          { status: :healthy, active_patterns: count }
        else
          { status: :degraded, message: "No active patterns" }
        end
      rescue StandardError => e
        { status: :critical, error: e.message }
      end

      def self.check_performance
        # Check recent performance metrics
        tracker = PerformanceTracker.new
        metrics = tracker.summary

        avg_time = metrics.dig(:categorizations, :avg_ms) || 0

        if avg_time <= 10
          { status: :healthy, avg_response_ms: avg_time }
        elsif avg_time <= 25
          { status: :degraded, avg_response_ms: avg_time }
        else
          { status: :critical, avg_response_ms: avg_time }
        end
      end
    end
  end
end
