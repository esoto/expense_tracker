# frozen_string_literal: true

require "singleton"
require "forwardable"

module Services::Categorization
  module Monitoring
    # Singleton service for collecting and reporting metrics
    # Integrates with StatsD for production monitoring
    class MetricsCollector
      include Singleton
      extend Forwardable

      CONFIDENCE_BUCKETS = {
        very_high: 0.9..1.0,
        high: 0.7...0.9,
        medium: 0.5...0.7,
        low: 0.3...0.5,
        very_low: 0.0...0.3
      }.freeze

      attr_reader :client, :enabled, :prefix

      def initialize
        @enabled = Rails.configuration.x.categorization&.dig(:monitoring, :enabled) || false
        @prefix = Rails.configuration.x.categorization&.dig(:monitoring, :prefix) || "categorization"
        @client = initialize_client
        @mutex = Mutex.new
      end

      # Track categorization attempt metrics
      def track_categorization(expense_id:, success:, confidence:, duration_ms:, category_id: nil, method: nil)
        return unless enabled?

        @mutex.synchronize do
          # Track attempt
          increment("attempts.total")
          increment(success ? "attempts.success" : "attempts.failure")

          # Track by method if provided
          increment("attempts.by_method.#{method || 'unknown'}") if method

          # Track duration
          timing("duration", duration_ms)
          histogram("duration.distribution", duration_ms)

          # Track confidence
          if confidence
            gauge("confidence.last", confidence)
            histogram("confidence.distribution", confidence * 100)
            track_confidence_bucket(confidence)
          end

          # Track category distribution
          increment("categories.#{category_id || 'uncategorized'}") if success
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error tracking categorization: #{e.message}"
      end

      # Track cache performance
      def track_cache(operation:, cache_type:, hit:, duration_ms: nil)
        return unless enabled?

        @mutex.synchronize do
          cache_key = "cache.#{cache_type}"
          increment("#{cache_key}.#{operation}.total")
          increment("#{cache_key}.#{operation}.#{hit ? 'hit' : 'miss'}")

          if duration_ms
            timing("#{cache_key}.#{operation}.duration", duration_ms)
          end

          # Calculate and track hit rate
          track_hit_rate(cache_type)
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error tracking cache: #{e.message}"
      end

      # Track pattern learning events
      def track_learning(action:, pattern_type:, success:, confidence_change: nil)
        return unless enabled?

        @mutex.synchronize do
          learning_key = "learning.#{pattern_type}"
          increment("#{learning_key}.#{action}.total")
          increment("#{learning_key}.#{action}.#{success ? 'success' : 'failure'}")

          if confidence_change
            gauge("#{learning_key}.confidence_change", confidence_change)
            increment(confidence_change.positive? ? "#{learning_key}.improvements" : "#{learning_key}.degradations")
          end
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error tracking learning: #{e.message}"
      end

      # Track error events
      def track_error(error_type:, context: {})
        return unless enabled?

        @mutex.synchronize do
          increment("errors.total")
          increment("errors.by_type.#{error_type}")

          # Track error context if provided
          context.each do |key, value|
            next unless %i[service method].include?(key)
            increment("errors.by_#{key}.#{value}")
          end
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error tracking error: #{e.message}"
      end

      # Track system performance metrics
      def track_performance(metric_name:, value:, unit: nil)
        return unless enabled?

        @mutex.synchronize do
          performance_key = "performance.#{metric_name}"
          gauge(performance_key, value)

          # Track unit-specific metrics
          case unit
          when :percentage
            histogram("#{performance_key}.percentage", value * 100)
          when :bytes
            histogram("#{performance_key}.bytes", value)
          when :count
            increment("#{performance_key}.count", value)
          end
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error tracking performance: #{e.message}"
      end

      # Batch multiple metrics operations
      def batch(&block)
        return unless enabled?

        @mutex.synchronize do
          yield self
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Error in batch operation: #{e.message}"
      end

      # Get current metrics snapshot (for health checks)
      def snapshot
        return {} unless enabled?

        {
          enabled: true,
          prefix: prefix,
          client_connected: client_connected?
        }
      end

      private

      def enabled?
        @enabled && @client.present?
      end

      def initialize_client
        return nil unless @enabled

        # Try to use StatsD if available
        if defined?(::StatsD)
          host = Rails.configuration.x.categorization&.dig(:monitoring, :statsd_host) || "localhost"
          port = Rails.configuration.x.categorization&.dig(:monitoring, :statsd_port) || 8125

          ::StatsD.new(host, port).tap do |client|
            client.namespace = @prefix
          end
        elsif defined?(::Statsd)
          # Alternative StatsD client
          host = Rails.configuration.x.categorization&.dig(:monitoring, :statsd_host) || "localhost"
          port = Rails.configuration.x.categorization&.dig(:monitoring, :statsd_port) || 8125

          ::Statsd.new(host, port).tap do |client|
            client.namespace = @prefix
          end
        else
          Rails.logger.warn "[MetricsCollector] StatsD client not available. Metrics collection disabled."
          nil
        end
      rescue => e
        Rails.logger.error "[MetricsCollector] Failed to initialize StatsD client: #{e.message}"
        nil
      end

      def client_connected?
        return false unless @client

        # Simple connectivity check
        @client.increment("heartbeat", 0)
        true
      rescue
        false
      end

      def track_confidence_bucket(confidence)
        bucket = CONFIDENCE_BUCKETS.find { |_, range| range.include?(confidence) }&.first || :unknown
        increment("confidence.buckets.#{bucket}")
      end

      def track_hit_rate(cache_type)
        # This would typically query from a time-series database
        # For now, we just track the current operation
        # Real implementation would calculate: hits / (hits + misses)
      end

      # StatsD client methods
      def increment(metric, value = 1)
        @client&.increment(metric, value)
      end

      def gauge(metric, value)
        @client&.gauge(metric, value)
      end

      def timing(metric, value)
        @client&.timing(metric, value)
      end

      def histogram(metric, value)
        @client&.histogram(metric, value) if @client.respond_to?(:histogram)
      end

      # Class-level convenience methods
      class << self
        extend Forwardable

        def_delegators :instance,
                       :track_categorization,
                       :track_cache,
                       :track_learning,
                       :track_error,
                       :track_performance,
                       :batch,
                       :snapshot,
                       :enabled?
      end
    end
  end
end
