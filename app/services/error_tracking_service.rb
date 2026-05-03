# frozen_string_literal: true

# Service for centralized error tracking and monitoring.
#
# Routes exceptions to Sentry when it is initialized (DSN present, non-test
# environment). Falls back to structured Rails logging when Sentry is absent,
# so the service is always safe to call regardless of environment.
#
# Wired for Sentry in PER-526. The sentry-rails gem initializer
# (config/initializers/sentry.rb) handles Sentry.init — this service trusts
# `Sentry.initialized?` as the single source of truth so we never double-init.
module Services
  class ErrorTrackingService
    include Singleton

    # Track an exception with optional context hash.
    # Called by LlmStrategy#trip_auth_circuit! (partial PER-550 signal).
    def track_exception(exception, context = {})
      enriched = enrich_context(context)

      if sentry_active?
        Sentry.capture_exception(exception, extra: enriched)
      end

      log_exception_locally(exception, enriched)
    rescue StandardError => e
      # Never let error tracking crash the caller.
      Rails.logger.error "ErrorTrackingService#track_exception failed: #{e.message}"
    end

    # Track a plain message (no exception object).
    def track_message(message, level = :info, context = {})
      enriched = enrich_context(context)

      if sentry_active?
        Sentry.capture_message(message, level: level, extra: enriched)
      end

      Rails.logger.public_send(level, { message: message, context: enriched }.to_json)
    end

    # Add a breadcrumb to the current Sentry scope.
    def add_breadcrumb(message, category: "app", level: :info, data: {})
      if sentry_active?
        Sentry.add_breadcrumb(
          Sentry::Breadcrumb.new(
            message: message,
            category: category,
            level: level.to_s,
            data: data
          )
        )
      end

      Rails.logger.debug "[Breadcrumb] #{category}: #{message} #{data.to_json}" if Rails.env.development?
    end

    # Set the current user on the Sentry scope (call from a controller concern).
    def set_user(user_data)
      return unless sentry_active?

      Sentry.set_user(user_data)
    end

    # Convenience alias kept for callers that used the old API name.
    alias_method :set_user_context, :set_user

    # Track a bulk operation error — delegates to track_exception with enriched context.
    def track_bulk_operation_error(operation_type, error, context = {})
      track_exception(error, context.merge(
        operation_type: operation_type,
        subsystem: "bulk_categorization"
      ))
    end

    # Track a performance observation (structured log + optional Sentry message).
    def track_performance(operation, duration_ms, metadata = {})
      performance_data = {
        operation: operation,
        duration_ms: duration_ms,
        timestamp: Time.current.iso8601
      }.merge(metadata)

      Rails.logger.info({ event: "performance_metric" }.merge(performance_data).to_json)
    end

    class << self
      delegate :track_exception, :track_message, :track_performance,
               :track_bulk_operation_error, :set_user_context, :set_user,
               :add_breadcrumb,
               to: :instance
    end

    private

    # Returns true when Sentry is fully initialised (DSN present, non-test).
    # The initializer already skips test env, so this is a belt-and-suspenders
    # guard for direct unit testing of the service.
    def sentry_active?
      defined?(Sentry) && Sentry.initialized?
    end

    def enrich_context(context)
      {
        environment: Rails.env,
        hostname: Socket.gethostname,
        process_id: Process.pid,
        rails_version: Rails::VERSION::STRING,
        ruby_version: RUBY_VERSION,
        timestamp: Time.current.iso8601
      }.merge(context)
    end

    def log_exception_locally(exception, context)
      Rails.logger.error "Exception: #{exception.class} - #{exception.message}"
      Rails.logger.error "Context: #{context.to_json}"
      if Rails.env.development?
        Rails.logger.error "Backtrace: #{exception.backtrace&.first(5)&.join("\n")}"
      end
    end
  end
end
