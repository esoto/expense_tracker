# frozen_string_literal: true

# Sentry APM / error-tracking initializer (PER-526).
#
# Guards:
#   1. Skip in test — sentry-rails middleware/background threads pollute test
#      isolation.
#   2. Skip in dev — even if a DSN is present locally (someone testing the
#      smoke-event flow), don't ship dev exceptions to the shared production
#      project. Restored after PR-#513 review caught the regression.
#   3. Skip when no DSN is present (CI, fresh prod before SENTRY_DSN ships).
#
# DSN resolution order (mirrors LlmStrategy / PER-548 credential pattern):
#   1. Rails encrypted credentials  → sentry.dsn
#   2. ENV["SENTRY_DSN"]            → injected by Kamal env.secret in production
return if Rails.env.test?

unless Rails.env.production? || Rails.env.staging?
  Rails.logger.info "[Sentry] disabled — only enabled in production/staging (current: #{Rails.env})"
  return
end

dsn = Rails.application.credentials.dig(:sentry, :dsn).presence ||
      ENV["SENTRY_DSN"].presence

if dsn.blank?
  Rails.logger.info "[Sentry] disabled — DSN absent (set sentry.dsn in credentials or SENTRY_DSN env)"
  return
end

Sentry.init do |config|
  config.dsn = dsn
  # Belt-and-suspenders gate; matches the early return above.
  config.enabled_environments = %w[production staging]

  # Default breadcrumb subscriptions, MINUS sql.active_record. The default
  # logger ships SQL into every event; for a bank-ledger app, raw SQL with
  # interpolated literals (e.g., merchant_normalized) leaks PII alongside
  # every captured exception. send_default_pii=false (Sentry default) covers
  # request body/cookies/auth headers, but the SQL breadcrumb is a separate
  # surface — drop it explicitly.
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.rails.skippable_job_adapters = [] # opt-in to ActiveJob auto-instrumentation
  # The sentry-rails default adds sql.active_record to the active_support_logger
  # subscriptions. Remove it post-init via the configuration's exclusion API.
  if defined?(config.rails.active_support_logger_subscription_items)
    config.rails.active_support_logger_subscription_items.delete("sql.active_record")
    config.rails.active_support_logger_subscription_items.delete("instantiation.active_record")
  end

  # Capture 10 % of transactions in production for performance tracing.
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 0
  config.environment = Rails.env

  # KAMAL_VERSION is injected automatically by Kamal at container build time,
  # so Sentry release tracking aligns with the deployed image tag.
  config.release = ENV["KAMAL_VERSION"]

  # send_default_pii is already false by default in sentry-ruby — meaning
  # request body, query string, cookies, and Authorization headers are
  # stripped before send. We rely on that default + the SQL breadcrumb
  # exclusion above; no custom before_send needed (the previous identity
  # lambda was misleading — it filtered nothing).
end

Rails.logger.info "[Sentry] initialized for #{Rails.env} (release=#{ENV['KAMAL_VERSION'].presence || 'unset'})"
