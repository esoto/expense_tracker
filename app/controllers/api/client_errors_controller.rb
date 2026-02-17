module Api
  class ClientErrorsController < ApplicationController
    skip_before_action :verify_authenticity_token

    # POST /api/client_errors
    # Receives error reports from client-side JavaScript
    # Requires a valid user session to prevent unauthenticated log flooding
    def create
      # Parse error data
      error_data = {
        message: params[:message],
        data: params[:data],
        session_id: params[:sessionId],
        timestamp: params[:timestamp],
        user_agent: params[:userAgent],
        url: params[:url],
        error_count: params[:errorCount],
        polling_mode: params[:pollingMode],
        connection_state: params[:connectionState],
        ip_address: request.remote_ip,
        reported_at: Time.current
      }

      # Log the error for monitoring
      Rails.logger.error "[CLIENT_ERROR] #{error_data[:message]}"
      Rails.logger.error "[CLIENT_ERROR] Details: #{error_data.to_json}"

      # Store in database if ClientError model exists
      if defined?(ClientError)
        ClientError.create!(error_data)
      end

      # Send to error tracking service if configured (e.g., Sentry, Rollbar)
      if Rails.application.config.respond_to?(:error_tracker)
        Rails.application.config.error_tracker.track_client_error(error_data)
      end

      # Return success response
      render json: { status: "received" }, status: :ok
    rescue StandardError => e
      # Don't fail the request even if error logging fails
      begin
        Rails.logger.error "[CLIENT_ERROR] Failed to log client error: #{e.message}"
      rescue
        # Even if logging fails, don't crash
      end
      render json: { status: "error" }, status: :ok
    end

    private

    # Override to return JSON 401 instead of redirecting to login page
    def authenticate_user!
      unless user_signed_in?
        render json: { error: "Authentication required" }, status: :unauthorized
      end
    end
  end
end
