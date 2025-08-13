# frozen_string_literal: true

# Concern for handling admin authentication and authorization
module AdminAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_admin_authentication
    before_action :check_session_expiry
    before_action :set_security_headers

    helper_method :current_admin_user, :admin_signed_in?

    # CSRF protection for admin area
    protect_from_forgery with: :exception
  end

  private

  def require_admin_authentication
    unless admin_signed_in?
      store_location
      redirect_to admin_login_path, alert: "Please sign in to continue."
    end
  end

  def check_session_expiry
    return unless current_admin_user

    if current_admin_user.session_expired?
      current_admin_user.invalidate_session!
      reset_session
      redirect_to admin_login_path, alert: "Your session has expired. Please sign in again."
    else
      # Extend session on activity
      current_admin_user.extend_session
    end
  end

  def current_admin_user
    @current_admin_user ||= begin
      if session[:admin_session_token].present?
        AdminUser.find_by_valid_session(session[:admin_session_token])
      end
    end
  end

  def admin_signed_in?
    current_admin_user.present?
  end

  def store_location
    # Store location only for GET requests (not HEAD)
    session[:return_to] = request.fullpath if request.get? && !request.head?
  end

  def redirect_back_or(default)
    redirect_to(session[:return_to] || default)
    session.delete(:return_to)
  end

  def set_admin_session(admin_user)
    reset_session # Prevent session fixation
    session[:admin_session_token] = admin_user.session_token
    session[:admin_user_id] = admin_user.id
  end

  def clear_admin_session
    current_admin_user&.invalidate_session!
    reset_session
  end

  def set_security_headers
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = content_security_policy
  end

  def content_security_policy
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net",
      "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net",
      "img-src 'self' data: https:",
      "font-src 'self' data:",
      "connect-src 'self'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join("; ")
  end

  # Authorization helpers
  def require_pattern_management_permission
    unless current_admin_user.can_manage_patterns?
      render_forbidden("You don't have permission to manage patterns.")
    end
  end

  def require_pattern_edit_permission
    unless current_admin_user.can_edit_patterns?
      render_forbidden("You don't have permission to edit patterns.")
    end
  end

  def require_pattern_delete_permission
    unless current_admin_user.can_delete_patterns?
      render_forbidden("You don't have permission to delete patterns.")
    end
  end

  def require_import_permission
    unless current_admin_user.can_import_patterns?
      render_forbidden("You don't have permission to import patterns.")
    end
  end

  def require_statistics_permission
    unless current_admin_user.can_access_statistics?
      render_forbidden("You don't have permission to access statistics.")
    end
  end

  def render_forbidden(message = "Forbidden")
    respond_to do |format|
      format.html { redirect_back(fallback_location: admin_root_path, alert: message) }
      format.json { render json: { error: message }, status: :forbidden }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { alert: message }) }
    end
  end

  # Audit logging
  def log_admin_action(action, details = {})
    Rails.logger.info(
      {
        event: "admin_action",
        admin_user_id: current_admin_user&.id,
        admin_email: current_admin_user&.email,
        action: action,
        details: details,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end
end
