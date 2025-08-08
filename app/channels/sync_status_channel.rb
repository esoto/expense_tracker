class SyncStatusChannel < ApplicationCable::Channel
  def subscribed
    if params[:session_id].present?
      session = SyncSession.find_by(id: params[:session_id])
      ip_address = connection.current_session_info&.dig(:ip_address) || "unknown"
      session_id = connection.current_session_info&.dig(:session_id) || "unknown"
      timestamp = Time.current.iso8601

      if session && can_access_session?(session)
        # Use stream_for to ensure proper isolation
        stream_for session

        # Log successful subscription for monitoring
        Rails.logger.info "[SECURITY] SyncStatusChannel subscription successful: Session=#{session_id[0..8]}..., SyncSession=#{session.id}, IP=#{ip_address}, Time=#{timestamp}"

        # Send initial status on subscription
        transmit_initial_status(session)
      else
        # Log unauthorized subscription attempt with detailed context
        session_exists = session ? "exists" : "not_found"
        Rails.logger.warn "[SECURITY] Unauthorized SyncStatusChannel subscription: Session=#{session_id[0..8]}..., SyncSession=#{params[:session_id]}, Status=#{session_exists}, IP=#{ip_address}, Time=#{timestamp}"
        reject
      end
    else
      # Log missing session ID parameter
      ip_address = connection.current_session_info&.dig(:ip_address) || "unknown"
      session_id = connection.current_session_info&.dig(:session_id) || "unknown"
      timestamp = Time.current.iso8601
      Rails.logger.warn "[SECURITY] SyncStatusChannel subscription rejected - missing session_id: Session=#{session_id[0..8]}..., IP=#{ip_address}, Time=#{timestamp}"
      reject
    end
  end

  def unsubscribed
    stop_all_streams
    session_id = connection.current_session_info&.dig(:session_id) || "unknown"
    Rails.logger.info "SyncStatusChannel: Session #{session_id} unsubscribed"
  end

  # Action to pause updates (when tab becomes inactive)
  def pause_updates
    @paused = true
    session_id = connection.current_session_info&.dig(:session_id) || "unknown"
    Rails.logger.debug "SyncStatusChannel: Updates paused for session #{session_id}"
  end

  # Action to resume updates (when tab becomes active)
  def resume_updates
    @paused = false
    session_id = connection.current_session_info&.dig(:session_id) || "unknown"
    Rails.logger.debug "SyncStatusChannel: Updates resumed for session #{session_id}"

    # Send latest status when resuming
    if params[:session_id].present?
      session = SyncSession.find_by(id: params[:session_id])
      transmit_current_status(session) if session && can_access_session?(session)
    end
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

  # Check if the current connection can access this sync session
  def can_access_session?(session)
    # Verify the connection is authenticated
    unless connection.current_session_info.present?
      log_security_event("Missing connection session info", session)
      return false
    end

    # In test environment, allow access for simplicity
    return true if Rails.env.test?

    ip_address = connection.current_session_info[:ip_address]
    rails_session_id = connection.current_session_info[:session_id]
    timestamp = Time.current.iso8601

    # Check if this sync session has a token (new sessions)
    if session.session_token.present?
      # For sessions with tokens, verify the token matches
      provided_token = params[:session_token] ||
                      connection.current_session_info[:sync_session_token]

      unless provided_token.present?
        Rails.logger.warn "[SECURITY] Token-based authentication failed - missing token: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{ip_address}, Time=#{timestamp}"
        return false
      end

      unless session.session_token == provided_token
        Rails.logger.warn "[SECURITY] Token-based authentication failed - invalid token: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{ip_address}, Time=#{timestamp}"
        return false
      end

      Rails.logger.info "[SECURITY] Token-based authentication successful: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{ip_address}, Time=#{timestamp}"
      return true
    end

    # For sessions without tokens (legacy), use session-based verification
    sync_session_id = connection.current_session_info[:sync_session_id]

    # Allow access if the sync session ID matches what's stored in the Rails session
    if sync_session_id == session.id
      Rails.logger.info "[SECURITY] Session-based authentication successful: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{ip_address}, Time=#{timestamp}"
      return true
    elsif session.created_at > 24.hours.ago
      # For recent sessions, verify IP address match for additional security
      stored_ip = session.metadata&.dig("ip_address")
      current_ip = connection.current_session_info[:ip_address]

      # If no IP stored (legacy), allow for backward compatibility but log it
      if stored_ip.nil?
        Rails.logger.info "[SECURITY] Legacy session access granted - no IP stored: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{current_ip}, Time=#{timestamp}"
        return true
      end

      # Check IP address match
      if stored_ip == current_ip
        Rails.logger.info "[SECURITY] IP-verified session access granted: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, IP=#{current_ip}, Time=#{timestamp}"
        return true
      else
        Rails.logger.warn "[SECURITY] IP mismatch for sync session #{session.id}: Expected=#{stored_ip}, Actual=#{current_ip}, Session=#{rails_session_id[0..8]}..., Time=#{timestamp}"
        return false
      end
    else
      Rails.logger.warn "[SECURITY] Session access denied - expired session: Session=#{rails_session_id[0..8]}..., SyncSession=#{session.id}, Created=#{session.created_at.iso8601}, IP=#{ip_address}, Time=#{timestamp}"
    end

    false
  end

  # Helper method for security event logging
  def log_security_event(event_type, session = nil)
    ip_address = connection.current_session_info&.dig(:ip_address) || "unknown"
    rails_session_id = connection.current_session_info&.dig(:session_id) || "unknown"
    session_id_display = rails_session_id == "unknown" ? "unknown" : "#{rails_session_id[0..8]}..."
    sync_session_id = session&.id || "unknown"
    timestamp = Time.current.iso8601

    Rails.logger.warn "[SECURITY] #{event_type}: Session=#{session_id_display}, SyncSession=#{sync_session_id}, IP=#{ip_address}, Time=#{timestamp}"
  end

  # Send initial status when subscribing
  def transmit_initial_status(session)
    transmit({
      type: "initial_status",
      status: session.status,
      progress_percentage: session.progress_percentage,
      processed_emails: session.processed_emails,
      total_emails: session.total_emails,
      detected_expenses: session.detected_expenses,
      accounts: build_accounts_data(session),
      time_remaining: self.class.send(:format_time_remaining, session.estimated_time_remaining)
    })
  end

  # Send current status (used when resuming)
  def transmit_current_status(session)
    session.reload
    transmit({
      type: "status_update",
      status: session.status,
      progress_percentage: session.progress_percentage,
      processed_emails: session.processed_emails,
      total_emails: session.total_emails,
      detected_expenses: session.detected_expenses,
      accounts: build_accounts_data(session),
      time_remaining: self.class.send(:format_time_remaining, session.estimated_time_remaining)
    })
  end

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
