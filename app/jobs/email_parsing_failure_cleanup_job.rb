# frozen_string_literal: true

# Background job that purges EmailParsingFailure rows older than RETENTION_DAYS.
#
# EmailParsingFailure.raw_email_content holds bank PII (amounts, merchants,
# account refs, recipient addresses, transaction times). PER-496 encrypts new
# rows at rest; this job enforces the companion retention window so historical
# failure data doesn't accumulate indefinitely.
#
# Scheduled daily at 4am via config/recurring.yml.
class EmailParsingFailureCleanupJob < ApplicationJob
  RETENTION_DAYS = 30

  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    cutoff = RETENTION_DAYS.days.ago
    Rails.logger.info "[EmailParsingFailureCleanup] Starting cleanup (cutoff=#{cutoff.iso8601})..."

    count = EmailParsingFailure.where(created_at: ..cutoff).delete_all

    Rails.logger.info "[EmailParsingFailureCleanup] Cleanup complete: cleaned_up=#{count}"
  rescue StandardError => e
    Rails.logger.error "[EmailParsingFailureCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
