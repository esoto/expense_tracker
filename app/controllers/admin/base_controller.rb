# frozen_string_literal: true

module Admin
  # Base controller for admin functionality with unified role-based authentication.
  # PR-12: Replaced legacy AdminAuthentication concern with UserAuthentication
  # (inherited from ApplicationController) + require_admin! before_action.
  # One login at /login — no separate /admin/login.
  class BaseController < ApplicationController
    layout "admin"

    # Enforce admin role — non-admins get 403; anonymous users were already
    # redirected to /login by UserAuthentication#require_authentication.
    before_action :require_admin!

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

    # PR-12: Authorization helpers ported from the deleted AdminAuthentication concern.
    # These delegate to User#can_*? which in the new two-role system all reduce to admin?.
    # Kept here (not in UserAuthentication) because they are admin-panel-only concerns.

    def require_pattern_management_permission
      unless current_admin_user&.can_manage_patterns?
        render_forbidden("You don't have permission to manage patterns.")
      end
    end

    def require_pattern_edit_permission
      unless current_admin_user&.can_edit_patterns?
        render_forbidden("You don't have permission to edit patterns.")
      end
    end

    def require_pattern_delete_permission
      unless current_admin_user&.can_delete_patterns?
        render_forbidden("You don't have permission to delete patterns.")
      end
    end

    def require_import_permission
      unless current_admin_user&.can_import_patterns?
        render_forbidden("You don't have permission to import patterns.")
      end
    end

    def require_statistics_permission
      unless current_admin_user&.can_access_statistics?
        render_forbidden("You don't have permission to access statistics.")
      end
    end
  end
end
