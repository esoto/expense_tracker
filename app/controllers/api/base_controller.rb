# frozen_string_literal: true

module Api
  # Base controller for all API endpoints with authentication and error handling
  class BaseController < ApplicationController
    include ApiConfiguration

    skip_before_action :verify_authenticity_token
    before_action :authenticate_api_token
    before_action :set_default_headers
    before_action :log_request

    rescue_from StandardError, with: :internal_server_error
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def authenticate_api_token
      token = extract_bearer_token

      unless token.present?
        render_unauthorized("Missing API token")
        return
      end

      @current_api_token = ApiToken.authenticate(token)

      unless @current_api_token
        render_unauthorized("Invalid or expired API token")
      end
    end

    def extract_bearer_token
      request.headers["Authorization"]&.remove("Bearer ")
    end

    def render_unauthorized(message = "Unauthorized")
      render json: {
        error: message,
        status: 401
      }, status: :unauthorized
    end

    def not_found(exception)
      render json: {
        error: exception.message,
        status: 404
      }, status: :not_found
    end

    def unprocessable_entity(exception)
      render json: {
        error: exception.message,
        errors: exception.record.errors.full_messages,
        status: 422
      }, status: :unprocessable_content
    end

    def bad_request(exception)
      render json: {
        error: exception.message,
        status: 400
      }, status: :bad_request
    end

    def paginate(collection)
      paginate_with_limits(collection)
    end

    def render_success(data = {}, status: :ok)
      response_data = { status: "success" }
      response_data.merge!(data) if data.is_a?(Hash)
      render json: response_data, status: status
    end

    def render_error(message, errors = [], status: :unprocessable_content)
      render json: {
        status: "error",
        message: message,
        errors: errors,
        request_id: request.request_id
      }, status: status
    end

    def internal_server_error(exception)
      Rails.logger.error "API Error: #{exception.message}"
      Rails.logger.error exception.backtrace.join("\n")

      render json: {
        error: "Internal server error",
        status: 500,
        request_id: request.request_id
      }, status: :internal_server_error
    end

    def set_default_headers
      response.headers["X-API-Version"] = CURRENT_API_VERSION
      response.headers["X-Request-ID"] = request.request_id
    end

    def log_request
      Rails.logger.info "API Request: #{request.method} #{request.path} - Token: #{@current_api_token&.name} - Request ID: #{request.request_id}"
    end
  end
end
