# frozen_string_literal: true

# Background job that removes expired LLM categorization cache entries.
#
# Deletes LlmCategorizationCacheEntry rows where expires_at is in the past,
# using the existing .expired scope.
#
# Runs monthly via Solid Queue recurring schedule.
#
# Usage:
#   LlmCacheCleanupJob.perform_now   # Run immediately
#   LlmCacheCleanupJob.perform_later # Enqueue for background execution
class LlmCacheCleanupJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    Rails.logger.info "[LlmCacheCleanup] Starting monthly cleanup..."

    count = LlmCategorizationCacheEntry.expired.delete_all

    Rails.logger.info "[LlmCacheCleanup] Cleanup complete: cleaned_up=#{count}"
  rescue StandardError => e
    Rails.logger.error "[LlmCacheCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
