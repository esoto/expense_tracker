# frozen_string_literal: true

# Background job that purges QueuedEmailPayload rows past their retention
# window.
#
# QueuedEmailPayload holds the encrypted bank-email body/pre-parsed data that
# ProcessEmailJob consumes (2026-08 audit fix — see QueuedEmailPayload for the
# full rationale). Two retention windows, matching the model's constants:
#
#   - processed rows (ProcessEmailJob already consumed them): purge quickly
#     (QueuedEmailPayload::PROCESSED_RETENTION, 7 days) — they're transient
#     scratch data with no further use.
#   - unprocessed rows (still awaiting a retry, or stuck): kept much longer
#     (QueuedEmailPayload::UNPROCESSED_RETENTION, 30 days) so retries and a
#     backlogged/paused queue still have data to work with, and so an
#     operator has time to notice a stuck queue before payload data
#     disappears.
#
# Scheduled daily via config/recurring.yml, alongside the other PII retention
# jobs (EmailParsingFailureCleanupJob, SolidQueueFailedExecutionCleanupJob).
class QueuedEmailPayloadCleanupJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    Rails.logger.info "[QueuedEmailPayloadCleanup] Starting cleanup " \
      "(processed_retention=#{QueuedEmailPayload::PROCESSED_RETENTION.inspect}, " \
      "unprocessed_retention=#{QueuedEmailPayload::UNPROCESSED_RETENTION.inspect})..."

    # delete_all (not destroy_all): no before/after_destroy callbacks on
    # QueuedEmailPayload, so bulk SQL DELETE is correct and fast (matches the
    # EmailParsingFailureCleanupJob / SolidQueueFailedExecutionCleanupJob
    # pattern).
    processed_count = QueuedEmailPayload.expired_processed.delete_all
    unprocessed_count = QueuedEmailPayload.expired_unprocessed.delete_all

    Rails.logger.info "[QueuedEmailPayloadCleanup] Cleanup complete: " \
      "processed_cleaned_up=#{processed_count}, unprocessed_cleaned_up=#{unprocessed_count}"
  rescue StandardError => e
    Rails.logger.error "[QueuedEmailPayloadCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
