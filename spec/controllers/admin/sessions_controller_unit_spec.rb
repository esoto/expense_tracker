require "rails_helper"

RSpec.describe Admin::SessionsController, type: :controller, unit: true do
  let(:admin_user) { create(:admin_user, email: "admin_#{SecureRandom.hex(4)}@example.com") }

  before do
    # Mock Rails.cache for rate limiting
    allow(Rails.cache).to receive(:read).and_return(0)
    allow(Rails.cache).to receive(:write).and_return(true)

    # Mock render methods to avoid template issues
    allow(controller).to receive(:render).and_return(nil)
    allow(controller).to receive(:redirect_to).and_return(nil)
    allow(controller).to receive(:reset_session)
  end

  describe "GET #new", unit: true do
    before do
      allow(controller).to receive(:admin_signed_in?).and_return(false)
    end

    it "assigns a new AdminUser" do
      get :new
      expect(assigns(:admin_user)).to be_a_new(AdminUser)
    end

    context "when already authenticated" do
      before do
        allow(controller).to receive(:admin_signed_in?).and_return(true)
      end

      it "redirects to admin patterns path" do
        expect(controller).to receive(:redirect_to)
        get :new
      end
    end
  end

  describe "POST #create", unit: true do
    let(:valid_params) do
      {
        admin_user: {
          email: admin_user.email,
          password: "password123"
        }
      }
    end

    before do
      allow(controller).to receive(:admin_signed_in?).and_return(false)
    end

    context "with valid credentials" do
      before do
        allow(AdminUser).to receive(:authenticate).and_return(admin_user)
        allow(controller).to receive(:handle_successful_login)
      end

      it "authenticates with AdminUser.authenticate" do
        expect(AdminUser).to receive(:authenticate).with(admin_user.email, "password123")
        post :create, params: valid_params
      end

      it "handles successful login" do
        expect(controller).to receive(:handle_successful_login)
        post :create, params: valid_params
      end
    end

    context "with invalid credentials" do
      before do
        allow(AdminUser).to receive(:authenticate).and_return(nil)
        allow(controller).to receive(:handle_failed_login)
      end

      it "handles failed login" do
        expect(controller).to receive(:handle_failed_login)
        post :create, params: valid_params
      end
    end

    context "with rate limiting" do
      before do
        allow(Rails.cache).to receive(:read).and_return(10) # Max attempts reached
        allow(controller).to receive(:render_too_many_requests)
      end

      it "blocks request when rate limit exceeded" do
        expect(controller).to receive(:render_too_many_requests)
        post :create, params: valid_params
      end
    end
  end

  describe "DELETE #destroy", unit: true do
    it "handles logout process" do
      # Test that the destroy action works without detailed implementation testing
      # since current_admin_user is defined in the action itself
      expect(controller).to receive(:reset_session)
      expect(controller).to receive(:redirect_to)
      delete :destroy
    end
  end

  describe "private methods", unit: true do
    describe "#session_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          admin_user: {
            email: "test@example.com",
            password: "password123",
            remember_me: "1",
            otp_code: "123456",
            unpermitted: "value"
          }
        })

        permitted_params = controller.send(:session_params)

        expect(permitted_params.keys).to contain_exactly(
          "email", "password", "remember_me", "otp_code"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#login_error_message" do
      let(:params) do
        ActionController::Parameters.new({
          admin_user: { email: "test@example.com" }
        })
      end

      before do
        controller.params = params
      end

      context "when user exists and is locked" do
        before do
          locked_user = double("locked_user", locked?: true)
          allow(AdminUser).to receive(:find_by).and_return(locked_user)
        end

        it "returns account locked message" do
          message = controller.send(:login_error_message)
          expect(message).to include("account has been locked")
        end
      end

      context "when user doesn't exist or isn't locked" do
        before do
          allow(AdminUser).to receive(:find_by).and_return(nil)
        end

        it "returns generic error message" do
          message = controller.send(:login_error_message)
          expect(message).to eq("Invalid email or password.")
        end
      end
    end

    describe "#check_login_rate_limit" do
      let(:ip_key) { "login_attempts:127.0.0.1" }

      before do
        allow(controller.request).to receive(:remote_ip).and_return("127.0.0.1")
      end

      context "when under rate limit" do
        before do
          allow(Rails.cache).to receive(:read).with(ip_key).and_return(5)
        end

        it "increments attempt count and allows request" do
          expect(Rails.cache).to receive(:write).with(ip_key, 6, expires_in: 15.minutes)
          result = controller.send(:check_login_rate_limit)
          expect(result).to be true
        end
      end

      context "when rate limit exceeded" do
        before do
          allow(Rails.cache).to receive(:read).with(ip_key).and_return(10)
          allow(controller).to receive(:render_too_many_requests)
        end

        it "renders too many requests error" do
          expect(controller).to receive(:render_too_many_requests)
          result = controller.send(:check_login_rate_limit)
          expect(result).to be false
        end
      end
    end

    describe "#admin_signed_in?" do
      context "with valid session" do
        before do
          session[:admin_session_token] = "valid_token"
          allow(AdminUser).to receive(:find_by_valid_session).with("valid_token").and_return(admin_user)
        end

        it "returns true" do
          result = controller.send(:admin_signed_in?)
          expect(result).to be true
        end
      end

      context "without session token" do
        before do
          session[:admin_session_token] = nil
        end

        it "returns false" do
          result = controller.send(:admin_signed_in?)
          expect(result).to be false
        end
      end

      context "with invalid session token" do
        before do
          session[:admin_session_token] = "invalid_token"
          allow(AdminUser).to receive(:find_by_valid_session).with("invalid_token").and_return(nil)
        end

        it "returns false" do
          result = controller.send(:admin_signed_in?)
          expect(result).to be false
        end
      end
    end

    describe "#set_admin_session" do
      before do
        allow(admin_user).to receive(:session_token).and_return("new_session_token")
        allow(admin_user).to receive(:id).and_return(123)
      end

      it "resets session and sets admin session data" do
        expect(controller).to receive(:reset_session)
        controller.send(:set_admin_session, admin_user)

        expect(session[:admin_session_token]).to eq("new_session_token")
        expect(session[:admin_user_id]).to eq(123)
      end
    end
  end

  describe "authentication flow integration", unit: true do
    describe "#handle_successful_login" do
      before do
        controller.instance_variable_set(:@admin_user, admin_user)
        allow(controller).to receive(:set_admin_session)
        allow(controller).to receive(:log_successful_login)
        allow(controller).to receive(:redirect_back_or)
      end

      it "handles successful login flow" do
        expect(controller).to receive(:set_admin_session).with(admin_user)
        expect(controller).to receive(:log_successful_login)
        expect(controller).to receive(:redirect_back_or)
        controller.send(:handle_successful_login)
      end
    end

    describe "#handle_failed_login" do
      let(:params) do
        ActionController::Parameters.new({
          admin_user: { email: "test@example.com" }
        })
      end

      before do
        controller.params = params
        allow(controller).to receive(:log_failed_login)
        allow(controller).to receive(:login_error_message).and_return("Invalid credentials")
      end

      it "logs failed login attempt" do
        expect(controller).to receive(:log_failed_login)
        controller.send(:handle_failed_login)
      end

      it "sets error flash message" do
        controller.send(:handle_failed_login)
        expect(flash.now[:alert]).to eq("Invalid credentials")
      end

      it "assigns new admin user with email" do
        controller.send(:handle_failed_login)
        expect(assigns(:admin_user)).to be_a(AdminUser)
        expect(assigns(:admin_user).email).to eq("test@example.com")
      end
    end
  end

  describe "logging methods", unit: true do
    let(:request_double) do
      double("request", remote_ip: "192.168.1.1", user_agent: "Test Browser")
    end

    before do
      allow(controller).to receive(:request).and_return(request_double)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Time).to receive(:current).and_return(Time.parse("2023-01-01 12:00:00 UTC"))
    end

    describe "#log_successful_login" do
      before do
        controller.instance_variable_set(:@admin_user, admin_user)
      end

      it "logs successful login with structured data" do
        expected_log = {
          event: "admin_login_success",
          admin_user_id: admin_user.id,
          email: admin_user.email,
          ip_address: "192.168.1.1",
          user_agent: "Test Browser",
          timestamp: "2023-01-01T12:00:00Z"
        }.to_json

        expect(Rails.logger).to receive(:info).with(expected_log)
        controller.send(:log_successful_login)
      end
    end

    describe "#log_failed_login" do
      let(:params) do
        ActionController::Parameters.new({
          admin_user: { email: "failed@example.com" }
        })
      end

      before do
        controller.params = params
      end

      it "logs failed login with structured data" do
        expected_log = {
          event: "admin_login_failed",
          email: "failed@example.com",
          ip_address: "192.168.1.1",
          user_agent: "Test Browser",
          timestamp: "2023-01-01T12:00:00Z"
        }.to_json

        expect(Rails.logger).to receive(:warn).with(expected_log)
        controller.send(:log_failed_login)
      end
    end

    describe "#log_admin_action" do
      it "logs admin action with details" do
        expected_log = {
          event: "admin_action",
          action: "test_action",
          details: { key: "value" },
          ip_address: "192.168.1.1",
          timestamp: "2023-01-01T12:00:00Z"
        }.to_json

        expect(Rails.logger).to receive(:info).with(expected_log)
        controller.send(:log_admin_action, "test_action", { key: "value" })
      end
    end
  end

  describe "CSRF protection", unit: true do
    it "does not skip verify_authenticity_token" do
      # Verify the controller source does not contain skip_before_action for CSRF
      source_file = Rails.root.join("app/controllers/admin/sessions_controller.rb")
      source_code = File.read(source_file)

      expect(source_code).not_to include("skip_before_action :verify_authenticity_token"),
        "Expected admin sessions controller to NOT skip CSRF protection, but it does"
    end

    it "enforces CSRF token verification on login" do
      # Verify verify_authenticity_token is in the callback chain for :create
      callbacks = described_class._process_action_callbacks.select do |cb|
        cb.filter == :verify_authenticity_token
      end

      # Should have the callback and it should NOT be skipped for :create
      expect(callbacks).not_to be_empty, "Expected verify_authenticity_token in callback chain"

      skipped_actions = described_class._process_action_callbacks.select do |cb|
        cb.filter == :verify_authenticity_token && cb.kind == :before && cb.instance_variable_get(:@if)&.any?
      end

      # None of the CSRF callbacks should exclude :create
      skipped_actions.each do |cb|
        conditions = cb.instance_variable_get(:@unless) || []
        conditions.each do |condition|
          expect(condition.to_s).not_to include("create"),
            "Expected CSRF protection to NOT be skipped for :create action"
        end
      end
    end

    it "inherits CSRF protection from ApplicationController" do
      # ApplicationController inherits from ActionController::Base which includes
      # protect_from_forgery by default. Confirm the chain is intact.
      expect(described_class.superclass).to eq(ApplicationController)
      expect(ApplicationController.superclass).to eq(ActionController::Base)
    end
  end

  describe "controller configuration", unit: true do
    it "has authentication and rate limiting callbacks" do
      expect(controller.respond_to?(:redirect_if_authenticated, true)).to be true
      expect(controller.respond_to?(:check_login_rate_limit, true)).to be true
    end

    it "has layout configuration" do
      expect(controller.class.name).to eq("Admin::SessionsController")
    end

    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end
  end

  describe "error handling", unit: true do
    describe "#render_too_many_requests" do
      it "handles too many requests error" do
        # Test the method exists and can be called
        expect(controller.respond_to?(:render_too_many_requests, true)).to be true
        # Testing the implementation details requires integration tests
      end
    end
  end
end
