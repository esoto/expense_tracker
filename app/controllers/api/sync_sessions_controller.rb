module Api
  class SyncSessionsController < Api::BaseController
    # SyncSessions uses a per-session X-Sync-Token scheme (see can_access_sync_session?),
    # not the Bearer ApiToken that Api::BaseController enforces. Browser polling
    # (app/javascript/mixins/sync_connection_mixin.js) does not send Authorization: Bearer,
    # so the inherited `authenticate_api_token` before_action must be skipped — scoped
    # to :status explicitly so future actions inherit Bearer auth by default (PER-502).
    skip_before_action :authenticate_api_token, only: [ :status ]
    before_action :set_sync_session, only: [ :status ]

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

        # PER-502: use ActiveSupport::SecurityUtils.secure_compare to defeat
        # timing attacks. Guards needed before invoking it:
        #   - is_a?(String) — a malicious client can send `?token[]=foo`, which
        #     makes params[:token] an Array with no #bytesize. Without this
        #     guard, NoMethodError would be rescued as StandardError → 500 +
        #     backtrace logged (DoS + log pollution).
        #   - bytesize equality — Rails 8.1's secure_compare requires equal-length
        #     inputs. Length itself is public (visible in every HTTP response) so
        #     the early return leaks no secrets. Matches the Api::QueueController:285
        #     pattern (provided first, stored second).
        return false unless provided_token.is_a?(String) && provided_token.present?

        stored_token = @sync_session.session_token
        return false unless stored_token.is_a?(String) &&
                            stored_token.bytesize == provided_token.bytesize

        return ActiveSupport::SecurityUtils.secure_compare(provided_token, stored_token)
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
  end
end
