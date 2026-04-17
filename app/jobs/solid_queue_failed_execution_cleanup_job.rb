# frozen_string_literal: true

# Background job that purges SolidQueue::FailedExecution rows older than
# RETENTION_DAYS to prevent unbounded growth of the queue.failed_executions
# table (PER-503).
#
# Context: config/recurring.yml already clears Solid Queue *finished* jobs via
# SolidQueue::Job.clear_finished_in_batches, but failed executions accumulate
# forever. Over months of production, this bloats the queue database.
#
# Retention matches PER-496 (email parsing failures): 30 days. The constant
# lives on this job (not on SolidQueue::FailedExecution) because we don't own
# the gem's model.
#
# Scheduled daily at 4:15am via config/recurring.yml (offset from the 4:00am
# PER-496 email-parsing cleanup to spread load).
class SolidQueueFailedExecutionCleanupJob < ApplicationJob
  RETENTION_DAYS = 30

  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    Rails.logger.info "[SolidQueueFailedExecutionCleanup] Starting cleanup (retention=#{RETENTION_DAYS}d)..."

    # delete_all (not destroy_all): SolidQueue::FailedExecution has no
    # before/after_destroy callbacks we care about. Bulk SQL DELETE is fast
    # and keeps the queue DB clean. The `created_at: ..cutoff` beginless range
    # emits `created_at <= $1` (inclusive) — matches the PER-496 pattern and
    # is more idiomatic than a raw SQL fragment.
    #
    # Scaling note: at current volume (dozens to low hundreds of rows per
    # month), a single DELETE is fine. If solid_queue_failed_executions ever
    # grows past ~10k rows, switch to `find_each(batch_size: 1000)` or add
    # a custom `db/queue_migrate/` index on created_at (the gem ships only
    # an index on job_id).
    count = SolidQueue::FailedExecution
              .where(created_at: ..RETENTION_DAYS.days.ago)
              .delete_all

    Rails.logger.info "[SolidQueueFailedExecutionCleanup] Cleanup complete: cleaned_up=#{count}"
  rescue StandardError => e
    Rails.logger.error "[SolidQueueFailedExecutionCleanup] Cleanup failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
