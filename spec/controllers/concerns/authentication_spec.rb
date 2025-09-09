# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Authentication, type: :controller, unit: true do
  controller(ApplicationController) do
    include Authentication

    before_action :require_admin!, only: [ :admin_action ]

    def index
      render json: { message: 'success' }
    end

    def admin_action
      render json: { message: 'admin content' }
    end

    def permission_check
      result = current_user&.can_manage_patterns? || false
      render json: { can_manage_patterns: result }
    end

    private

    def admin_login_path
      '/admin/login'
    end

    def root_path
      '/'
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'admin_action' => 'anonymous#admin_action'
      get 'permission_check' => 'anonymous#permission_check'
    end
  end

  let!(:admin_user) do
    AdminUser.create!(
      name: 'Test User',
      email: 'user@test.com',
      password: 'Password123!',
      role: 'admin'
    )
  end

  # Note: Cannot use authentication concern shared examples as
  # methods are private and not accessible

  describe "authentication enforcement", unit: true do
    it "allows access when user is authenticated" do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)

      get :index
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when user is not authenticated" do
      get :index
      expect(response).to redirect_to('/admin/login')
    end

    it "stores location for redirect after login" do
      get :index
      expect(session[:return_to]).to eq('/index')
    end
  end

  describe "session management", unit: true do
    context "with valid session" do
      before do
        session[:admin_session_token] = admin_user.session_token
        allow(AdminUser).to receive(:find_by_valid_session).with(admin_user.session_token).and_return(admin_user)
      end

      it "finds current user from session" do
        expect(controller.send(:current_user)).to eq(admin_user)
      end

      it "returns true for user_signed_in?" do
        expect(controller.send(:user_signed_in?)).to be true
      end

      it "returns user ID for current_user_id" do
        expect(controller.send(:current_user_id)).to eq(admin_user.id)
      end
    end

    context "with no session" do
      it "returns nil for current_user" do
        expect(controller.send(:current_user)).to be_nil
      end

      it "returns false for user_signed_in?" do
        expect(controller.send(:user_signed_in?)).to be false
      end

      it "raises error for current_user_id" do
        expect { controller.send(:current_user_id) }.to raise_error("No authenticated user")
      end
    end
  end

  describe "admin authorization", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
    end

    it "allows access when user is admin" do
      allow(admin_user).to receive(:admin?).and_return(true)

      get :admin_action
      expect(response).to have_http_status(:ok)
    end

    it "denies access when user is not admin" do
      allow(admin_user).to receive(:admin?).and_return(false)

      get :admin_action
      expect(response).to redirect_to('/')
    end
  end

  describe "permission checking", unit: true do
    before do
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
    end

    it "handles permission method delegation" do
      allow(admin_user).to receive(:can_manage_patterns?).and_return(true)

      get :permission_check
      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['can_manage_patterns']).to be true
    end

    it "returns nil when user is not signed in" do
      session.clear

      get :permission_check
      expect(response).to redirect_to('/admin/login')
    end
  end

  describe "location storage", unit: true do
    it "stores location only for GET requests" do
      allow(controller.request).to receive(:get?).and_return(true)
      allow(controller.request).to receive(:head?).and_return(false)
      allow(controller.request).to receive(:fullpath).and_return('/some/path')

      controller.send(:store_location)
      expect(session[:return_to]).to eq('/some/path')
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
      session[:admin_session_token] = admin_user.session_token
      allow(AdminUser).to receive(:find_by_valid_session).and_return(admin_user)
      allow(Rails.logger).to receive(:info)
      allow(controller).to receive(:request).and_return(double(remote_ip: '127.0.0.1'))
      allow(controller).to receive(:controller_name).and_return('test')
      allow(controller).to receive(:action_name).and_return('index')
    end

    it "logs user actions with comprehensive details" do
      freeze_time do
        controller.send(:log_user_action, 'test_action', { test: 'data' })

        expected_log = {
          event: "user_action",
          user_id: admin_user.id,
          action: 'test_action',
          details: { test: 'data' },
          controller: 'test',
          action_name: 'index',
          ip_address: '127.0.0.1',
          timestamp: Time.current.iso8601
        }.to_json

        expect(Rails.logger).to have_received(:info).with(expected_log)
      end
    end

    it "handles user actions when not signed in" do
      session.clear

      freeze_time do
        controller.send(:log_user_action, 'anonymous_action')

        expected_log = {
          event: "user_action",
          user_id: nil,
          action: 'anonymous_action',
          details: {},
          controller: 'test',
          action_name: 'index',
          ip_address: '127.0.0.1',
          timestamp: Time.current.iso8601
        }.to_json

        expect(Rails.logger).to have_received(:info).with(expected_log)
      end
    end
  end
end
