class SyncProgressUpdater
  attr_reader :sync_session

  def initialize(sync_session)
    @sync_session = sync_session
  end

  def call
    return unless sync_session

    # Use a single query with calculated fields for better performance
    update_with_aggregated_data

    true
  rescue ActiveRecord::StaleObjectError
    # Handle optimistic locking conflicts gracefully
    handle_stale_object_error
  rescue StandardError => e
    Rails.logger.error "Error updating sync progress for session #{sync_session.id}: #{e.message}"
    false
  end

  def update_account_progress(account_id, processed:, total:, detected:)
    account = sync_session.sync_session_accounts.find_by(email_account_id: account_id)
    return unless account

    account.update!(
      processed_emails: processed,
      total_emails: total,
      detected_expenses: detected,
      status: determine_account_status(processed, total)
    )

    # Update session progress after account update
    call
  end

  private

  def update_with_aggregated_data
    # Use a single query to get all aggregated data
    aggregated = sync_session.sync_session_accounts
      .select(
        "COALESCE(SUM(total_emails), 0) as total",
        "COALESCE(SUM(processed_emails), 0) as processed",
        "COALESCE(SUM(detected_expenses), 0) as detected"
      )
      .first

    sync_session.update!(
      total_emails: aggregated.total,
      processed_emails: aggregated.processed,
      detected_expenses: aggregated.detected
    )
  end

  def handle_stale_object_error
    # Reload and retry once
    sync_session.reload
    update_with_aggregated_data
  rescue ActiveRecord::StaleObjectError => e
    # If it fails again, log and give up
    Rails.logger.warn "Persistent stale object error for sync session #{sync_session.id}: #{e.message}"
    false
  end

  def determine_account_status(processed, total)
    return "completed" if processed >= total && total > 0
    return "processing" if processed > 0
    "pending"
  end
end
