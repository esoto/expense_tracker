# frozen_string_literal: true

require "rails_helper"

# PR-12: Admin sessions are now handled by the unified SessionsController at /login.
# This spec verifies:
#   - /admin/login no longer exists (route removed)
#   - Admin users sign in via /login like all other users
#   - After sign-in, admin users can access /admin routes
#   - Redirect-back after auth still works for /admin paths
RSpec.describe "Admin login via unified /login", type: :request do
  let(:password) { "AdminPassword123!" }
  let(:admin_user) do
    create(:user, :admin,
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: password
    )
  end

  before do
    Rails.cache.delete("login_attempts:127.0.0.1")
  end

  describe "GET /admin/login — route no longer exists", :unit do
    it "returns 404 (route was removed in PR-12)" do
      # Rails 8 with show_exceptions: :rescuable returns 404 instead of raising in request specs.
      get "/admin/login"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/login — route no longer exists", :unit do
    it "returns 404 (route was removed in PR-12)" do
      post "/admin/login", params: { admin_user: { email: admin_user.email, password: password } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Admin login via POST /login", :unit do
    context "with correct credentials" do
      it "redirects to root_path after successful direct login" do
        post login_path, params: { email: admin_user.email, password: password }
        expect(response).to redirect_to(root_path)
      end
    end

    context "with wrong password" do
      it "returns 422 Unprocessable Content" do
        post login_path, params: { email: admin_user.email, password: "wrong_password" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders the login form (not a redirect)" do
        post login_path, params: { email: admin_user.email, password: "wrong_password" }
        expect(response).not_to be_redirect
      end

      # PER-181: Password must never be reflected back in the response body
      it "does NOT include the submitted password value in the response body" do
        submitted_password = "wrong_password_per181"
        post login_path, params: { email: admin_user.email, password: submitted_password }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).not_to include(submitted_password)
      end
    end

    context "with a locked admin account" do
      let(:locked_admin) do
        create(:user, :admin, :locked,
          email: "locked-admin-#{SecureRandom.hex(4)}@example.com",
          password: password
        )
      end

      it "returns 422 and renders the form (not a redirect)" do
        post login_path, params: { email: locked_admin.email, password: "wrong_password" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response).not_to be_redirect
      end
    end
  end

  describe "Admin access to /admin after unified login", :unit do
    context "when signed in as admin via /login" do
      before { sign_in_as(admin_user, password: password) }

      it "allows access to GET /admin/patterns after signing in" do
        get admin_patterns_path
        expect(response).not_to redirect_to(login_path)
      end
    end
  end

  describe "POST /login redirect-back for admin paths (PER-180)", :unit do
    context "when the admin requested a protected /admin path before logging in" do
      it "redirects to the originally requested admin path after successful login" do
        # Step 1: visit a protected resource (unauthenticated)
        get admin_patterns_path
        expect(response).to redirect_to(login_path)

        # Step 2: follow the redirect to login page (session[:return_to] is now stored)
        follow_redirect!

        # Step 3: login — should redirect back to the originally requested path
        post login_path, params: { email: admin_user.email, password: password }
        expect(response).to redirect_to(admin_patterns_path)
      end
    end

    context "when there is no stored return path (direct login)" do
      it "redirects to root_path after successful login" do
        post login_path, params: { email: admin_user.email, password: password }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "DELETE /logout (unified)", :unit do
    context "when authenticated as admin" do
      before { sign_in_as(admin_user, password: password) }

      it "redirects to the unified login page" do
        delete logout_path
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
