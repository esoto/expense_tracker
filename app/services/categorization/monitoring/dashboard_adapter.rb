# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Adapter for dashboard monitoring strategies
    # Provides a unified interface to switch between original and optimized implementations
    class DashboardAdapter
      # Available strategies
      STRATEGIES = {
        original: Services::Categorization::Monitoring::DashboardHelper,
        optimized: Services::Categorization::Monitoring::DashboardHelperOptimized
      }.freeze

      # Default strategy
      DEFAULT_STRATEGY = :optimized

      attr_reader :strategy_override

      class << self
        # Singleton instance
        def instance
          @instance ||= new
        end

        # Get the currently configured strategy
        def current_strategy
          strategy_from_env || strategy_from_config || DEFAULT_STRATEGY
        end

        private

        def strategy_from_env
          return unless ENV["DASHBOARD_STRATEGY"].present?

          strategy = ENV["DASHBOARD_STRATEGY"].to_sym
          STRATEGIES.key?(strategy) ? strategy : nil
        end

        def strategy_from_config
          return unless defined?(Rails) && Rails.configuration.respond_to?(:x)

          config_strategy = Rails.configuration.x.categorization&.dig("monitoring", "dashboard_strategy")
          return unless config_strategy

          strategy = config_strategy.to_sym
          STRATEGIES.key?(strategy) ? strategy : nil
        rescue StandardError => e
          Rails.logger.warn "Failed to read dashboard strategy from config: #{e.message}"
          nil
        end
      end

      def initialize(strategy_override: nil)
        @strategy_override = validate_strategy(strategy_override) if strategy_override
        @metrics_cache = {}
        @cache_timestamps = {}
        @mutex = Mutex.new
      end

      # Get the active strategy name
      def strategy_name
        determine_strategy
      end

      # Get information about the current strategy
      def strategy_info
        strategy = determine_strategy
        {
          name: strategy,
          class: STRATEGIES[strategy].name,
          cached: strategy == :optimized,
          source: strategy_source
        }
      end

      # Main metrics summary with instrumentation
      def metrics_summary
        instrument_method(:metrics_summary) do
          with_error_handling do
            strategy_class.metrics_summary
          end
        end
      end

      # Categorization metrics
      def categorization_metrics
        instrument_method(:categorization_metrics) do
          with_error_handling do
            if strategy_class.respond_to?(:categorization_metrics_optimized)
              strategy_class.categorization_metrics_optimized
            else
              strategy_class.categorization_metrics
            end
          end
        end
      end

      # Pattern metrics
      def pattern_metrics
        instrument_method(:pattern_metrics) do
          with_error_handling do
            if strategy_class.respond_to?(:pattern_metrics_optimized)
              strategy_class.pattern_metrics_optimized
            else
              strategy_class.pattern_metrics
            end
          end
        end
      end

      # Cache metrics
      def cache_metrics
        instrument_method(:cache_metrics) do
          with_error_handling do
            strategy_class.cache_metrics
          end
        end
      end

      # Performance metrics
      def performance_metrics
        instrument_method(:performance_metrics) do
          with_error_handling do
            strategy_class.performance_metrics
          end
        end
      end

      # Learning metrics
      def learning_metrics
        instrument_method(:learning_metrics) do
          with_error_handling do
            if strategy_class.respond_to?(:learning_metrics_optimized)
              strategy_class.learning_metrics_optimized
            else
              strategy_class.learning_metrics
            end
          end
        end
      end

      # System metrics
      def system_metrics
        instrument_method(:system_metrics) do
          with_error_handling do
            if strategy_class.respond_to?(:system_metrics_safe)
              strategy_class.system_metrics_safe
            else
              strategy_class.system_metrics
            end
          end
        end
      end

      # Switch strategy at runtime (useful for testing)
      def switch_strategy(new_strategy)
        @strategy_override = validate_strategy(new_strategy)
        clear_cache
        strategy_name
      end

      # Clear any cached metrics
      def clear_cache
        @mutex.synchronize do
          @metrics_cache.clear
          @cache_timestamps.clear
        end
      end

      # Get cache statistics
      def cache_stats
        @mutex.synchronize do
          {
            entries: @metrics_cache.size,
            timestamps: @cache_timestamps.transform_values { |t| Time.current - t }
          }
        end
      end

      private

      def determine_strategy
        @strategy_override || self.class.current_strategy
      end

      def strategy_class
        STRATEGIES[determine_strategy]
      end

      def validate_strategy(strategy)
        strategy = strategy.to_sym if strategy.is_a?(String)
        unless STRATEGIES.key?(strategy)
          raise ArgumentError, "Invalid strategy: #{strategy}. Must be one of: #{STRATEGIES.keys.join(', ')}"
        end
        strategy
      end

      def strategy_source
        if @strategy_override
          :override
        elsif ENV["DASHBOARD_STRATEGY"].present?
          :environment
        elsif Rails.configuration.x.categorization&.dig("monitoring", "dashboard_strategy")
          :config
        else
          :default
        end
      end

      def instrument_method(method_name)
        start_time = Time.current

        result = yield

        duration = (Time.current - start_time) * 1000
        log_slow_operation(method_name, duration) if duration > 100

        notify_instrumentation(method_name, duration, result)

        result
      rescue StandardError => e
        notify_error(method_name, e)
        raise
      end

      def with_error_handling
        yield
      rescue StandardError => e
        Rails.logger.error "Dashboard adapter error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n") if e.backtrace

        # Return fallback metrics
        {
          error: true,
          message: "Unable to fetch metrics: #{e.message}",
          timestamp: Time.current.iso8601
        }
      end

      def log_slow_operation(method_name, duration)
        Rails.logger.warn "Slow dashboard operation: #{method_name} took #{duration.round(2)}ms"
      end

      def notify_instrumentation(method_name, duration, result)
        ActiveSupport::Notifications.instrument(
          "dashboard_adapter.categorization",
          method: method_name,
          strategy: determine_strategy,
          duration: duration,
          result_size: result.is_a?(Hash) ? result.size : 0
        )

        # Send to StatsD if configured
        send_to_statsd(method_name, duration) if statsd_enabled?
      end

      def notify_error(method_name, error)
        ActiveSupport::Notifications.instrument(
          "dashboard_adapter.error",
          method: method_name,
          strategy: determine_strategy,
          error_class: error.class.name,
          error_message: error.message
        )
      end

      def statsd_enabled?
        Rails.configuration.x.categorization&.dig("monitoring", "enabled") == true
      rescue
        false
      end

      def send_to_statsd(method_name, duration)
        return unless defined?(StatsD) && StatsD.respond_to?(:timing)

        prefix = Rails.configuration.x.categorization&.dig("monitoring", "prefix") || "categorization"
        StatsD.timing("#{prefix}.dashboard.#{method_name}.duration", duration)
        StatsD.increment("#{prefix}.dashboard.#{method_name}.calls")
        StatsD.increment("#{prefix}.dashboard.strategy.#{determine_strategy}")
      rescue StandardError => e
        Rails.logger.debug "Failed to send metrics to StatsD: #{e.message}"
      end

      # Cache helper for expensive operations (optional future enhancement)
      def with_cache(key, ttl: 10.seconds)
        @mutex.synchronize do
          if @metrics_cache[key] && @cache_timestamps[key] && (Time.current - @cache_timestamps[key]) < ttl
            return @metrics_cache[key]
          end

          result = yield
          @metrics_cache[key] = result
          @cache_timestamps[key] = Time.current
          result
        end
      end
    end
  end
end
