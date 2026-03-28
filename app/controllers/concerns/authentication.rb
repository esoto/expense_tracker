# frozen_string_literal: true

# Authentication concern for controllers requiring user authentication
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    helper_method :current_user, :user_signed_in?
  end

  private

  def authenticate_user!
    unless user_signed_in?
      # Allowlist pattern: only redirect HTML requests. All other formats
      # (JSON, CSV, turbo_stream, XML, etc.) get a 401 JSON response.
      # This is future-proof — no need to enumerate formats. (PER-212 review)
      if request.format.html? && !request.xhr?
        store_location
        # PER-213: For Turbo Drive navigation, return a response that tells
        # Turbo Drive to do a full page reload to the login path rather than
        # swapping content, avoiding stale CSRF token issues.
        if turbo_drive_request?
          response.set_header("X-Turbo-Location", admin_login_path)
          redirect_to admin_login_path, alert: t("authentication.session_expired",
            default: "Please sign in to continue.")
        else
          redirect_to admin_login_path, alert: t("authentication.session_expired",
            default: "Please sign in to continue.")
        end
      else
        render json: { error: "Authentication required" }, status: :unauthorized
      end
    end
  end

  def current_user
    @current_user ||= begin
      if session[:admin_session_token].present?
        # PER-213: Session extension is managed in check_session_expiry
        # (AdminAuthentication) based on whether the request is a prefetch.
        # Use extend: false here so the model lookup is side-effect free.
        AdminUser.find_by_valid_session(session[:admin_session_token], extend: false)
      end
    end
  end

  def user_signed_in?
    current_user.present?
  end

  def current_user_id
    current_user&.id || raise("No authenticated user")
  end

  def store_location
    # Store location only for GET requests (not HEAD).
    # PER-213: Skip storing location for Turbo Drive prefetch requests — these
    # are speculative and not initiated by the user.
    return if turbo_prefetch_request?

    session[:return_to] = request.fullpath if request.get? && !request.head?
  end

  # PER-213: Returns true when the request was initiated by Turbo Drive.
  # Turbo Drive sets the Turbo-Frame header for frame requests and
  # X-Requested-With for XHR, but the canonical signal for a full Turbo Drive
  # visit is the Accept header including "text/vnd.turbo-stream.html".
  def turbo_drive_request?
    request.headers["Turbo-Frame"].present? ||
      request.headers["X-Turbo-Request-Id"].present? ||
      request.accept.to_s.include?("text/vnd.turbo-stream.html")
  end

  # PER-213: Returns true for browser-initiated prefetch requests that should
  # not have any side effects (session refresh, audit logging, etc.).
  # Modern browsers send "Sec-Purpose: prefetch" or "Purpose: prefetch".
  def turbo_prefetch_request?
    request.headers["Sec-Purpose"].to_s.include?("prefetch") ||
      request.headers["Purpose"].to_s.include?("prefetch")
  end

  # Helper method to check if user has specific role
  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "You don't have permission to access this page."
    end
  end

  # Helper method to check if user has specific permission
  def can?(action, resource = nil)
    current_user&.can?(action, resource)
  end

  # Log user actions for audit trail
  def log_user_action(action, details = {})
    Rails.logger.info(
      {
        event: "user_action",
        user_id: current_user&.id,
        action: action,
        details: details,
        controller: controller_name,
        action_name: action_name,
        ip_address: request.remote_ip,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end
end
