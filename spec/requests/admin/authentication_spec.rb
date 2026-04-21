# frozen_string_literal: true

require "rails_helper"

# PR-12: Verify admin routes require authentication before granting access.
# Unauthenticated requests MUST redirect to /login (unified login — no /admin/login).
# Admin-role users MUST be able to access protected admin pages.
# Non-admin authenticated users MUST be redirected/forbidden from admin pages.
RSpec.describe "Admin Authentication", type: :request do
  let(:password) { "AdminPassword123!" }
  let(:admin_user) { create(:user, :admin, password: password) }
  let(:regular_user) { create(:user, password: password) }

  # ─── Admin::PatternsController ─────────────────────────────────────────────

  describe "Admin::PatternsController", :unit do
    context "when unauthenticated" do
      it "redirects GET /admin/patterns to unified login" do
        get admin_patterns_path
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/new to unified login" do
        get new_admin_pattern_path
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/:id to unified login" do
        get admin_pattern_path(id: 999)
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects POST /admin/patterns to unified login" do
        post admin_patterns_path, params: {}
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects GET /admin/patterns/:id/edit to unified login" do
        get edit_admin_pattern_path(id: 999)
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects DELETE /admin/patterns/:id to unified login" do
        delete admin_pattern_path(id: 999)
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end

      it "redirects PATCH /admin/patterns/:id to unified login" do
        patch admin_pattern_path(id: 999), params: {}
        expect(response).to redirect_to(login_path)
        expect(response).to have_http_status(:found)
      end
    end

    context "when authenticated as admin" do
      before { sign_in_as(admin_user, password: password) }

      it "does NOT redirect GET /admin/patterns to login" do
        get admin_patterns_path
        expect(response).not_to redirect_to(login_path)
      end

      it "does NOT redirect GET /admin/patterns/new to login" do
        get new_admin_pattern_path
        expect(response).not_to redirect_to(login_path)
      end

      it "does NOT redirect GET /admin/patterns/:id to login" do
        pattern = create(:categorization_pattern)
        get admin_pattern_path(pattern)
        expect(response).not_to redirect_to(login_path)
      end

      it "does NOT redirect POST /admin/patterns to login" do
        post admin_patterns_path, params: { categorization_pattern: { name: "Test", pattern: "foo", category_id: create(:category).id } }
        expect(response).not_to redirect_to(login_path)
      end
    end

    context "when authenticated as non-admin (regular user)" do
      before { sign_in_as(regular_user, password: password) }

      it "does not allow GET /admin/patterns (redirects with Forbidden alert)" do
        get admin_patterns_path
        # require_admin! calls render_forbidden which for HTML format
        # redirects back with a "Forbidden" alert (fallback to root_path).
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Forbidden")
      end
    end
  end

  # ─── /admin/login no longer exists ─────────────────────────────────────────

  describe "Legacy /admin/login route", :unit do
    it "does NOT exist — GET /admin/login returns 404" do
      # Rails 8 with show_exceptions: :rescuable returns 404 instead of raising in request specs.
      get "/admin/login"
      expect(response).to have_http_status(:not_found)
    end
  end
end
