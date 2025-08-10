# frozen_string_literal: true

# Sidekiq configuration for broadcast reliability and background job processing
# This configuration ensures reliable processing of broadcast jobs with appropriate
# retry mechanisms and queue priorities.

require "sidekiq"
require "sidekiq/web"

# Redis connection configuration
redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  network_timeout: 5,
  pool_timeout: 5,
  size: ENV.fetch("REDIS_POOL_SIZE", 25).to_i
}

Sidekiq.configure_server do |config|
  config.redis = redis_config

  # Configure job retry behavior
  config.default_job_options = {
    "retry" => 3,
    "dead_job_ttl" => 6.months.to_i,
    "backtrace" => true
  }

  # Queue configuration with priorities for broadcast reliability
  config.queues = %w[critical high default low]

  # Error handling and monitoring
  config.error_handlers << ->(error, context) do
    Rails.logger.error "Sidekiq error: #{error.message}"
    Rails.logger.error "Context: #{context.inspect}"
  end

  # Death handler for failed jobs
  config.death_handlers << ->(job, ex) do
    Rails.logger.error "Sidekiq job died: #{job['class']} - #{ex.message}"

    # Handle BroadcastJob deaths specifically
    if job["class"] == "BroadcastJob"
      begin
        BroadcastAnalytics.record_failure(
          channel: job["args"][0],
          target_type: job["args"][2],
          target_id: job["args"][1],
          priority: job["args"][4],
          attempt: job["retry_count"] || 0,
          error: "Job died: #{ex.message}",
          duration: 0.0
        )

        # Create failed broadcast record for manual recovery
        FailedBroadcastStore.create!(
          channel_name: job["args"][0],
          target_type: job["args"][2],
          target_id: job["args"][1],
          data: job["args"][3] || {},
          priority: job["args"][4] || "medium",
          error_type: "job_death",
          error_message: ex.message,
          failed_at: Time.current,
          retry_count: job["retry_count"] || 0,
          sidekiq_job_id: job["jid"]
        )
      rescue StandardError => e
        Rails.logger.error "Failed to record broadcast job death: #{e.message}"
      end
    end
  end

  # Lifecycle callbacks
  config.on(:startup) do
    Rails.logger.info "Sidekiq server started with #{config.options[:concurrency]} workers"
    Rails.logger.info "Processing queues: #{config.queues.join(', ')}"
  end

  config.on(:shutdown) do
    Rails.logger.info "Sidekiq server shutting down"
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

# Allow for flexible argument passing in development
Sidekiq.strict_args!(Rails.env.production?)

# Rate limiting configuration
if defined?(Rack::Attack)
  # Limit Sidekiq web interface access
  Rack::Attack.throttle("sidekiq-web", limit: 20, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/sidekiq")
  end
end
