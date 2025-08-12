# frozen_string_literal: true

# Sidekiq 8.x configuration for broadcast reliability and background job processing
# This configuration ensures reliable processing of broadcast jobs with appropriate
# retry mechanisms and queue priorities.
#
# Sidekiq 8.x Changes:
# - Uses dead_max_jobs instead of dead_job_ttl (deprecated in 7.x, removed in 8.x)
# - Capsules support for isolated processing (new in 8.x)
# - Enhanced middleware configuration
# - Improved lifecycle callbacks
#
# Configuration follows Sidekiq 8.x best practices:
# https://github.com/sidekiq/sidekiq/blob/main/docs/8.0-Upgrade.md

require "sidekiq"
require "sidekiq/web"

# Redis connection configuration
# Sidekiq 8.x uses connection_pool internally, so we provide Redis config
redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  network_timeout: 5,
  pool_timeout: 5
  # Server uses RAILS_MAX_THREADS or 5 by default
  # Client uses 5 connections by default
}

Sidekiq.configure_server do |config|
  # Redis configuration
  config.redis = redis_config.merge(
    size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i
  )

  # Dead job configuration for Sidekiq 8.x
  # Controls the maximum number of jobs in the dead set (default: 10,000)
  # Old jobs are automatically pruned after 6 months
  config[:dead_max_jobs] = ENV.fetch("SIDEKIQ_DEAD_MAX_JOBS", 10_000).to_i

  # Configure concurrency (number of worker threads)
  # MUST be less than or equal to database pool size to avoid connection pool errors
  # Database pool is set by RAILS_MAX_THREADS (default: 5)
  max_threads = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
  default_concurrency = [ max_threads, 5 ].min  # Use smaller of pool size or 5
  config[:concurrency] = ENV.fetch("SIDEKIQ_CONCURRENCY", default_concurrency).to_i

  # Queue configuration with priorities for broadcast reliability
  # Higher weight means higher priority (processed more frequently)
  # Sidekiq 8.x supports both array and hash formats
  config[:queues] = [
    [ "critical", 6 ],  # Most important broadcasts
    [ "high", 4 ],      # High priority broadcasts
    [ "default", 2 ],   # Standard priority
    [ "low", 1 ]        # Background tasks
  ]

  # Sidekiq 8.x strict argument checking for production
  # Helps catch argument mismatches early
  config[:strict] = Rails.env.production?

  # Error handling and monitoring
  config.error_handlers << ->(error, context) do
    # Extract job details from context hash
    job_info = context[:job] || {}

    Rails.logger.error "[SIDEKIQ_ERROR] #{error.class}: #{error.message}"
    Rails.logger.error "[SIDEKIQ_ERROR] Job: #{job_info['class']} (JID: #{job_info['jid']})"
    Rails.logger.error "[SIDEKIQ_ERROR] Queue: #{job_info['queue']}, Retry: #{job_info['retry_count']}/#{job_info['retry']}"
    Rails.logger.error "[SIDEKIQ_ERROR] Args: #{job_info['args']&.inspect}"
    Rails.logger.error "[SIDEKIQ_ERROR] Backtrace:\n#{error.backtrace&.first(10)&.join("\n")}"

    # Optional: Send to error tracking service
    # Sentry.capture_exception(error, extra: context) if defined?(Sentry)
  end

  # Death handler for permanently failed jobs
  # Called when a job has exhausted all retries and moves to the dead set
  config.death_handlers << ->(job, ex) do
    Rails.logger.error "[SIDEKIQ_DEATH] Job died: #{job['class']} (JID: #{job['jid']}) - #{ex.message}"
    Rails.logger.error "[SIDEKIQ_DEATH] Queue: #{job['queue']}, Retries exhausted: #{job['retry_count']}/#{job['retry']}"

    # Handle BroadcastJob deaths specifically
    if job["class"] == "BroadcastJob" || job["wrapped"] == "BroadcastJob"
      begin
        # Extract job arguments
        channel_name = job.dig("args", 0)
        target_id = job.dig("args", 1)
        target_type = job.dig("args", 2)
        data = job.dig("args", 3) || {}
        priority = job.dig("args", 4) || "medium"

        # Record failure in analytics
        BroadcastAnalytics.record_failure(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: job["retry_count"] || 0,
          error: "Job died after #{job['retry_count'] || 0} retries: #{ex.message}",
          duration: 0.0
        )

        # Create failed broadcast record for manual recovery
        FailedBroadcastStore.create!(
          channel_name: channel_name,
          target_type: target_type,
          target_id: target_id,
          data: data,
          priority: priority,
          error_type: "job_death",
          error_message: ex.message,
          failed_at: Time.current,
          retry_count: job["retry_count"] || 0,
          sidekiq_job_id: job["jid"]
        )

        Rails.logger.info "[SIDEKIQ_DEATH] BroadcastJob failure recorded for manual recovery"
      rescue StandardError => e
        Rails.logger.error "[SIDEKIQ_DEATH] Failed to record broadcast job death: #{e.message}"
        Rails.logger.error "[SIDEKIQ_DEATH] #{e.backtrace&.first(5)&.join("\n")}"
      end
    end
  end

  # Lifecycle callbacks (Sidekiq 8.x enhanced callbacks)
  config.on(:startup) do
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Sidekiq #{Sidekiq::VERSION} server started"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Rails environment: #{Rails.env}"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Concurrency: #{config[:concurrency]} worker threads"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Queues: #{config[:queues].map { |q, w| "#{q}(weight:#{w})" }.join(', ')}"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Dead jobs max: #{config[:dead_max_jobs]}"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Redis: #{redis_config[:url]}"

    # Verify required models exist
    if defined?(BroadcastAnalytics) && defined?(FailedBroadcastStore)
      Rails.logger.info "[SIDEKIQ_LIFECYCLE] Broadcast reliability services configured"
    end
  end

  config.on(:quiet) do
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Server entering quiet mode (no new jobs)"
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Waiting for #{Sidekiq::ProcessSet.new.total_concurrency} jobs to finish"
  end

  config.on(:shutdown) do
    Rails.logger.info "[SIDEKIQ_LIFECYCLE] Server shutting down gracefully"

    # Optional: Perform cleanup tasks
    # ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  end

  config.on(:heartbeat) do
    # Called every 10 seconds by default
    # Useful for metrics collection or health checks
    # Rails.logger.debug "[SIDEKIQ_LIFECYCLE] Heartbeat - Workers: #{Sidekiq::ProcessSet.new.total_concurrency}"
  end

  # Sidekiq 8.x middleware configuration
  config.server_middleware do |chain|
    # Add custom middleware if needed
    # chain.add MyCustomMiddleware

    # Remove a default middleware if needed
    # chain.remove Sidekiq::Middleware::Server::RetryJobs
  end

  config.client_middleware do |chain|
    # Add client-side middleware if needed
    # chain.add MyClientMiddleware
  end

  # Sidekiq 8.x capsule configuration for isolation (optional)
  # Capsules allow running multiple isolated Sidekiq instances with different configurations
  # Useful for separating broadcast jobs from other background jobs
  #
  # Example: Create a dedicated capsule for critical broadcasts
  # config.capsule("broadcast") do |cap|
  #   cap.concurrency = 5
  #   cap.queues = %w[critical high]
  #
  #   # Capsule-specific error handler
  #   cap.error_handlers << ->(error, context) do
  #     Rails.logger.error "[BROADCAST_CAPSULE] Error: #{error.message}"
  #   end
  # end
