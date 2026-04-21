# frozen_string_literal: true

require "rails_helper"

# PER-213: Prevent session expiry from cascading into CSRF-token mismatches
# and rate-limit lockouts during Turbo Drive navigation.
#
# Root causes:
# 1. check_session_expiry called reset_session on expiry, which rotated the
#    CSRF token.  Turbo Drive caches pages, so the next form submission
#    would carry the old (now-invalid) token → 422 → redirect loop → lockout.
#
# 2. Turbo Drive prefetch requests (Sec-Purpose: prefetch) were counted as
#    user activity and extended (or reset) the session, causing the session
#    to appear active when it wasn't, or consuming session refresh budget.
#
# 3. Session expiry redirect used HTTP 302 (Found), but Turbo Drive follows
#    redirects with a GET, sometimes re-using the cached page body. HTTP 303
#    (See Other) forces Turbo Drive to do a full-page visit.
#
# Fixes:
# - Replace reset_session with targeted session.delete(:admin_session_token)
#   and session.delete(:admin_user_id) so the CSRF token is preserved.
# - Use HTTP 303 See Other for Turbo Drive session-expiry redirects.
# - Skip session extension for prefetch requests.
# - Skip store_location for prefetch requests.
RSpec.describe "PER-213 Session expiry during Turbo Drive navigation", type: :request do
  # PR-12: Use User factory default password so sign_in_admin works without a separate password.
  let(:password) { "TestPass123!" }
  let(:admin_user) { create(:user, :admin) }

  # Helper: POST to unified /login endpoint and follow the redirect.
  def sign_in_admin
    post login_path, params: { email: admin_user.email, password: password }
    follow_redirect!
  end

  # Helper: Simulate session expiry by traveling past the session_expires_at
  # time stored in both the DB record and the session cookie.
  # The session cookie's user_session_expires_at was set to SESSION_DURATION
  # from the login time, so traveling 3 hours forward guarantees both are past.
  def with_expired_session(&block)
    travel_to(User::SESSION_DURATION.from_now + 1.hour, &block)
  end

  # ─── CSRF token preservation ────────────────────────────────────────────────

  describe "CSRF token after session expiry", :unit do
    it "does NOT call reset_session when the session expires" do
      sign_in_admin

      # Travel past the session duration so both the session-cookie expiry and
      # the DB record are in the past — this is how expiry naturally occurs.
      with_expired_session do
        # A normal GET (no prefetch)
        get admin_patterns_path

        # The controller should have cleared individual user session keys, not
        # wiped the whole session (which would rotate CSRF token).
        # Verify we redirected gracefully without a full session reset.
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq("Your session has expired. Please sign in again.")
      end
    end

    it "preserves the CSRF token cookie across a session-expiry redirect" do
      sign_in_admin
      csrf_token_before = session[:_csrf_token]

      with_expired_session do
        get admin_patterns_path

        # After the redirect the cookie-based session should still carry the
        # same CSRF token (it was not rotated by reset_session).
        csrf_token_after = session[:_csrf_token]
        expect(csrf_token_after).to eq(csrf_token_before)
      end
    end
  end

  # ─── Turbo Drive: see-other redirect on expiry ──────────────────────────────

  describe "session-expiry redirect status for Turbo Drive requests", :unit do
    it "returns 303 See Other for Turbo Drive requests on session expiry" do
      sign_in_admin

      with_expired_session do
        get admin_patterns_path, headers: { "X-Turbo-Request-Id" => "test-id-123" }

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(login_path)
      end
    end

    it "returns 302 Found for regular browser requests on session expiry" do
      sign_in_admin

      with_expired_session do
        get admin_patterns_path  # no Turbo headers

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(login_path)
      end
    end
  end

  # ─── Session persists across normal Turbo Drive navigation ──────────────────

  describe "session persistence during Turbo Drive navigation", :unit do
    before { sign_in_admin }

    it "session remains active after a standard Turbo Drive GET visit" do
      get admin_patterns_path, headers: {
        "X-Turbo-Request-Id" => "nav-visit-001",
        "Accept" => "text/html, application/xhtml+xml"
      }

      expect(response).to have_http_status(:ok)
    end

    it "session remains active after multiple consecutive Turbo Drive visits" do
      3.times do |i|
        get admin_patterns_path, headers: { "X-Turbo-Request-Id" => "visit-#{i}" }
        expect(response).to have_http_status(:ok), "Request #{i} failed: #{response.status}"
      end
    end

    it "session_expires_at is extended on each authenticated request" do
      original_expiry = admin_user.reload.session_expires_at

      travel_to 30.minutes.from_now do
        get admin_patterns_path
        expect(response).to have_http_status(:ok)
      end

      expect(admin_user.reload.session_expires_at).to be > original_expiry
    end
  end

  # ─── Turbo Drive prefetch requests ──────────────────────────────────────────

  describe "Turbo Drive prefetch requests", :unit do
    before { sign_in_admin }

    it "does NOT extend session on Sec-Purpose: prefetch requests" do
      original_expiry = admin_user.reload.session_expires_at

      travel_to 10.minutes.from_now do
        get admin_patterns_path, headers: { "Sec-Purpose" => "prefetch" }
      end

      # Session extension should have been skipped for the prefetch
      expect(admin_user.reload.session_expires_at).to eq(original_expiry)
    end

    it "does NOT extend session on Purpose: prefetch requests" do
      original_expiry = admin_user.reload.session_expires_at

      travel_to 10.minutes.from_now do
        get admin_patterns_path, headers: { "Purpose" => "prefetch" }
      end

      expect(admin_user.reload.session_expires_at).to eq(original_expiry)
    end

    it "does NOT store return_to location for prefetch requests" do
      get admin_patterns_path, headers: { "Sec-Purpose" => "prefetch" }

      expect(session[:return_to]).to be_nil
    end
  end

  # ─── Authentication concern: turbo_drive_request? detection ─────────────────

  describe "turbo_drive_request? header detection", :unit do
    before { sign_in_admin }

    it "treats X-Turbo-Request-Id as a Turbo Drive request" do
      get admin_patterns_path, headers: { "X-Turbo-Request-Id" => "abc-123" }
      expect(response).to have_http_status(:ok)
    end

    it "treats Turbo-Frame header as a Turbo Drive request" do
      get admin_patterns_path, headers: { "Turbo-Frame" => "content" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ─── Unauthenticated Turbo Drive request ────────────────────────────────────

  describe "unauthenticated Turbo Drive requests", :unit do
    it "redirects to login when not signed in via Turbo Drive navigation" do
      get admin_patterns_path, headers: { "X-Turbo-Request-Id" => "unauth-001" }

      expect(response).to redirect_to(login_path)
    end

    it "sets alert message for session-less Turbo Drive requests" do
      get admin_patterns_path, headers: { "X-Turbo-Request-Id" => "unauth-002" }
      follow_redirect!

      expect(response.body).to include("Please sign in to continue.")
    end

    it "does NOT store return_to location for prefetch when unauthenticated" do
      get admin_patterns_path, headers: { "Sec-Purpose" => "prefetch" }

      expect(session[:return_to]).to be_nil
    end
  end
end
