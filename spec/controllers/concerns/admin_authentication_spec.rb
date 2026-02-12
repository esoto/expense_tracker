# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminAuthentication, type: :controller, unit: true do
  controller(ApplicationController) do
    include AdminAuthentication

    before_action :require_pattern_management_permission, only: [ :pattern_management ]
    before_action :require_statistics_permission, only: [ :statistics ]

    def index
      render json: { message: 'admin dashboard' }
    end

    def restricted_action
      render json: { message: 'restricted content' }
    end

    def pattern_management
      render json: { message: 'pattern management' }
    end

    def statistics
      render json: { message: 'statistics' }
    end

    private

    def admin_login_path
      '/admin/login'
    end

    def admin_root_path
      '/admin'
    end

    def root_path
      '/'
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'restricted_action' => 'anonymous#restricted_action'
      get 'pattern_management' => 'anonymous#pattern_management'
      get 'statistics' => 'anonymous#statistics'
    end
  end

  let!(:admin_user) do
    AdminUser.create!(
      name: 'Test Admin',
      email: 'admin@test.com',
      password: 'Password123!',
      role: 'admin'
    )
  end

  # Use shared examples for admin-specific behavior
  it_behaves_like "security headers concern"

  describe "authentication enforcement", unit: true do
    it "allows access when admin is authenticated" do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)

      get :index
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when admin is not authenticated" do
      get :index
      expect(response).to redirect_to('/admin/login')
      expect(flash[:alert]).to eq("Please sign in to continue.")
    end

    it "stores location for redirect after login" do
      get :restricted_action
      expect(session[:return_to]).to eq('/restricted_action')
    end
  end

  describe "session management", unit: true do
    context "with valid session" do
      before do
        session[:admin_session_token] = admin_user.session_token
        allow(AdminUser).to receive(:find_by_valid_session).with(admin_user.session_token).and_return(admin_user)
      end

      it "finds current admin user from session" do
        expect(controller.send(:current_admin_user)).to eq(admin_user)
      end

      it "returns true for admin_signed_in?" do
        expect(controller.send(:admin_signed_in?)).to be true
      end

      it "extends session on activity" do
        expect(admin_user).to receive(:extend_session)
        get :index
      end
    end

    context "with expired session" do
      before do
        session[:admin_session_token] = admin_user.session_token
        allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
        allow(admin_user).to receive(:session_expired?).and_return(true)
      end

      it "invalidates expired session and redirects" do
        expect(admin_user).to receive(:invalidate_session!)
        expect(controller).to receive(:reset_session)

        get :index
        expect(response).to redirect_to('/admin/login')
        expect(flash[:alert]).to eq("Your session has expired. Please sign in again.")
      end
    end

    context "with no session" do
      it "returns nil for current_admin_user" do
        expect(controller.send(:current_admin_user)).to be_nil
      end

      it "returns false for admin_signed_in?" do
        expect(controller.send(:admin_signed_in?)).to be false
      end
    end
  end

  describe "security headers", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
    end

    it "sets security headers on requests" do
      get :index

      expect(response.headers["X-Frame-Options"]).to eq("DENY")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["X-XSS-Protection"]).to eq("1; mode=block")
      expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
      expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'")
    end

    it "includes comprehensive CSP directives" do
      get :index

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net")
      expect(csp).to include("style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net")
      expect(csp).to include("frame-ancestors 'none'")
      expect(csp).to include("base-uri 'self'")
    end
  end

  describe "authorization helpers", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
    end

    context "pattern management permissions" do
      it "allows access when user can manage patterns" do
        allow(admin_user).to receive(:can_manage_patterns?).and_return(true)

        get :pattern_management, format: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('pattern management')
      end

      it "denies access when user cannot manage patterns" do
        allow(admin_user).to receive(:can_manage_patterns?).and_return(false)

        get :pattern_management, format: :json
        expect(response).to have_http_status(:forbidden)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq("You don't have permission to manage patterns.")
      end
    end

    context "statistics permissions" do
      it "allows access when user can access statistics" do
        allow(admin_user).to receive(:can_access_statistics?).and_return(true)

        get :statistics, format: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('statistics')
      end

      it "denies access when user cannot access statistics" do
        allow(admin_user).to receive(:can_access_statistics?).and_return(false)

        get :statistics, format: :json
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq("You don't have permission to access statistics.")
      end
    end
  end

  describe "session helpers", unit: true do
    it "sets admin session with security measures" do
      expect(controller).to receive(:reset_session)

      controller.send(:set_admin_session, admin_user)

      expect(session[:admin_session_token]).to eq(admin_user.session_token)
      expect(session[:admin_user_id]).to eq(admin_user.id)
    end

    it "clears admin session completely" do
      session[:admin_session_token] = admin_user.session_token
      session[:admin_user_id] = admin_user.id
      controller.instance_variable_set(:@current_admin_user, admin_user)

      expect(controller).to receive(:reset_session)

      controller.send(:clear_admin_session)
    end

    it "redirects back to stored location" do
      session[:return_to] = '/admin/dashboard'

      expect(controller).to receive(:redirect_to).with('/admin/dashboard')
      controller.send(:redirect_back_or, '/admin')

      expect(session[:return_to]).to be_nil
    end
  end

  describe "audit logging", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
      allow(Rails.logger).to receive(:info)
      allow(controller).to receive(:request).and_return(double(remote_ip: '127.0.0.1', user_agent: 'Test Agent'))
    end

    it "logs admin actions with comprehensive details" do
      freeze_time do
        controller.send(:log_admin_action, 'test_action', { test: 'data' })

        expected_log = {
          event: "admin_action",
          admin_user_id: admin_user.id,
          admin_email: admin_user.email,
          action: 'test_action',
          details: { test: 'data' },
          ip_address: '127.0.0.1',
          user_agent: 'Test Agent',
          timestamp: Time.current.iso8601
        }.to_json

        expect(Rails.logger).to have_received(:info).with(expected_log)
      end
    end

    it "includes admin details in logs" do
      controller.send(:log_admin_action, 'test_action', { test: 'data' })

      expect(Rails.logger).to have_received(:info) do |log_json|
        log_data = JSON.parse(log_json)
        expect(log_data['admin_user_id']).to eq(admin_user.id)
        expect(log_data['admin_email']).to eq(admin_user.email)
        expect(log_data['action']).to eq('test_action')
        expect(log_data['details']).to eq({ 'test' => 'data' })
      end
    end
  end

  describe "location storage", unit: true do
    it "stores location only for GET requests" do
      allow(controller.request).to receive(:get?).and_return(true)
      allow(controller.request).to receive(:head?).and_return(false)
      allow(controller.request).to receive(:fullpath).and_return('/admin/dashboard')

      controller.send(:store_location)
      expect(session[:return_to]).to eq('/admin/dashboard')
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
end
