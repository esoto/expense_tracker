class SyncSessionMonitorJob < ApplicationJob
  queue_as :default

  def perform(sync_session_id)
    sync_session = SyncSession.find_by(id: sync_session_id)
    return unless sync_session

    # Reload to get the latest status
    sync_session.reload

    # Don't monitor if already completed or failed
    return unless sync_session.running?

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
      # Still processing, check again in 5 seconds
      SyncSessionMonitorJob.set(wait: 5.seconds).perform_later(sync_session_id)
    end
  rescue => e
    Rails.logger.error "Error monitoring sync session #{sync_session_id}: #{e.message}"
    sync_session&.fail!(e.message)
  end
end