end

Sidekiq.configure_client do |config|
  # Redis configuration for client (web app)
  config.redis = redis_config.merge(
    size: 5  # Client needs fewer connections than server
  )

  # Client middleware for job enqueuing
  config.client_middleware do |chain|
    # Add middleware to track job enqueuing if needed
    # chain.add MyEnqueueTracker
  end
end

# Sidekiq 8.x strict argument checking
# In production, ensures job arguments match the perform method signature
# In development/test, allows flexibility for easier debugging
Sidekiq.strict_args!(Rails.env.production?)

# Configure Sidekiq logger (Sidekiq 8.x uses default_configuration)
# The logger is configured per-configuration in Sidekiq 8.x
Sidekiq.default_configuration.logger = Rails.logger if Rails.logger
Sidekiq.default_configuration.logger.level = Rails.env.production? ? Logger::INFO : Logger::DEBUG

# Sidekiq Web UI authentication (for production)
if Rails.env.production?
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    # Use secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SIDEKIQ_WEB_USERNAME", "admin")) &&
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SIDEKIQ_WEB_PASSWORD", SecureRandom.hex(16)))
  end
end

# Rate limiting configuration for Sidekiq Web UI
if defined?(Rack::Attack)
  # Limit Sidekiq web interface access
  Rack::Attack.throttle("sidekiq-web/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/sidekiq")
  end

  # Stricter limit for non-GET requests to Sidekiq Web
  Rack::Attack.throttle("sidekiq-web-write/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/sidekiq") && !req.get?
  end
end

# Sidekiq Pro/Enterprise features (if available)
# if defined?(Sidekiq::Pro)
#   Sidekiq::Pro.reliable_fetch!
#   Sidekiq::Pro.reliable_scheduler!
# end
#
# if defined?(Sidekiq::Enterprise)
#   Sidekiq::Enterprise.rate_limiting!
#   Sidekiq::Enterprise.unique_jobs!
# end
