# frozen_string_literal: true

require "json"
require "securerandom"

module Services::Categorization
  module Monitoring
    # Structured logging service for categorization events
    # Provides JSON-formatted logs with correlation IDs for tracing
    class StructuredLogger
      SENSITIVE_FIELDS = %i[api_token password secret_key access_token].freeze
      LOG_LEVELS = {
        debug: Logger::DEBUG,
        info: Logger::INFO,
        warn: Logger::WARN,
        error: Logger::ERROR,
        fatal: Logger::FATAL
      }.freeze

      attr_reader :logger, :context

      def initialize(logger: nil, context: {})
        @logger = logger || Rails.logger
        @context = default_context.merge(context)
        @correlation_id = generate_correlation_id
      end

      # Log categorization event
      def log_categorization(event_type:, expense:, result:, metadata: {})
        log_event(
          level: :info,
          event: "categorization.#{event_type}",
          data: build_categorization_data(expense, result, metadata)
        )
      end

      # Log pattern learning event
      def log_learning(action:, pattern:, changes: {}, metadata: {})
        log_event(
          level: :info,
          event: "learning.#{action}",
          data: build_learning_data(pattern, changes, metadata)
        )
      end

      # Log error with context
      def log_error(error:, context: {}, metadata: {})
        log_event(
          level: :error,
          event: "error.#{error.class.name.underscore}",
          data: build_error_data(error, context, metadata)
        )
      end

      # Log performance metrics
      def log_performance(operation:, duration_ms:, metadata: {})
        log_event(
          level: :debug,
          event: "performance.#{operation}",
          data: {
            duration_ms: duration_ms,
            **metadata
          }
        )
      end

      # Log cache operation
      def log_cache(operation:, cache_type:, key:, hit:, metadata: {})
        log_event(
          level: :debug,
          event: "cache.#{operation}",
          data: {
            cache_type: cache_type,
            key: sanitize_cache_key(key),
            hit: hit,
            **metadata
          }
        )
      end

      # Log with correlation ID
      def with_correlation_id(correlation_id = nil)
        old_correlation_id = @correlation_id
        @correlation_id = correlation_id || generate_correlation_id

        yield self
      ensure
        @correlation_id = old_correlation_id
      end

      # Add context for a block
      def with_context(additional_context)
        old_context = @context
        @context = @context.merge(additional_context)

        yield self
      ensure
        @context = old_context
      end

      # Generic structured log
      def log(level:, message:, data: {})
        log_event(
          level: level,
          event: "custom",
          message: message,
          data: data
        )
      end

      # Create child logger with inherited context
      def child(additional_context = {})
        self.class.new(
          logger: @logger,
          context: @context.merge(additional_context)
        ).tap do |child_logger|
          child_logger.instance_variable_set(:@correlation_id, @correlation_id)
        end
      end

      private

      def log_event(level:, event:, data: {}, message: nil)
        log_level = LOG_LEVELS[level] || Logger::INFO

        log_entry = build_log_entry(
          event: event,
          message: message,
          data: sanitize_data(data)
        )

        @logger.add(log_level, log_entry.to_json)
      rescue => e
        # Fallback to regular logging if JSON formatting fails
        @logger.error "StructuredLogger error: #{e.message}"
        @logger.add(log_level, "#{event}: #{data.inspect}")
      end

      def build_log_entry(event:, message: nil, data: {})
        {
          timestamp: Time.current.iso8601(3),
          correlation_id: @correlation_id,
          event: event,
          message: message,
          level: Thread.current[:log_level] || "info",
          service: "categorization",
          environment: Rails.env,
          **@context,
          data: data
        }.compact
      end

      def build_categorization_data(expense, result, metadata)
        {
          expense_id: expense.id,
          description: truncate_string(expense.description, 100),
          amount: expense.amount,
          transaction_date: expense.transaction_date&.iso8601,
          result: {
            category_id: result&.category_id,
            category_name: result&.category&.name,
            confidence: result&.confidence,
            method: result&.method,
            rule_matched: result&.metadata&.dig(:rule_id),
            processing_time_ms: result&.metadata&.dig(:processing_time_ms)
          }.compact,
          **metadata
        }.compact
      end

      def build_learning_data(pattern, changes, metadata)
        {
          pattern_id: pattern.id,
          pattern_type: pattern.class.name,
          pattern_value: truncate_string(pattern.respond_to?(:pattern_value) ? pattern.pattern_value : pattern.to_s, 50),
          category_id: pattern.category_id,
          changes: {
            confidence_before: changes[:confidence_before],
            confidence_after: changes[:confidence_after],
            confidence_change: changes[:confidence_change],
            activation_count_before: changes[:activation_count_before],
            activation_count_after: changes[:activation_count_after]
          }.compact,
          **metadata
        }.compact
      end

      def build_error_data(error, context, metadata)
        {
          error_class: error.class.name,
          error_message: error.message,
          error_backtrace: clean_backtrace(error.backtrace),
          context: context,
          **metadata
        }.compact
      end

      def default_context
        {
          hostname: Socket.gethostname,
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          rails_version: Rails.version,
          ruby_version: RUBY_VERSION
        }
      rescue
        {}
      end

      def generate_correlation_id
        "cat_#{SecureRandom.hex(8)}"
      end

      def sanitize_data(data)
        case data
        when Hash
          data.transform_values { |v| sanitize_data(v) }
              .reject { |k, _| SENSITIVE_FIELDS.include?(k.to_sym) }
        when Array
          data.map { |v| sanitize_data(v) }
        when String
          # Redact potential sensitive patterns
          data.gsub(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, "[EMAIL]")
              .gsub(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/, "[CARD]")
              .gsub(/\b\d{3}-\d{2}-\d{4}\b/, "[SSN]")
        else
          data
        end
      end

      def sanitize_cache_key(key)
        # Remove potentially sensitive parts from cache keys
        key.to_s.gsub(/user_\d+/, "user_[ID]")
           .gsub(/expense_\d+/, "expense_[ID]")
      end

      def truncate_string(str, max_length)
        return nil if str.nil?
        return str if str.length <= max_length

        "#{str[0...max_length]}..."
      end

      def clean_backtrace(backtrace)
        return nil if backtrace.nil?

        # Keep only app-specific lines and limit to 10 lines
        backtrace
          .select { |line| line.include?(Rails.root.to_s) }
          .map { |line| line.sub(Rails.root.to_s, "[APP_ROOT]") }
          .first(10)
      end

      # Class-level convenience methods
      class << self
        def default
          @default ||= new
        end

        def log_categorization(...)
          default.log_categorization(...)
        end

        def log_learning(...)
          default.log_learning(...)
        end

        def log_error(...)
          default.log_error(...)
        end

        def log_performance(...)
          default.log_performance(...)
        end

        def log_cache(...)
          default.log_cache(...)
        end

        def with_correlation_id(...)
          default.with_correlation_id(...)
        end

        def with_context(...)
          default.with_context(...)
        end
      end
    end
  end
end
