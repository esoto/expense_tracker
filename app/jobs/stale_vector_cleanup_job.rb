# frozen_string_literal: true

# Background job that removes stale categorization vectors.
#
# Deletes categorization_vector rows where last_seen_at is older than 6 months,
# using the existing .stale scope on CategorizationVector.
#
# Runs monthly via Solid Queue recurring schedule.
#
# Usage:
#   StaleVectorCleanupJob.perform_now   # Run immediately
#   StaleVectorCleanupJob.perform_later # Enqueue for background execution
class StaleVectorCleanupJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[StaleVectorCleanup] Starting monthly cleanup..."

    count = CategorizationVector.stale.delete_all

    Rails.logger.info "[StaleVectorCleanup] Cleanup complete: cleaned_up=#{count}"
  rescue StandardError => e
    Rails.logger.error "[StaleVectorCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
