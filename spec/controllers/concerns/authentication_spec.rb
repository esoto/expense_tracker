# frozen_string_literal: true

require "rails_helper"

# PR-12: Legacy Authentication concern deleted — ApplicationController now uses
# UserAuthentication directly. This spec now tests UserAuthentication behavior,
# including the legacy aliases current_user, current_admin_user, etc.
RSpec.describe UserAuthentication, type: :controller, unit: true do
  controller(ApplicationController) do
    skip_before_action :require_authentication, only: [ :public_action ]

    def index
      render json: { message: "success" }
    end

    def public_action
      render json: { message: "public" }
    end

    def admin_action
      require_admin!
      render json: { message: "admin content" } unless performed?
    end

    def permission_check
      result = current_user&.can_manage_patterns? || false
      render json: { can_manage_patterns: result }
    end

    private

    def root_path
      "/"
    end
  end

  before do
    routes.draw do
      get "index"           => "anonymous#index"
      get "public_action"   => "anonymous#public_action"
      get "admin_action"    => "anonymous#admin_action"
      get "permission_check" => "anonymous#permission_check"
    end
  end

  let!(:admin_user) do
    create(:user, :admin,
      name: "Test User",
      email: "user-#{SecureRandom.hex(4)}@test.com",
      password: "Password123!"
    )
  end

  describe "authentication enforcement", unit: true do
    it "allows access when user is authenticated via user_session_token" do
      session[:user_session_token] = admin_user.session_token
      session[:user_session_expires_at] = 2.hours.from_now.iso8601
      allow(User).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)

      get :index
      expect(response).to have_http_status(:ok)
    end

    it "redirects to unified /login when user is not authenticated" do
      get :index
      expect(response).to redirect_to(login_path)
    end

    it "stores location for redirect after login" do
      get :index
      expect(session[:return_to]).to eq("/index")
    end

    it "does not require authentication for public action" do
      get :public_action
      expect(response).to have_http_status(:ok)
    end
  end

  describe "session management", unit: true do
    context "with valid session" do
      before do
        session[:user_session_token] = admin_user.session_token
        session[:user_session_expires_at] = 2.hours.from_now.iso8601
        allow(User).to receive(:find_by_valid_session)
          .with(admin_user.session_token, extend: false)
          .and_return(admin_user)
      end

      it "finds current_app_user from session" do
        expect(controller.send(:current_app_user)).to eq(admin_user)
      end

      it "exposes current_user alias (legacy)" do
        expect(controller.send(:current_user)).to eq(admin_user)
      end

      it "exposes current_admin_user alias (legacy)" do
        expect(controller.send(:current_admin_user)).to eq(admin_user)
      end

      it "returns true for app_user_signed_in?" do
        expect(controller.send(:app_user_signed_in?)).to be true
      end

      it "returns true for user_signed_in? alias" do
        expect(controller.send(:user_signed_in?)).to be true
      end

      it "returns true for admin_signed_in? alias" do
        expect(controller.send(:admin_signed_in?)).to be true
      end
    end

    context "with no session" do
      it "returns nil for current_app_user" do
        expect(controller.send(:current_app_user)).to be_nil
      end

      it "returns nil for current_user" do
        expect(controller.send(:current_user)).to be_nil
      end

      it "returns false for app_user_signed_in?" do
        expect(controller.send(:app_user_signed_in?)).to be false
      end
    end
  end

  describe "admin authorization via require_admin!", unit: true do
    before do
      session[:user_session_token] = admin_user.session_token
      session[:user_session_expires_at] = 2.hours.from_now.iso8601
      allow(User).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)
    end

    it "allows access when user has admin role" do
      allow(admin_user).to receive(:admin?).and_return(true)
      get :admin_action
      expect(response).to have_http_status(:ok)
    end

    it "denies access when user does not have admin role" do
      allow(admin_user).to receive(:admin?).and_return(false)
      get :admin_action
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "permission checking (via User#can_*? methods)", unit: true do
    before do
      session[:user_session_token] = admin_user.session_token
      session[:user_session_expires_at] = 2.hours.from_now.iso8601
      allow(User).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)
    end

    it "handles can_manage_patterns? delegation to User" do
      allow(admin_user).to receive(:can_manage_patterns?).and_return(true)
      get :permission_check
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["can_manage_patterns"]).to be true
    end
  end

  describe "location storage", unit: true do
    it "stores location only for GET requests" do
      allow(controller.request).to receive(:get?).and_return(true)
      allow(controller.request).to receive(:head?).and_return(false)
      allow(controller.request).to receive(:fullpath).and_return("/some/path")

      controller.send(:store_location)
      expect(session[:return_to]).to eq("/some/path")
    end

    it "does not store location for HEAD requests" do
      allow(controller.request).to receive(:get?).and_return(false)
      allow(controller.request).to receive(:head?).and_return(true)

      controller.send(:store_location)
      expect(session[:return_to]).to be_nil
    end

    it "does not store location for POST requests" do
      allow(controller.request).to receive(:get?).and_return(false)
      allow(controller.request).to receive(:head?).and_return(false)

      controller.send(:store_location)
      expect(session[:return_to]).to be_nil
    end
  end

  describe "audit logging", unit: true do
    before do
      session[:user_session_token] = admin_user.session_token
      session[:user_session_expires_at] = 2.hours.from_now.iso8601
      allow(User).to receive(:find_by_valid_session).with(anything, extend: false).and_return(admin_user)
      allow(Rails.logger).to receive(:info)
      mock_headers = double("headers", :[] => nil)
      allow(controller).to receive(:request).and_return(
        double(remote_ip: "127.0.0.1", user_agent: "Test Agent", headers: mock_headers)
      )
    end

    it "log_admin_action delegates to log_app_user_action" do
      freeze_time do
        expected_log = {
          event: "user_action",
          user_id: admin_user.id,
          user_email: admin_user.email,
          action: "test_action",
          details: { test: "data" },
          ip_address: "127.0.0.1",
          user_agent: "Test Agent",
          timestamp: Time.current.iso8601
        }.to_json

        expect(Rails.logger).to receive(:info).with(expected_log)
        controller.send(:log_admin_action, "test_action", { test: "data" })
      end
    end
  end
end
