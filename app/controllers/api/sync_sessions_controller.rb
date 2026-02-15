module Api
  class SyncSessionsController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :set_sync_session, only: [ :status ]
    skip_before_action :verify_authenticity_token, if: :json_request?

    # GET /api/sync_sessions/:id/status
    # Returns the current status of a sync session for polling
    def status
      # Check if user has access to this sync session
      unless can_access_sync_session?
        render json: { error: "Unauthorized" }, status: :unauthorized
        return
      end

      # Build status response
      status_data = build_status_response

      # Return status
      render json: status_data
    end

    private

    def set_sync_session
      @sync_session = SyncSession.find_by(id: params[:id])

      unless @sync_session
        render json: { error: "Sync session not found" }, status: :not_found
      end
    end

    def can_access_sync_session?
      return false unless @sync_session

      # Check if session token matches (for new sessions with tokens)
      if @sync_session.session_token?
        provided_token = request.headers["X-Sync-Token"] ||
                        request.headers["HTTP_X_SYNC_TOKEN"] ||
                        params[:token]

        # If token is present in session, require token auth
        if provided_token.present?
          return @sync_session.session_token == provided_token
        else
          # Token required but not provided
          return false
        end
      end

      # Check if sync session is in current user session (legacy)
      if session[:sync_session_id] == @sync_session.id
        return true
      end

      # Check IP address for recent sessions (when no token)
      if @sync_session.created_at > 24.hours.ago
        stored_ip = @sync_session.metadata&.dig("ip_address")
        current_ip = request.remote_ip

        # Allow if no IP stored (backward compatibility) OR if stored IP matches current
        if stored_ip.nil? || stored_ip == current_ip
          return true
        end
      end

      false
    end

    def build_status_response
      # Reload to get latest data
      @sync_session.reload

      # Build accounts data
      accounts = @sync_session.sync_session_accounts.includes(:email_account).map do |account|
        {
          id: account.email_account_id,
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

      # Build response
      {
        type: "status_update",
        status: @sync_session.status,
        progress_percentage: @sync_session.progress_percentage,
        processed_emails: @sync_session.processed_emails,
        total_emails: @sync_session.total_emails,
        detected_expenses: @sync_session.detected_expenses,
        time_remaining: format_time_remaining(@sync_session.estimated_time_remaining),
        accounts: accounts,
        started_at: @sync_session.started_at,
        completed_at: @sync_session.completed_at,
        error_details: @sync_session.error_details
      }
    end

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

    def json_request?
      request.format.json?
    end
  end
end
