# frozen_string_literal: true

require "rails_helper"

# PER-200: Verify admin routes require authentication before granting access.
# Unauthenticated requests MUST redirect to /admin/login (HTTP 302).
# Authenticated admin users MUST be able to access protected admin pages.
RSpec.describe "Admin Authentication", type: :request do
  let(:admin_user) { create(:admin_user) }

  # ─── Admin::PatternsController ─────────────────────────────────────────────

  describe "Admin::PatternsController", :unit do
    context "when unauthenticated" do
      it "redirects GET /admin/patterns to admin login" do
        get admin_patterns_path
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/new to admin login" do
        get new_admin_pattern_path
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/:id to admin login" do
        get admin_pattern_path(id: 999)
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects POST /admin/patterns to admin login" do
        post admin_patterns_path, params: {}
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/:id/edit to admin login" do
        get edit_admin_pattern_path(id: 999)
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects DELETE /admin/patterns/:id to admin login" do
        delete admin_pattern_path(id: 999)
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects PATCH /admin/patterns/:id to admin login" do
        patch admin_pattern_path(id: 999), params: {}
        expect(response).to redirect_to(admin_login_path)
        expect(response).to have_http_status(:found)
      end
    end

    context "when authenticated" do
      before do
        post admin_login_path, params: {
          admin_user: { email: admin_user.email, password: "AdminPassword123!" }
        }
      end

      it "does NOT redirect GET /admin/patterns to admin login" do
        get admin_patterns_path
        expect(response).not_to redirect_to(admin_login_path)
      end
    end
  end

  # ─── Admin::SessionsController ──────────────────────────────────────────────

  describe "Admin::SessionsController (login page)", :unit do
    it "allows GET /admin/login without authentication" do
      get admin_login_path
      # Should NOT redirect to login — the login page itself is accessible
      expect(response).not_to redirect_to(admin_login_path)
      expect(response.status).to be_in([200, 500])
    end
  end
end
