# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:password) { "TestPass123!" }
  let(:user) { create(:user) }

  # Helper: POST to login and capture session
  def sign_in_as(u, pw = password)
    post login_path, params: { email: u.email, password: pw }
  end

  # ─── GET /login ─────────────────────────────────────────────────────────────

  describe "GET /login", :unit do
    it "returns 200 and renders the sign-in form" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
    end

    it "does not side-effect on Sec-Purpose: prefetch" do
      get login_path, headers: { "Sec-Purpose" => "prefetch" }
      expect(response).to have_http_status(:ok)
      # No session token should be set
      expect(session[:user_session_token]).to be_nil
    end
  end

  # ─── POST /login — valid credentials ────────────────────────────────────────

  describe "POST /login with valid credentials", :unit do
    it "redirects to root_path on success" do
      sign_in_as(user)
      expect(response).to redirect_to(root_path)
    end

    it "sets session[:user_session_token] on success" do
      sign_in_as(user)
      expect(session[:user_session_token]).to be_present
    end

    it "sets session[:user_id] to the authenticated user's id" do
      sign_in_as(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "sets a flash notice on success" do
      sign_in_as(user)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("Signed in successfully")
    end
  end

  # ─── POST /login — invalid credentials ──────────────────────────────────────

  describe "POST /login with invalid password", :unit do
    it "re-renders the login form with 422" do
      post login_path, params: { email: user.email, password: "WrongPassword1!" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not set a session token on failure" do
      post login_path, params: { email: user.email, password: "WrongPassword1!" }
      expect(session[:user_session_token]).to be_nil
    end

    it "shows an error message for invalid password" do
      post login_path, params: { email: user.email, password: "WrongPassword1!" }
      expect(response.body).to include("Invalid email or password")
    end
  end

  describe "POST /login with non-existent email", :unit do
    it "re-renders the login form with 422" do
      post login_path, params: { email: "nobody@example.com", password: password }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "shows a generic error (no user enumeration)" do
      post login_path, params: { email: "nobody@example.com", password: password }
      expect(response.body).to include("Invalid email or password")
    end
  end

  describe "POST /login with blank email and password", :unit do
    it "re-renders the login form with 422 and does not raise" do
      expect { post login_path, params: { email: "", password: "" } }.not_to raise_error
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "shows an error message for blank credentials" do
      post login_path, params: { email: "", password: "" }
      expect(response.body).to include("Invalid email or password")
    end
  end

  # ─── POST /login — account lockout ──────────────────────────────────────────

  describe "POST /login — incremental lockout", :unit do
    it "locks the account after 5 consecutive failed attempts" do
      5.times do
        post login_path, params: { email: user.email, password: "WrongPassword1!" }
      end
      expect(user.reload.locked?).to be true
    end
  end

  describe "POST /login when account is already locked", :unit do
    # Use a recent locked_at so the lock has not expired (LOCK_DURATION = 30 min)
    let(:locked_user) { create(:user, locked_at: 5.minutes.ago, failed_login_attempts: 5) }

    it "returns 422 and shows a generic error message (no enumeration)" do
      post login_path, params: { email: locked_user.email, password: password }
      expect(response).to have_http_status(:unprocessable_content)
      # Generic message to avoid leaking whether the email exists / is locked.
      expect(response.body).to include("Invalid email or password")
      expect(response.body).not_to include("Account locked")
    end
  end

  # ─── POST /login — successful-login redirect target ─────────────────────────

  describe "POST /login — redirect target", :unit do
    it "redirects to root_path when no return_to is stored" do
      sign_in_as(user)
      expect(response).to redirect_to(root_path)
    end

    # Return-to coverage is unit-tested at the concern level via
    # `valid_return_to_path` (see user_authentication_spec) and end-to-end in
    # PR 12 once UserAuthentication guards protected routes. Today the
    # SessionsController is the only consumer of UserAuthentication, so there
    # is no non-login route that stores a return_to through this concern.
  end

  describe "UserAuthentication#require_admin! (role gate)", :unit do
    def invoke_require_admin(controller)
      UserAuthentication.instance_method(:require_admin!).bind_call(controller)
    end

    it "does not raise when current_app_user is admin" do
      ctrl = SessionsController.new
      allow(ctrl).to receive(:current_app_user).and_return(create(:user, :admin))
      expect(ctrl).not_to receive(:render_forbidden)
      invoke_require_admin(ctrl)
    end

    it "renders forbidden when current_app_user is a non-admin user" do
      ctrl = SessionsController.new
      allow(ctrl).to receive(:current_app_user).and_return(create(:user))
      expect(ctrl).to receive(:render_forbidden)
      invoke_require_admin(ctrl)
    end

    it "renders forbidden when current_app_user is nil" do
      ctrl = SessionsController.new
      allow(ctrl).to receive(:current_app_user).and_return(nil)
      expect(ctrl).to receive(:render_forbidden)
      invoke_require_admin(ctrl)
    end
  end

  describe "UserAuthentication#valid_return_to_path (open-redirect guard)", :unit do
    # SessionsController hosts the concern; invoke the private method directly
    # via bind_call so we don't need a full request to cover edge cases.
    def guard(path)
      UserAuthentication.instance_method(:valid_return_to_path)
        .bind_call(SessionsController.new, path)
    end

    it "accepts same-origin user-facing paths" do
      expect(guard("/expenses")).to eq("/expenses")
    end

    it "accepts /admin paths (PR-12: admin role-gate enforced by Admin::BaseController)" do
      expect(guard("/admin/patterns")).to eq("/admin/patterns")
    end

    it "rejects protocol-relative URLs" do
      expect(guard("//evil.com")).to be_nil
      expect(guard("//evil.com/path")).to be_nil
    end

    it "rejects external URLs" do
      expect(guard("https://evil.com")).to be_nil
    end

    it "rejects blank input" do
      expect(guard(nil)).to be_nil
      expect(guard("")).to be_nil
    end
  end

  # ─── DELETE /logout ──────────────────────────────────────────────────────────

  describe "DELETE /logout when signed in", :unit do
    before { sign_in_as(user) }

    it "clears the session" do
      delete logout_path
      expect(session[:user_session_token]).to be_nil
      expect(session[:user_id]).to be_nil
    end

    it "redirects to login_path with a notice" do
      delete logout_path
      expect(response).to redirect_to(login_path)
    end

    it "shows a signed-out flash notice after redirect" do
      delete logout_path
      expect(flash[:notice]).to include("signed out successfully")
    end

    it "invalidates the session token in the database" do
      delete logout_path
      expect(user.reload.session_token).to be_nil
    end
  end

  describe "DELETE /logout when not signed in", :unit do
    it "still redirects gracefully to login_path" do
      delete logout_path
      expect(response).to redirect_to(login_path)
    end

    it "does not raise an error when not signed in" do
      expect { delete logout_path }.not_to raise_error
    end
  end

  # ─── PER-213: prefetch does not side-effect ──────────────────────────────────

  describe "GET /login with Sec-Purpose: prefetch", :unit do
    it "returns 200 and does not set any session keys" do
      get login_path, headers: { "Sec-Purpose" => "prefetch" }
      expect(response).to have_http_status(:ok)
      expect(session[:user_session_token]).to be_nil
    end
  end

  # ─── Rate limiting ────────────────────────────────────────────────────────────

  describe "rate limiting", :unit do
    it "is skipped in the test environment (rack_attack initializer returns early)" do
      # The initializer has `return if Rails.env.test?`, so Rack::Attack
      # is not inserted into the middleware stack during tests.
      # This test asserts that 10 rapid POSTs do not trigger a 429.
      10.times do
        post login_path, params: { email: user.email, password: "WrongPassword1!" }
      end
      # Should be 422 (failed auth), never 429 (rate limit)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
