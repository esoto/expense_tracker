# frozen_string_literal: true

module Admin
  # Base controller for admin functionality with secure authentication
  class BaseController < ApplicationController
    layout "admin"

    skip_before_action :authenticate_user!
    include AdminAuthentication

    # Rate limiting is centralized in Rack::Attack (see config/initializers/
    # rack_attack.rb for the admin/state-changing/ip throttle and the per-
    # action rules for login, password reset, pattern test/import, CSV
    # exports, and statistics). PER-507 removed a no-op request-level
    # placeholder that added no protection.

    # Audit logging
    after_action :log_admin_activity

    private

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
      request.filtered_parameters
    end
  end
end
