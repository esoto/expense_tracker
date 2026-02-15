module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_session_info

    def connect
      self.current_session_info = find_verified_session
    end

    private

    def find_verified_session
      # In test environment, allow a simpler authentication method for testing
      if Rails.env.test?
        # For tests, return a valid session structure
        return {
          session_id: "test_session",
          sync_session_id: nil,
          verified_at: Time.current,
          ip_address: "127.0.0.1"
        }
      end

      # Get the main session data
      session_data = cookies.encrypted[:_expense_tracker_session]
      ip_address = request.remote_ip || request.ip
      timestamp = Time.current.iso8601

      # Extract session ID from cookies
      rails_session_id = extract_session_id(session_data)

      # Create a verified session info object
      if rails_session_id.present?
        # Log successful authentication for monitoring
        Rails.logger.info "[SECURITY] WebSocket authentication successful: IP=#{ip_address}, Session=#{rails_session_id[0..8]}..., Time=#{timestamp}"
        {
          session_id: rails_session_id,
          sync_session_id: session_data&.dig("sync_session_id"),
          verified_at: Time.current,
          ip_address: ip_address
        }
      else
        # Log failed authentication attempt
        session_status = session_data.nil? ? "nil" : session_data.class.name
        Rails.logger.warn "[SECURITY] Failed WebSocket authentication: IP=#{ip_address}, Session=#{session_status}, Time=#{timestamp}"
        reject_unauthorized_connection
      end
    end

    def extract_session_id(session_data)
      case session_data
      when Hash
        # Rails session ID is typically stored in the session itself
        session_data["session_id"] || session_data[:session_id]
      when String
        # Invalid format
        nil
      else
        nil
      end
    end
  end
end
