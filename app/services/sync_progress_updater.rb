class SyncProgressUpdater
  attr_reader :sync_session

  def initialize(sync_session)
    @sync_session = sync_session
  end

  def call
    return unless sync_session

    # Use a single query with calculated fields for better performance
    update_with_aggregated_data

    # Broadcast progress update via ActionCable
    broadcast_progress_update

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

    # Broadcast account-specific update
    SyncStatusChannel.broadcast_account_progress(sync_session, account)

    # Update session progress after account update
    call
  end

  private

  def update_with_aggregated_data
    # Use Arel.sql for safety with raw SQL
    totals = sync_session.sync_session_accounts
      .pluck(
        Arel.sql("COALESCE(SUM(total_emails), 0)"),
        Arel.sql("COALESCE(SUM(processed_emails), 0)"),
        Arel.sql("COALESCE(SUM(detected_expenses), 0)")
      )
      .first

    sync_session.update!(
      total_emails: totals[0] || 0,
      processed_emails: totals[1] || 0,
      detected_expenses: totals[2] || 0
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

  def broadcast_progress_update
    # Broadcast via Action Cable
    SyncStatusChannel.broadcast_progress(
      sync_session,
      sync_session.processed_emails,
      sync_session.total_emails,
      sync_session.detected_expenses
    )

    # Also trigger Turbo Stream broadcast for dashboard
    sync_session.broadcast_dashboard_update if sync_session.respond_to?(:broadcast_dashboard_update)
  rescue StandardError => e
    Rails.logger.error "Error broadcasting progress update: #{e.message}"
    # Don't fail the whole update if broadcasting fails
  end
end
