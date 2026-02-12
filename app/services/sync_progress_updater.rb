module Services
  class SyncProgressUpdater
  attr_reader :sync_session, :batch_collector, :metrics_collector

  def initialize(sync_session, metrics_collector: nil)
    @sync_session = sync_session
    @batch_collector = ProgressBatchCollector.new(sync_session) if sync_session
    @metrics_collector = metrics_collector || (SyncMetricsCollector.new(sync_session) if sync_session)
  end

  def call
    return unless sync_session

    # Use a single query with calculated fields for better performance
    update_with_aggregated_data

    # Use batched progress updates for better performance
    broadcast_progress_update_batched

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

    # Use batched account update for better performance
    batch_collector&.add_account_update(
      account_id: account_id,
      status: account.status,
      processed: processed,
      total: total,
      detected: detected
    )

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
    # Track broadcast operation
    if @metrics_collector
      @metrics_collector.track_operation(:broadcast_update, nil, { type: "progress" }) do
        perform_broadcast
      end
    else
      perform_broadcast
    end
  rescue StandardError => e
    Rails.logger.error "Error broadcasting progress update: #{e.message}"
    # Don't fail the whole update if broadcasting fails
  end

  def perform_broadcast
    # Broadcast via Action Cable with enhanced reliability
    SyncStatusChannel.broadcast_progress(
      sync_session,
      sync_session.processed_emails,
      sync_session.total_emails,
      sync_session.detected_expenses
    )

    # Also trigger Turbo Stream broadcast for dashboard
    sync_session.broadcast_dashboard_update if sync_session.respond_to?(:broadcast_dashboard_update)
  end

  # New batched broadcasting method for improved performance
  def broadcast_progress_update_batched
    return unless batch_collector

    # Add progress update to batch collector
    batch_collector.add_progress_update(
      processed: sync_session.processed_emails,
      total: sync_session.total_emails,
      detected: sync_session.detected_expenses,
      metadata: {
        session_id: sync_session.id,
        status: sync_session.status,
        progress_percentage: sync_session.progress_percentage
      }
    )

    # Also trigger Turbo Stream broadcast for dashboard (non-batched)
    sync_session.broadcast_dashboard_update if sync_session.respond_to?(:broadcast_dashboard_update)
  rescue StandardError => e
    Rails.logger.error "Error broadcasting batched progress update: #{e.message}"
    # Fallback to direct broadcasting
    broadcast_progress_update
  end

  # Add activity updates to batch
  def add_activity_update(activity_type, message)
    return unless batch_collector

    batch_collector.add_activity_update(
      activity_type: activity_type,
      message: message
    )
  rescue StandardError => e
    Rails.logger.error "Error adding activity update to batch: #{e.message}"
    # Fallback to direct broadcast
    SyncStatusChannel.broadcast_activity(sync_session, activity_type, message)
  end

  # Add critical updates (bypass batching)
  def add_critical_update(type, message, data = {})
    return unless batch_collector

    batch_collector.add_critical_update(
      type: type,
      message: message,
      data: data
    )
  rescue StandardError => e
    Rails.logger.error "Error adding critical update: #{e.message}"
  end

  # Stop batch collector and flush remaining updates
  def finalize
    return unless batch_collector

    batch_collector.stop
    @batch_collector = nil
  end

  # Get batch collector statistics for monitoring
  def batch_stats
    batch_collector&.stats || {}
  end
  end
end
