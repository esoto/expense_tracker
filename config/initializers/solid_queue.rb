# frozen_string_literal: true

# Solid Queue configuration and optimizations
Rails.application.configure do
  # Configure Solid Queue settings
  if defined?(SolidQueue)
    # Set default job preservation period (keep completed jobs for analysis)
    config.solid_queue.preserve_finished_jobs = ENV.fetch("SOLID_QUEUE_PRESERVE_DAYS", 7).to_i.days

    # Configure shutdown timeout (grace period for jobs to finish)
    config.solid_queue.shutdown_timeout = ENV.fetch("SOLID_QUEUE_SHUTDOWN_TIMEOUT", 30).to_i.seconds

    # Enable performance logging in production
    if Rails.env.production?
      config.solid_queue.logger = Rails.logger
    end

    # Add instrumentation for monitoring
    ActiveSupport::Notifications.subscribe("enqueue.solid_queue") do |name, start, finish, id, payload|
      duration = (finish - start) * 1000.0
      job_class = payload[:job]&.class&.name || "Unknown"
      queue_name = payload[:job]&.queue_name || "default"

      Rails.logger.info "[SolidQueue] Enqueued #{job_class} to #{queue_name} (#{duration.round(2)}ms)"

      # Track metrics if available
      if defined?(StatsD)
        StatsD.increment("solid_queue.jobs.enqueued", tags: [ "job:#{job_class}", "queue:#{queue_name}" ])
        StatsD.histogram("solid_queue.enqueue.duration", duration, tags: [ "job:#{job_class}" ])
      end
    end

    ActiveSupport::Notifications.subscribe("perform.solid_queue") do |name, start, finish, id, payload|
      duration = (finish - start) * 1000.0
      job_class = payload[:job]&.class&.name || "Unknown"
      queue_name = payload[:job]&.queue_name || "default"
      status = payload[:exception] ? "failed" : "success"

      Rails.logger.info "[SolidQueue] Performed #{job_class} from #{queue_name} - #{status} (#{duration.round(2)}ms)"

      # Track metrics if available
      if defined?(StatsD)
        StatsD.increment("solid_queue.jobs.performed", tags: [ "job:#{job_class}", "queue:#{queue_name}", "status:#{status}" ])
        StatsD.histogram("solid_queue.perform.duration", duration, tags: [ "job:#{job_class}", "status:#{status}" ])
      end

      # Alert on slow jobs
      if duration > 30_000 && !payload[:exception]
        Rails.logger.warn "[SolidQueue] Slow job detected: #{job_class} took #{(duration / 1000).round(2)}s"
      end
    end

    ActiveSupport::Notifications.subscribe("discard.solid_queue") do |name, start, finish, id, payload|
      job_class = payload[:job]&.class&.name || "Unknown"
      error = payload[:error]

      Rails.logger.error "[SolidQueue] Discarded #{job_class} - Error: #{error}"

      # Track metrics if available
      if defined?(StatsD)
        StatsD.increment("solid_queue.jobs.discarded", tags: [ "job:#{job_class}" ])
      end
    end

    # Monitor queue depth periodically in production
    if Rails.env.production? && defined?(Rails.application) && Rails.application.initialized?
      Thread.new do
        loop do
          begin
            sleep 60 # Check every minute

            # Get queue metrics
            pending = SolidQueue::ReadyExecution.count rescue 0
            processing = SolidQueue::ClaimedExecution.count rescue 0
            failed = SolidQueue::FailedExecution.count rescue 0

            # Log metrics
            Rails.logger.info "[SolidQueue] Queue Status - Pending: #{pending}, Processing: #{processing}, Failed: #{failed}"

            # Alert on high queue depth
            if pending > 1000
              Rails.logger.warn "[SolidQueue] High queue depth detected: #{pending} pending jobs"
            end

            # Alert on high failure rate
            if failed > 100
              Rails.logger.error "[SolidQueue] High failure count detected: #{failed} failed jobs"
            end
          rescue => e
            Rails.logger.error "[SolidQueue] Monitoring error: #{e.message}"
          end
        end
      end
    end
  end
end

# Helper methods for job monitoring (optional extensions)
# These can be used by the QueueMonitor service for enhanced functionality
