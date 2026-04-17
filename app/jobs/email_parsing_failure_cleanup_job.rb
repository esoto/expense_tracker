# frozen_string_literal: true

# Background job that purges EmailParsingFailure rows older than
# EmailParsingFailure::RETENTION_DAYS.
#
# EmailParsingFailure.raw_email_content holds bank PII (amounts, merchants,
# account refs, recipient addresses, transaction times). PER-496 encrypts new
# rows at rest; this job enforces the companion retention window so historical
# failure data doesn't accumulate indefinitely.
#
# Scheduled daily at 4am via config/recurring.yml.
class EmailParsingFailureCleanupJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    Rails.logger.info "[EmailParsingFailureCleanup] Starting cleanup (retention=#{EmailParsingFailure::RETENTION_DAYS}d)..."

    # delete_all (not destroy_all): no before/after_destroy callbacks on
    # EmailParsingFailure, so bulk SQL DELETE is correct and fast. If a
    # callback is ever added, switch to destroy_all.
    count = EmailParsingFailure.expired.delete_all

    Rails.logger.info "[EmailParsingFailureCleanup] Cleanup complete: cleaned_up=#{count}"
  rescue StandardError => e
    Rails.logger.error "[EmailParsingFailureCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
