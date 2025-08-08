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

  # Configure retry behavior - we handle retries in BroadcastReliabilityService
  sidekiq_options retry: false, dead: true

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

      # Delegate to BroadcastReliabilityService for actual broadcasting
      success = BroadcastReliabilityService.broadcast_with_retry(
        channel: channel_name,
        target: target,
        data: data,
        priority: priority.to_sym
      )

      # Log job completion
      duration = Time.current - start_time
      if success
        Rails.logger.info "[BROADCAST_JOB] Completed: #{channel_name} -> #{target_type}##{target_id}, Priority: #{priority}, Duration: #{duration.round(3)}s"
      else
        Rails.logger.warn "[BROADCAST_JOB] Failed after retries: #{channel_name} -> #{target_type}##{target_id}, Priority: #{priority}"
      end

    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "[BROADCAST_JOB] Target not found: #{target_type}##{target_id}"

      # Record failure in analytics
      BroadcastAnalytics.record_failure(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 1,
        error: "Target not found: #{e.message}",
        duration: (Time.current - start_time).to_f
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
        retry_count: 0
      )

    rescue StandardError => e
      Rails.logger.error "[BROADCAST_JOB] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Record failure in analytics
      duration = Time.current - start_time
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
        retry_count: 0
      )

      # Re-raise to trigger Sidekiq's dead job handling
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

    set(queue: queue_name).perform_async(
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
    Sidekiq::Queue.new("critical").size +
    Sidekiq::Queue.new("high").size +
    Sidekiq::Queue.new("default").size +
    Sidekiq::Queue.new("low").size
  end

  # Get current queue sizes
  # @return [Hash] Queue sizes by priority
  def self.queue_sizes
    {
      critical: Sidekiq::Queue.new("critical").size,
      high: Sidekiq::Queue.new("high").size,
      default: Sidekiq::Queue.new("default").size,
      low: Sidekiq::Queue.new("low").size
    }
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
