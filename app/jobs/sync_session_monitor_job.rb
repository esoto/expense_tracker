class SyncSessionMonitorJob < ApplicationJob
  queue_as :email_processing

  # Gracefully stop polling when the SyncSession record is deleted mid-poll
  discard_on ActiveJob::DeserializationError

  # Retry on transient database deadlocks with exponential back-off (overrides ApplicationJob default)
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # PER-386: Cap rescheduling to ~10 minutes (120 × 5s) to prevent unbounded job accumulation
  MAX_RESCHEDULES = 120

  def perform(sync_session_id, reschedule_count = 0)
    sync_session = SyncSession.find_by(id: sync_session_id)
    return unless sync_session

    # Reload to get the latest status
    sync_session.reload

    # Don't monitor if already completed or failed
    return unless sync_session.running?

    # Timeout: force-fail sessions running longer than 30 minutes
    if sync_session.started_at && sync_session.started_at < 30.minutes.ago
      sync_session.fail!("Sync timed out after 30 minutes")
      Rails.logger.warn "Sync session #{sync_session_id} force-failed: exceeded 30-minute timeout"
      return
    end

    # PER-386: Stop rescheduling once the cap is reached
    if reschedule_count >= MAX_RESCHEDULES
      Rails.logger.warn "[SyncSessionMonitor] Max reschedules reached for session #{sync_session_id}"
      sync_session.fail!("Monitor timeout — max reschedules reached") if sync_session.running?
      return
    end

    # Check if all accounts are processed
    accounts = sync_session.sync_session_accounts
    all_done = accounts.all? { |sa| sa.completed? || sa.failed? }

    if all_done
      # Handle empty accounts case
      if accounts.empty?
        sync_session.complete!
        Rails.logger.info "Sync session #{sync_session_id} completed - no accounts to process"
      else
        # Check if all accounts failed
        all_failed = accounts.all?(&:failed?)

        if all_failed
          # Aggregate error messages
          error_messages = accounts.where.not(last_error: nil).pluck(:last_error)
          error_detail = error_messages.any? ? error_messages.join("; ") : "All accounts failed"
          sync_session.fail!(error_detail)
          Rails.logger.info "Sync session #{sync_session_id} failed - all accounts failed"
        else
          # Some succeeded, mark as completed (partial success)
          sync_session.complete!
          Rails.logger.info "Sync session #{sync_session_id} completed"
        end
      end
    else
      # Still processing, check again in 5 seconds with incremented counter
      SyncSessionMonitorJob.set(wait: 5.seconds).perform_later(sync_session_id, reschedule_count + 1)
    end
  rescue => e
    Rails.logger.error "Error monitoring sync session #{sync_session_id}: #{e.message}"
    sync_session&.fail!(e.message)
  end
end
