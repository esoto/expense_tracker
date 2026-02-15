# frozen_string_literal: true

module Admin
  # Base controller for admin functionality with secure authentication
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!
    include AdminAuthentication

    # Rate limiting for admin actions
    before_action :check_rate_limit

    # Audit logging
    after_action :log_admin_activity

    private

    def check_rate_limit
      # Rate limiting is handled by Rack::Attack middleware
      # This is a placeholder for request-specific rate limiting
      true
    end

    def log_admin_activity
      # Log all admin actions for audit trail
      log_admin_action(
        "#{controller_name}##{action_name}",
        {
          params: filtered_params,
          method: request.method,
          path: request.path
        }
      )
    end

    def filtered_params
      params.except(:password, :password_confirmation, :authenticity_token).to_unsafe_h
    end
  end
end
