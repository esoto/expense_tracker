# frozen_string_literal: true

# Service for centralized error tracking and monitoring
# Can be configured to use Sentry, Rollbar, or other error tracking services
module Services
  class Services::ErrorTrackingService
  include Singleton

  SEVERITY_LEVELS = {
    debug: 0,
    info: 1,
    warning: 2,
    error: 3,
    fatal: 4
  }.freeze

  def initialize
    @enabled = Rails.application.credentials.dig(:error_tracking, :enabled) || false
    @service = Rails.application.credentials.dig(:error_tracking, :service) || "logger"
    configure_service
  end

  # Track an exception with context
  def track_exception(exception, context = {})
    return unless tracking_enabled?

    enriched_context = enrich_context(context)

    case @service
    when "sentry"
      track_with_sentry(exception, enriched_context)
    when "rollbar"
      track_with_rollbar(exception, enriched_context)
    else
      track_with_logger(exception, enriched_context)
    end

    # Also log locally for debugging
    log_exception_locally(exception, enriched_context)
  rescue StandardError => e
    # Prevent error tracking from breaking the application
    Rails.logger.error "Error tracking failed: #{e.message}"
  end

  # Track a message without an exception
  def track_message(message, level = :info, context = {})
    return unless tracking_enabled?

    enriched_context = enrich_context(context)

    case @service
    when "sentry"
      Sentry.capture_message(message, level: level, extra: enriched_context) if defined?(Sentry)
    when "rollbar"
      Rollbar.log(level, message, enriched_context) if defined?(Rollbar)
    end

    # Always log locally
    Rails.logger.public_send(level, { message: message, context: enriched_context }.to_json)
  end

  # Track performance metrics
  def track_performance(operation, duration_ms, metadata = {})
    return unless tracking_enabled?

    performance_data = {
      operation: operation,
      duration_ms: duration_ms,
      timestamp: Time.current.iso8601
    }.merge(metadata)

    # Log performance metrics
    Rails.logger.info({ event: "performance_metric" }.merge(performance_data).to_json)

    # Send to monitoring service if configured
    if defined?(Sentry) && @service == "sentry"
      Sentry.capture_message(
        "Performance metric: #{operation}",
        level: :info,
        extra: performance_data
      )
    end
  end

  # Track bulk operation errors
  def track_bulk_operation_error(operation_type, error, context = {})
    track_exception(error, context.merge(
      operation_type: operation_type,
      subsystem: "bulk_categorization"
    ))
  end

  # Set user context for error tracking
  def set_user_context(user)
    return unless tracking_enabled? && user

    user_data = {
      id: user.id,
      email: user.email,
      role: user.role
    }

    case @service
    when "sentry"
      Sentry.set_user(user_data) if defined?(Sentry)
    when "rollbar"
      Rollbar.configure do |config|
        config.payload_options = {
          person: user_data
        }
      end if defined?(Rollbar)
    end
  end

  # Add breadcrumb for debugging
  def add_breadcrumb(message, category: "app", level: :info, data: {})
    return unless tracking_enabled?

    if defined?(Sentry) && @service == "sentry"
      Sentry.add_breadcrumb(
        message: message,
        category: category,
        level: level,
        data: data
      )
    end

    # Always log breadcrumbs locally in development
    if Rails.env.development?
      Rails.logger.debug "[Breadcrumb] #{category}: #{message} #{data.to_json}"
    end
  end

  private

  def configure_service
    case @service
    when "sentry"
      configure_sentry if defined?(Sentry)
    when "rollbar"
      configure_rollbar if defined?(Rollbar)
    end
  end

  def configure_sentry
    # Sentry configuration would typically be in an initializer
    # This is just for reference
    return unless defined?(Sentry)

    Sentry.init do |config|
      config.dsn = Rails.application.credentials.dig(:error_tracking, :sentry, :dsn)
      config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
      config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0
      config.environment = Rails.env
      config.enabled_environments = %w[production staging]
    end
  end

  def configure_rollbar
    # Rollbar configuration would typically be in an initializer
    return unless defined?(Rollbar)

    Rollbar.configure do |config|
      config.access_token = Rails.application.credentials.dig(:error_tracking, :rollbar, :access_token)
      config.environment = Rails.env
      config.enabled = Rails.env.production? || Rails.env.staging?
    end
  end

  def tracking_enabled?
    @enabled && !Rails.env.test?
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

  def track_with_sentry(exception, context)
    return unless defined?(Sentry)

    Sentry.capture_exception(exception, extra: context)
  end

  def track_with_rollbar(exception, context)
    return unless defined?(Rollbar)

    Rollbar.error(exception, context)
  end

  def track_with_logger(exception, context)
    Rails.logger.error(
      {
        event: "exception_tracked",
        exception_class: exception.class.name,
        exception_message: exception.message,
        backtrace: exception.backtrace&.first(10),
        context: context
      }.to_json
    )
  end

  def log_exception_locally(exception, context)
    Rails.logger.error "Exception: #{exception.class} - #{exception.message}"
    Rails.logger.error "Context: #{context.to_json}"
    Rails.logger.error "Backtrace: #{exception.backtrace&.first(5)&.join("\n")}" if Rails.env.development?
  end

  class << self
    delegate :track_exception, :track_message, :track_performance,
             :track_bulk_operation_error, :set_user_context, :add_breadcrumb,
             to: :instance
  end
end
end
