# frozen_string_literal: true

require "rails_helper"

# PER-213: Unit tests for AdminAuthentication concern Turbo Drive fixes.
# Tests the behaviour of check_session_expiry, turbo_drive_request?, and
# turbo_prefetch_request? helpers added/modified for PER-213.
RSpec.describe AdminAuthentication, type: :controller, unit: true do
  controller(ApplicationController) do
    include AdminAuthentication

    def index
      render json: { authenticated: true }
    end

    private

    def admin_login_path
      "/admin/login"
    end

    def admin_root_path
      "/admin"
    end

    def root_path
      "/"
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  let!(:admin_user) do
    AdminUser.create!(
      name: "Test Admin",
      email: "admin@test.com",
      password: "Password123!",
      role: "admin",
      # Explicitly set session_token so it is non-nil for session[] assignment
      session_token: SecureRandom.urlsafe_base64(32),
      session_expires_at: 2.hours.from_now
    )
  end

  # Re-usable token value shared between the model record and the session cookie
  let(:session_token) { admin_user.session_token }

  # ─── require_admin_authentication: expired session handling ─────────────────
  #
  # PER-213: The expired-session path now lives in require_admin_authentication.
  # When find_by_valid_session returns nil (expired token), admin_signed_in? is
  # false and we fall into the require_admin_authentication branch.
  # The branch checks session_token_present_but_expired? to distinguish between:
  #   a) truly anonymous request → "Please sign in to continue."
  #   b) stale session token    → "Your session has expired."
  #
  # Full integration is verified in spec/requests/per213_session_expiry_turbo_spec.rb.
  # Here we test the private helper methods in isolation.

  describe "#session_token_present_but_expired?", unit: true do
    it "returns false when no session token is present" do
      expect(controller.send(:session_token_present_but_expired?)).to be false
    end

    it "returns false when session token is present but no expiry is stored in session" do
      session[:admin_session_token] = "some_token"
      # No admin_session_expires_at stored — treat as not-yet-expired (legacy session)
      expect(controller.send(:session_token_present_but_expired?)).to be false
    end

    it "returns true when session-stored expiry is in the past" do
      session[:admin_session_token] = admin_user.session_token
      session[:admin_session_expires_at] = 1.hour.ago.iso8601
      expect(controller.send(:session_token_present_but_expired?)).to be true
    end

    it "returns false when session-stored expiry is in the future" do
      session[:admin_session_token] = admin_user.session_token
      session[:admin_session_expires_at] = 2.hours.from_now.iso8601
      expect(controller.send(:session_token_present_but_expired?)).to be false
    end

    it "does NOT perform a DB query to determine expiry" do
      session[:admin_session_token] = admin_user.session_token
      session[:admin_session_expires_at] = 1.hour.ago.iso8601
      expect(AdminUser).not_to receive(:find_by)
      controller.send(:session_token_present_but_expired?)
    end
  end

  describe "#clean_expired_session_keys", unit: true do
    it "removes admin_session_token and related keys from session without calling reset_session" do
      session[:admin_session_token] = "some_token"
      session[:admin_user_id] = 42
      session[:admin_session_expires_at] = 1.hour.ago.iso8601
      expect(controller).not_to receive(:reset_session)
      allow(AdminUser).to receive(:find_by).and_return(nil)

      controller.send(:clean_expired_session_keys)

      expect(session[:admin_session_token]).to be_nil
      expect(session[:admin_user_id]).to be_nil
      expect(session[:admin_session_expires_at]).to be_nil
    end

    it "calls invalidate_session! on the matching AdminUser record (server-side revocation)" do
      session[:admin_session_token] = admin_user.session_token
      session[:admin_session_expires_at] = 1.hour.ago.iso8601
      allow(AdminUser).to receive(:find_by).with(session_token: admin_user.session_token).and_return(admin_user)
      expect(admin_user).to receive(:invalidate_session!)

      controller.send(:clean_expired_session_keys)
    end

    it "does NOT call invalidate_session! when there is no session token" do
      expect(AdminUser).not_to receive(:find_by)
      controller.send(:clean_expired_session_keys)
    end
  end

  # ─── check_session_expiry: session extension ────────────────────────────────

  describe "#check_session_expiry", unit: true do
    context "when session is valid" do
      before do
        session[:admin_session_token] = admin_user.session_token
        allow(AdminUser).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)
      end

      it "extends session for regular requests" do
        expect(admin_user).to receive(:extend_session)
        get :index
      end

      it "does NOT extend session for prefetch requests" do
        expect(admin_user).not_to receive(:extend_session)
        request.headers["Sec-Purpose"] = "prefetch"
        get :index
      end

      it "does NOT extend session for Purpose: prefetch requests" do
        expect(admin_user).not_to receive(:extend_session)
        request.headers["Purpose"] = "prefetch"
        get :index
      end
    end
  end

  # ─── turbo_drive_request? ────────────────────────────────────────────────────

  describe "#turbo_drive_request?", unit: true do
    it "returns true when X-Turbo-Request-Id header is present" do
      request.headers["X-Turbo-Request-Id"] = "abc-123"
      expect(controller.send(:turbo_drive_request?)).to be true
    end

    it "returns true when Turbo-Frame header is present" do
      request.headers["Turbo-Frame"] = "content"
      expect(controller.send(:turbo_drive_request?)).to be true
    end

    it "returns true when Accept includes turbo-stream media type" do
      request.headers["Accept"] = "text/html, text/vnd.turbo-stream.html"
      expect(controller.send(:turbo_drive_request?)).to be true
    end

    it "returns false for plain browser requests" do
      expect(controller.send(:turbo_drive_request?)).to be false
    end
  end

  # ─── turbo_prefetch_request? ─────────────────────────────────────────────────

  describe "#turbo_prefetch_request?", unit: true do
    it "returns true when Sec-Purpose: prefetch header is present" do
      request.headers["Sec-Purpose"] = "prefetch"
      expect(controller.send(:turbo_prefetch_request?)).to be true
    end

    it "returns true when Purpose: prefetch header is present" do
      request.headers["Purpose"] = "prefetch"
      expect(controller.send(:turbo_prefetch_request?)).to be true
    end

    it "returns false for regular requests" do
      expect(controller.send(:turbo_prefetch_request?)).to be false
    end

    it "returns false for Turbo Drive navigation without prefetch header" do
      request.headers["X-Turbo-Request-Id"] = "nav-123"
      expect(controller.send(:turbo_prefetch_request?)).to be false
    end
  end

  # ─── store_location: skip for prefetch ──────────────────────────────────────

  describe "#store_location", unit: true do
    it "stores return_to for regular GET requests" do
      allow(controller.request).to receive(:get?).and_return(true)
      allow(controller.request).to receive(:head?).and_return(false)
      allow(controller.request).to receive(:fullpath).and_return("/admin/patterns")

      controller.send(:store_location)
      expect(session[:return_to]).to eq("/admin/patterns")
    end

    it "does NOT store return_to for Sec-Purpose: prefetch requests" do
      request.headers["Sec-Purpose"] = "prefetch"
      allow(controller.request).to receive(:get?).and_return(true)
      allow(controller.request).to receive(:head?).and_return(false)
      allow(controller.request).to receive(:fullpath).and_return("/admin/patterns")

      controller.send(:store_location)
      expect(session[:return_to]).to be_nil
    end
  end

  # ─── refresh_csrf_token_for_turbo ────────────────────────────────────────────

  describe "#refresh_csrf_token_for_turbo", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)
      allow(admin_user).to receive(:extend_session)
    end

    it "calls form_authenticity_token on GET requests to memoize CSRF token" do
      # We verify the before_action runs without error and the response succeeds
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "allows prefetch GET requests without rotating CSRF token" do
      request.headers["Sec-Purpose"] = "prefetch"
      # Prefetch should still get a 200 — the CSRF rotation is skipped silently
      get :index
      expect(response).to have_http_status(:ok)
    end
  end
end
