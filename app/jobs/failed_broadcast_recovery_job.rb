# frozen_string_literal: true

# FailedBroadcastRecoveryJob attempts to recover failed broadcasts from the dead letter queue.
# This job runs periodically to retry broadcasts that failed due to temporary issues.
#
# Usage:
#   FailedBroadcastRecoveryJob.perform_async
class FailedBroadcastRecoveryJob < ApplicationJob
  queue_as :low

  # Maximum number of broadcasts to process in one run to avoid overwhelming the system
  MAX_RECOVERY_BATCH_SIZE = 50

  def perform
    Rails.logger.info "[FAILED_BROADCAST_RECOVERY] Starting recovery job"

    recovery_stats = {
      attempted: 0,
      successful: 0,
      failed: 0,
      skipped: 0
    }

    # Get failed broadcasts ready for retry, ordered by priority and age
    failed_broadcasts = FailedBroadcastStore.ready_for_retry
                                          .recent_failures
                                          .limit(MAX_RECOVERY_BATCH_SIZE)

    Rails.logger.info "[FAILED_BROADCAST_RECOVERY] Found #{failed_broadcasts.count} broadcasts ready for recovery"

    failed_broadcasts.find_each do |failed_broadcast|
      recovery_stats[:attempted] += 1

      begin
        # Skip if target no longer exists
        unless failed_broadcast.target_exists?
          Rails.logger.debug "[FAILED_BROADCAST_RECOVERY] Skipping #{failed_broadcast.id}: target no longer exists"
          failed_broadcast.update!(
            error_type: "record_not_found",
            error_message: "Target #{failed_broadcast.target_type}##{failed_broadcast.target_id} no longer exists"
          )
          recovery_stats[:skipped] += 1
          next
        end

        # Attempt recovery
        if failed_broadcast.retry_broadcast!(manual: false)
          recovery_stats[:successful] += 1
          Rails.logger.info "[FAILED_BROADCAST_RECOVERY] Successfully recovered: #{failed_broadcast.channel_name} -> #{failed_broadcast.target_type}##{failed_broadcast.target_id}"
        else
          recovery_stats[:failed] += 1
          Rails.logger.warn "[FAILED_BROADCAST_RECOVERY] Failed to recover: #{failed_broadcast.channel_name} -> #{failed_broadcast.target_type}##{failed_broadcast.target_id}"
        end

      rescue StandardError => e
        recovery_stats[:failed] += 1
        Rails.logger.error "[FAILED_BROADCAST_RECOVERY] Error recovering broadcast #{failed_broadcast.id}: #{e.message}"

        # Update the failed broadcast with the new error
        failed_broadcast.update!(
          error_type: FailedBroadcastStore.classify_error(e),
          error_message: e.message
        )
      end

      # Small delay to avoid overwhelming the system
      sleep(0.1) if recovery_stats[:attempted] % 10 == 0
    end

    # Log final statistics
    Rails.logger.info "[FAILED_BROADCAST_RECOVERY] Recovery completed: #{recovery_stats[:successful]} successful, #{recovery_stats[:failed]} failed, #{recovery_stats[:skipped]} skipped out of #{recovery_stats[:attempted]} attempted"

    # Record recovery metrics in analytics
    record_recovery_metrics(recovery_stats)

    recovery_stats
  end

  private

  # Record recovery metrics for monitoring
  # @param stats [Hash] Recovery statistics
  def record_recovery_metrics(stats)
    Rails.cache.write(
      "failed_broadcast_recovery:last_run",
      {
        timestamp: Time.current.iso8601,
        stats: stats
      },
      expires_in: 24.hours
    )
  end
end
