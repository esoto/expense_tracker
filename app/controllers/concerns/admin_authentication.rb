# frozen_string_literal: true

# Concern for handling admin authentication and authorization
module AdminAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_admin_authentication
    before_action :check_session_expiry
    before_action :set_security_headers
    # PER-213: Refresh CSRF token on every admin request so Turbo Drive always
    # has a fresh token in the meta tag after navigation.
    before_action :refresh_csrf_token_for_turbo

    helper_method :current_admin_user, :admin_signed_in?

    # CSRF protection for admin area
    protect_from_forgery with: :exception
  end

  private

  def require_admin_authentication
    unless admin_signed_in?
      # PER-213: Check whether this is an expired session (token present but
      # session_expires_at in the past) vs. a truly anonymous request.  We
      # distinguish these so we can:
      #   a) Delete only the stale session keys (not reset_session) to avoid
      #      CSRF token rotation.
      #   b) Return 303 See Other for Turbo Drive requests on expiry so Turbo
      #      forces a full-page visit rather than swapping cached content.
      if session_token_present_but_expired?
        # Clear stale auth keys without rotating the CSRF token.
        clean_expired_session_keys
        redirect_to admin_login_path,
          alert: "Your session has expired. Please sign in again.",
          status: turbo_drive_request? ? :see_other : :found
      else
        store_location
        redirect_to admin_login_path, alert: "Please sign in to continue."
      end
    end
  end

  def check_session_expiry
    return unless current_admin_user

    # At this point find_by_valid_session already confirmed the session is not
    # expired (it returns nil otherwise).  We only need to extend the session
    # for real user activity — skip for prefetch requests.
    current_admin_user.extend_session unless turbo_prefetch_request?
  end

  # PER-213: Returns true when a session token is stored in the cookie but the
  # session-stored expiry timestamp is in the past.
  # Uses the session-stored expiry rather than a DB lookup to avoid creating
  # a timing oracle on every unauthenticated request.
  def session_token_present_but_expired?
    return false unless session[:admin_session_token].present?

    expires_at = session[:admin_session_expires_at]
    return false unless expires_at.present?

    Time.zone.parse(expires_at.to_s) < Time.current
  end

  # PER-213: Remove stale admin session keys without calling reset_session.
  # reset_session would rotate the CSRF token, causing Turbo Drive's cached
  # page to send a stale token on the next form submission → 422 → lockout.
  # Calls invalidate_session! to nullify the DB token (server-side revocation)
  # without touching the CSRF token (invalidate_session! is a model method,
  # not a controller method, so it does NOT call reset_session).
  def clean_expired_session_keys
    if session[:admin_session_token].present?
      AdminUser.find_by(session_token: session[:admin_session_token])&.invalidate_session!
    end
    session.delete(:admin_session_token)
    session.delete(:admin_user_id)
    session.delete(:admin_session_expires_at)
  end

  # PER-213: Ensure the CSRF token is consistent for the current response so
  # Turbo Drive page-cache restorations send a valid token.  This is a no-op
  # for non-GET requests.
  def refresh_csrf_token_for_turbo
    # Only relevant on full-page GET responses that Turbo Drive may cache.
    # HEAD responses carry no body so the memoized token is never delivered;
    # intentionally excluded (Fix 5 of PER-213 security review).
    return unless request.get?
    # Skip for prefetch — the prefetched response is discarded and we don't
    # want to advance the token counter for a speculative request.
    return if turbo_prefetch_request?

    # Calling form_authenticity_token memoizes the masked token for this
    # request, ensuring that the csrf-token meta tag written by csrf_meta_tags
    # in the layout matches any form tokens on the same page.
    form_authenticity_token
  end

  def current_admin_user
    @current_admin_user ||= begin
      if session[:admin_session_token].present?
        # PER-213: Skip session extension for prefetch requests — they are
        # speculative and should not count as real user activity. Extension
        # is handled explicitly in check_session_expiry for non-prefetch requests.
        AdminUser.find_by_valid_session(session[:admin_session_token], extend: false)
      end
    end
  end

  def admin_signed_in?
    current_admin_user.present?
  end

  def store_location
    # Store location only for GET requests (not HEAD).
    # PER-213: Skip for Turbo Drive prefetch requests.
    return if turbo_prefetch_request?

    session[:return_to] = request.fullpath if request.get? && !request.head?
  end

  # NOTE: These headers are user-controlled and spoofable. This method is used
  # ONLY for UX decisions (redirect status code), never for security decisions.
  # Security-sensitive actions (session revocation, auth checks) must not branch
  # on this value.
  # PER-213: Returns true when the request was initiated by Turbo Drive.
  def turbo_drive_request?
    request.headers["Turbo-Frame"].present? ||
      request.headers["X-Turbo-Request-Id"].present? ||
      request.accept.to_s.include?("text/vnd.turbo-stream.html")
  end

  # PER-213: Returns true for browser-initiated prefetch requests.
  def turbo_prefetch_request?
    request.headers["Sec-Purpose"].to_s.include?("prefetch") ||
      request.headers["Purpose"].to_s.include?("prefetch")
  end

  # PER-219: Validate return_to path before redirecting to prevent RoutingError
  # from non-existent routes (e.g. /login) and open-redirect attacks.
  # Only admin paths are safe return destinations after authentication.
  def redirect_back_or(default)
    return_to = valid_return_to_path(session.delete(:return_to))
    redirect_to(return_to || default)
  end

  # Only redirect back to safe admin paths to prevent open redirect and
  # routing errors caused by stale or external session[:return_to] values.
  def valid_return_to_path(path)
    return nil if path.blank?
    return nil unless path.start_with?("/admin/") || path == "/admin"

    path
  end

  def set_admin_session(admin_user)
    reset_session # Prevent session fixation
    session[:admin_session_token] = admin_user.session_token
    session[:admin_user_id] = admin_user.id
    session[:admin_session_expires_at] = admin_user.session_expires_at&.iso8601
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
