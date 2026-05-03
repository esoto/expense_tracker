# frozen_string_literal: true

# Sentry APM / error-tracking initializer (PER-526).
#
# Guards:
#   1. Skip entirely in test — sentry-rails registers middleware and starts
#      background threads which pollute test isolation.
#   2. Skip when no DSN is present (local dev without credentials, CI, etc.)
#      so the gem stays inert rather than queuing noise.
#
# DSN resolution order (mirrors LlmStrategy / PER-548 credential pattern):
#   1. Rails encrypted credentials  → sentry.dsn
#   2. ENV["SENTRY_DSN"]            → injected by Kamal env.secret in production
return if Rails.env.test?

dsn = Rails.application.credentials.dig(:sentry, :dsn).presence ||
      ENV["SENTRY_DSN"].presence
return if dsn.blank?

Sentry.init do |config|
  config.dsn = dsn
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  # Capture 10 % of transactions in production for performance tracing;
  # 0 in development to avoid performance overhead with no benefit.
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 0
  config.environment = Rails.env
  # KAMAL_VERSION is injected automatically by Kamal at container build time,
  # so Sentry release tracking aligns with the deployed image tag.
  config.release = ENV["KAMAL_VERSION"]

  # Strip request body params that are already covered by filter_parameters
  # (config/initializers/filter_parameter_logging.rb). Sentry respects Rails'
  # filter_parameters automatically for request data, but LLM prompts pass
  # merchant strings through the extra/context hash — those don't leak here
  # because track_exception only sends exception metadata + structured context.
  config.before_send = lambda do |event, _hint|
    event
  end
end
