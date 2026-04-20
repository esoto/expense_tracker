# frozen_string_literal: true

# Authentication concern for end-user sessions. Parallel to AdminAuthentication
# (admin panel) during the unified-user migration; PR 12 will merge them.
module UserAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :check_session_expiry
    before_action :set_security_headers
    # PER-213: Refresh CSRF token on every request so Turbo Drive always
    # has a fresh token in the meta tag after navigation.
    before_action :refresh_csrf_token_for_turbo

    helper_method :current_app_user, :app_user_signed_in?

    # CSRF protection
    protect_from_forgery with: :exception
  end

  private

  def require_authentication
    unless app_user_signed_in?
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
        redirect_to login_path,
          alert: "Your session has expired. Please sign in again.",
          status: turbo_drive_request? ? :see_other : :found
      else
        store_location
        redirect_to login_path, alert: "Please sign in to continue."
      end
    end
  end

  def check_session_expiry
    return unless current_app_user

    # At this point find_by_valid_session already confirmed the session is not
    # expired (it returns nil otherwise).  We only need to extend the session
    # for real user activity — skip for prefetch requests.
    current_app_user.extend_session unless turbo_prefetch_request?
  end

  # PER-213: Returns true when a session token is stored in the cookie but the
  # session-stored expiry timestamp is in the past.
  # Uses the session-stored expiry rather than a DB lookup to avoid creating
  # a timing oracle on every unauthenticated request.
  def session_token_present_but_expired?
    return false unless session[:user_session_token].present?

    expires_at = session[:user_session_expires_at]
    return false unless expires_at.present?

    Time.zone.parse(expires_at.to_s) < Time.current
  end

  # PER-213: Remove stale user session keys without calling reset_session.
  # reset_session would rotate the CSRF token, causing Turbo Drive's cached
  # page to send a stale token on the next form submission → 422 → lockout.
  # Calls invalidate_session! to nullify the DB token (server-side revocation)
  # without touching the CSRF token (invalidate_session! is a model method,
  # not a controller method, so it does NOT call reset_session).
  def clean_expired_session_keys
    if session[:user_session_token].present?
      User.find_by(session_token: session[:user_session_token])&.invalidate_session!
    end
    session.delete(:user_session_token)
    session.delete(:user_id)
    session.delete(:user_session_expires_at)
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

  def current_app_user
    @current_app_user ||= begin
      if session[:user_session_token].present?
        # PER-213: Skip session extension for prefetch requests — they are
        # speculative and should not count as real user activity. Extension
        # is handled explicitly in check_session_expiry for non-prefetch requests.
        User.find_by_valid_session(session[:user_session_token], extend: false)
      end
    end
  end

  def app_user_signed_in?
    current_app_user.present?
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
  # from non-existent routes and open-redirect attacks.
  # Only user-facing paths (not /admin) are safe return destinations.
  def redirect_back_or(default)
    return_to = valid_return_to_path(session.delete(:return_to))
    redirect_to(return_to || default)
  end

  # Reject admin paths and external URLs to prevent open redirect and
  # routing errors caused by stale or external session[:return_to] values.
  def valid_return_to_path(path)
    return nil if path.blank?
    return nil if path.start_with?("/admin")
    return nil unless path.start_with?("/")

    path
  end

  def set_user_session(user)
    reset_session # Prevent session fixation
    session[:user_session_token] = user.session_token
    session[:user_id] = user.id
    session[:user_session_expires_at] = user.session_expires_at&.iso8601
  end

  def clear_user_session
    current_app_user&.invalidate_session!
    reset_session
  end

  def set_security_headers
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # CSP is managed globally via config/initializers/content_security_policy.rb
    # with nonce-based script-src. Do not override here with unsafe-inline.
  end

  # Authorization helper — renders forbidden unless current user is an admin.
  def require_admin!
    render_forbidden unless current_app_user&.admin?
  end

  def render_forbidden(message = "Forbidden")
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, alert: message) }
      format.json { render json: { error: message }, status: :forbidden }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { alert: message }) }
    end
  end

  # Audit logging for end-user actions
  def log_app_user_action(action, details = {})
    Rails.logger.info(
      {
        event: "user_action",
        user_id: current_app_user&.id,
        user_email: current_app_user&.email,
        action: action,
        details: details,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end
end
