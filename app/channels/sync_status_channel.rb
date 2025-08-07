class SyncStatusChannel < ApplicationCable::Channel
  def subscribed
    if params[:session_id].present?
      session = SyncSession.find_by(id: params[:session_id])

      if session
        stream_for session

        # Send initial status on subscription
        transmit({
          type: "initial_status",
          status: session.status,
          progress_percentage: session.progress_percentage,
          processed_emails: session.processed_emails,
          total_emails: session.total_emails,
          detected_expenses: session.detected_expenses,
          accounts: build_accounts_data(session)
        })
      else
        reject
      end
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end

  # Class methods for broadcasting
  class << self
    def broadcast_progress(session, processed, total, detected = nil)
      return unless session

      data = {
        type: "progress_update",
        status: session.status,
        progress_percentage: session.progress_percentage,
        processed_emails: processed,
        total_emails: total,
        detected_expenses: detected || session.detected_expenses,
        time_remaining: format_time_remaining(session.estimated_time_remaining)
      }

      broadcast_to(session, data)
    end

    def broadcast_account_progress(session, account)
      return unless session && account

      data = {
        type: "account_update",
        account_id: account.email_account_id,  # Use email_account_id for DOM matching
        sync_account_id: account.id,  # Keep sync account ID for reference
        status: account.status,
        progress: account.progress_percentage,
        processed: account.processed_emails,
        total: account.total_emails,
        detected: account.detected_expenses
      }

      broadcast_to(session, data)
    end

    def broadcast_account_update(session, email_account_id, status, processed, total, detected)
      return unless session

      data = {
        type: "account_update",
        account_id: email_account_id,
        status: status,
        progress: total > 0 ? ((processed.to_f / total) * 100).round : 0,
        processed: processed,
        total: total,
        detected: detected
      }

      broadcast_to(session, data)
    end

    def broadcast_activity(session, activity_type, message)
      return unless session

      data = {
        type: "activity",
        activity_type: activity_type,
        message: message,
        timestamp: Time.current.iso8601
      }

      broadcast_to(session, data)
    end

    def broadcast_completion(session)
      return unless session

      data = {
        type: "completed",
        status: "completed",
        progress_percentage: 100,
        processed_emails: session.processed_emails,
        total_emails: session.total_emails,
        detected_expenses: session.detected_expenses,
        duration: format_duration(session.duration),
        message: "Sincronización completada exitosamente"
      }

      broadcast_to(session, data)
    end

    def broadcast_failure(session, error_message = nil)
      return unless session

      data = {
        type: "failed",
        status: "failed",
        error: error_message || session.error_details || "Error durante la sincronización",
        processed_emails: session.processed_emails,
        total_emails: session.total_emails
      }

      broadcast_to(session, data)
    end

    def broadcast_status(session)
      return unless session

      session.reload
      accounts_data = session.sync_session_accounts.includes(:email_account).map do |account|
        {
          id: account.id,
          email: account.email_account.email,
          bank: account.email_account.bank_name,
          status: account.status,
          progress: account.progress_percentage,
          processed: account.processed_emails,
          total: account.total_emails,
          detected: account.detected_expenses
        }
      end

      data = {
        type: "status_update",
        status: session.status,
        progress_percentage: session.progress_percentage,
        processed_emails: session.processed_emails,
        total_emails: session.total_emails,
        detected_expenses: session.detected_expenses,
        time_remaining: format_time_remaining(session.estimated_time_remaining),
        accounts: accounts_data
      }

      broadcast_to(session, data)
    end

    private

    def format_time_remaining(seconds)
      return nil unless seconds

      if seconds < 60
        "#{seconds.to_i} segundos"
      elsif seconds < 3600
        minutes = (seconds / 60).to_i
        "#{minutes} minuto#{'s' if minutes != 1}"
      else
        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        "#{hours}h #{minutes}m"
      end
    end

    def format_duration(seconds)
      return nil unless seconds

      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      secs = (seconds % 60).to_i

      if hours > 0
        "#{hours}h #{minutes}m #{secs}s"
      elsif minutes > 0
        "#{minutes}m #{secs}s"
      else
        "#{secs}s"
      end
    end
  end

  private

  def build_accounts_data(session)
    session.sync_session_accounts.includes(:email_account).map do |account|
      {
        id: account.email_account_id,  # Use email_account_id for DOM matching
        sync_id: account.id,
        email: account.email_account.email,
        bank: account.email_account.bank_name,
        status: account.status,
        progress: account.progress_percentage,
        processed: account.processed_emails,
        total: account.total_emails,
        detected: account.detected_expenses
      }
    end
  end
end
