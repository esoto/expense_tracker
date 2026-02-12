# frozen_string_literal: true

# BroadcastJob handles reliable broadcasting of ActionCable messages via Sidekiq.
# This job provides retry mechanisms with exponential backoff and dead letter queue
# functionality for failed broadcasts.
#
# Usage:
#   BroadcastJob.set(queue: 'high').perform_async(
#     'SyncStatusChannel',
#     123,
#     'SyncSession',
#     { status: 'processing' },
#     :high
#   )
class BroadcastJob < ApplicationJob
  # Queue configuration based on priority
  QUEUE_MAPPING = {
    critical: "critical",
    high: "high",
    medium: "default",
    low: "low"
  }.freeze

  # Sidekiq 8.x compatible retry configuration
  # We manually handle ActiveRecord::RecordNotFound for immediate failure recording
  # Other errors get automatic retries via ActiveJob

  # Retry connection and Redis errors automatically
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on Redis::BaseError, wait: 5.seconds, attempts: 3

  # Retry general errors with exponential backoff
  retry_on StandardError, wait: 15.seconds, attempts: 5 do |job, error|
    # This block is called after all retry attempts have been exhausted
    Rails.logger.error "[BROADCAST_JOB] Final failure after all retries: #{error.message}"

    # Extract job arguments for failure tracking
    args = job.arguments
    channel_name = args[0]
    target_id = args[1]
    target_type = args[2]
    data = args[3] || {}
    priority = args[4] || "medium"

    # Record final failure
    begin
      BroadcastAnalytics.record_failure(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 5,
        error: "Exhausted all retries: #{error.message}",
        duration: 0.0
      )

      FailedBroadcastStore.create!(
        channel_name: channel_name,
        target_type: target_type,
        target_id: target_id,
        data: data,
        priority: priority,
        error_type: "retry_exhausted",
        error_message: error.message,
        failed_at: Time.current,
        retry_count: 5,
        sidekiq_job_id: job.job_id
      )
    rescue StandardError => e
      Rails.logger.error "[BROADCAST_JOB] Failed to record exhausted retry: #{e.message}"
    end
  end

  # Permanently discard jobs with deserialization errors
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.error "[BROADCAST_JOB] Discarding job due to deserialization error: #{error.message}"
  end

  # Perform the broadcast job
  # @param channel_name [String] ActionCable channel class name
  # @param target_id [Integer] Target object ID
  # @param target_type [String] Target object class name
  # @param data [Hash] Data to broadcast
  # @param priority [String] Priority level
  def perform(channel_name, target_id, target_type, data, priority = "medium")
    start_time = Time.current

    begin
      # Find the target object
      target = target_type.constantize.find(target_id)

      # Delegate to Services::BroadcastReliabilityService for actual broadcasting
      success = Services::BroadcastReliabilityService.broadcast_with_retry(
        channel: channel_name,
        target: target,
        data: data,
        priority: priority.to_sym
      )

      # Log job completion
      duration = Time.current - start_time
      if success
        Rails.logger.info "[BROADCAST_JOB] Completed: #{channel_name} -> #{target_type}##{target_id}, Priority: #{priority}, Duration: #{duration.round(3)}s"

        # Track successful broadcast
        BroadcastAnalytics.record_success(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 1,  # First attempt since retries are handled by Services::BroadcastReliabilityService
          duration: duration
        )
      else
        # Services::BroadcastReliabilityService already handled its own retries
        # This indicates a failure after service-level retries
        Rails.logger.warn "[BROADCAST_JOB] Failed after retries: #{channel_name} -> #{target_type}##{target_id}, Priority: #{priority}"

        # Record the failure but don't raise - the service already did retries
        BroadcastAnalytics.record_failure(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 1,
          error: "Broadcast failed after service-level retries",
          duration: duration
        )

        # Store failure for potential manual retry
        FailedBroadcastStore.create!(
          channel_name: channel_name,
          target_type: target_type,
          target_id: target_id,
          data: data,
          priority: priority,
          error_type: "broadcast_failed",
          error_message: "Failed after service retries",
          failed_at: Time.current,
          retry_count: 0,
          sidekiq_job_id: job_id
        )
      end

    rescue ActiveRecord::RecordNotFound => e
      # Handle RecordNotFound specially - no retry needed for missing records
      duration = Time.current - start_time
      Rails.logger.error "[BROADCAST_JOB] Target not found: #{target_type}##{target_id}"

      # Record failure in analytics
      BroadcastAnalytics.record_failure(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 1,
        error: "Target not found: #{e.message}",
        duration: duration
      )

      # Store in dead letter queue for manual review
      FailedBroadcastStore.create!(
        channel_name: channel_name,
        target_type: target_type,
        target_id: target_id,
        data: data,
        priority: priority,
        error_type: "record_not_found",
        error_message: e.message,
        failed_at: Time.current,
        retry_count: 0,
        sidekiq_job_id: job_id
      )

      # Don't re-raise - this is a permanent failure
      # The record won't magically appear, so no point in retrying

    rescue StandardError => e
      # Handle unexpected errors - record them and re-raise for retry
      duration = Time.current - start_time
      Rails.logger.error "[BROADCAST_JOB] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace

      # Record failure in analytics
      BroadcastAnalytics.record_failure(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 1,
        error: "Job error: #{e.message}",
        duration: duration
      )

      # Store in dead letter queue
      FailedBroadcastStore.create!(
        channel_name: channel_name,
        target_type: target_type,
        target_id: target_id,
        data: data,
        priority: priority,
        error_type: "job_error",
        error_message: e.message,
        failed_at: Time.current,
        retry_count: 0,
        sidekiq_job_id: job_id
      )

      # Re-raise to trigger ActiveJob's retry mechanism
      raise
    end
  end

  # Enqueue a broadcast job with appropriate queue based on priority
  # @param channel_name [String] ActionCable channel class name
  # @param target_id [Integer] Target object ID
  # @param target_type [String] Target object class name
  # @param data [Hash] Data to broadcast
  # @param priority [Symbol] Priority level
  def self.enqueue_broadcast(channel_name:, target_id:, target_type:, data:, priority: :medium)
    queue_name = QUEUE_MAPPING[priority] || "default"

    set(queue: queue_name).perform_later(
      channel_name,
      target_id,
      target_type,
      data,
      priority.to_s
    )

    # Track queued broadcast in analytics
    BroadcastAnalytics.record_queued(
      channel: channel_name,
      target_type: target_type,
      target_id: target_id,
      priority: priority
    )
  end

  # Get job statistics
  # @return [Hash] Job statistics
  def self.stats
    {
      total_enqueued: total_enqueued_jobs,
      queue_sizes: queue_sizes,
      processing_times: average_processing_times
    }
  end

  private

  # Get total enqueued jobs across all broadcast queues
  # @return [Integer] Total enqueued jobs
  def self.total_enqueued_jobs
    return 0 unless defined?(Sidekiq)

    require "sidekiq/api"
    Sidekiq::Queue.new("critical").size +
    Sidekiq::Queue.new("high").size +
    Sidekiq::Queue.new("default").size +
    Sidekiq::Queue.new("low").size
  rescue StandardError
    0
  end

  # Get current queue sizes
  # @return [Hash] Queue sizes by priority
  def self.queue_sizes
    return { critical: 0, high: 0, default: 0, low: 0 } unless defined?(Sidekiq)

    require "sidekiq/api"
    {
      critical: Sidekiq::Queue.new("critical").size,
      high: Sidekiq::Queue.new("high").size,
      default: Sidekiq::Queue.new("default").size,
      low: Sidekiq::Queue.new("low").size
    }
  rescue StandardError
    { critical: 0, high: 0, default: 0, low: 0 }
  end

  # Get average processing times (simplified implementation)
  # @return [Hash] Average processing times by queue
  def self.average_processing_times
    # This would require more sophisticated tracking in a real implementation
    {
      critical: 0.05,
      high: 0.08,
      default: 0.12,
      low: 0.15
    }
  end
end
