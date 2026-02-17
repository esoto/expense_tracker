# frozen_string_literal: true

# Shared contexts for controller concern testing

RSpec.shared_context "controller with concern" do |concern|
  controller(ApplicationController) do
    include concern

    def index
      render json: { message: 'success' }
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      post 'index' => 'anonymous#index'
    end
  end
end

# Shared examples for testing controller concerns

# Tests authentication behavior
RSpec.shared_examples "authentication concern" do
  describe "authentication methods" do
    it { should respond_to(:current_user) }
    it { should respond_to(:user_signed_in?) }
    it { should respond_to(:authenticate_user!) }

    it "includes authentication helper methods" do
      expect(controller.class._helper_methods).to include(:current_user, :user_signed_in?)
    end
  end

  describe "#user_signed_in?" do
    context "when user is signed in" do
      let(:user) { build_stubbed(:admin_user) }

      before { allow(controller).to receive(:current_user).and_return(user) }

      it "returns true" do
        expect(controller.user_signed_in?).to be true
      end
    end

    context "when user is not signed in" do
      before { allow(controller).to receive(:current_user).and_return(nil) }

      it "returns false" do
        expect(controller.user_signed_in?).to be false
      end
    end
  end
end

# Tests authorization behavior
RSpec.shared_examples "authorization concern" do
  describe "authorization methods" do
    it { should respond_to(:authorize_sync_access!) }

    context "when access is allowed" do
      before { allow(controller).to receive(:sync_access_allowed?).and_return(true) }

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:authorize_sync_access!)
      end
    end

    context "when access is denied" do
      before { allow(controller).to receive(:sync_access_allowed?).and_return(false) }

      it "handles unauthorized access" do
        expect(controller).to receive(:respond_to)
        controller.send(:authorize_sync_access!)
      end
    end
  end
end

# Tests rate limiting behavior
RSpec.shared_examples "rate limiting concern" do |action_name|
  describe "rate limiting" do
    let(:config) { { limit: 5, period: 1.minute, by: :ip } }

    before do
      allow(controller.class).to receive(:rate_limits).and_return({ action_name => config })
      allow(controller).to receive(:request).and_return(double(remote_ip: "127.0.0.1"))
      allow(controller).to receive(:controller_name).and_return("test")
    end

    describe "#rate_limit_key" do
      it "generates correct key for IP-based limiting" do
        key = controller.send(:rate_limit_key, action_name, :ip)
        expect(key).to eq("rate_limit:test:#{action_name}:127.0.0.1")
      end

      it "generates correct key for user-based limiting" do
        user = build_stubbed(:admin_user, id: 123)
        allow(controller).to receive(:current_user).and_return(user)
        key = controller.send(:rate_limit_key, action_name, :user)
        expect(key).to eq("rate_limit:test:#{action_name}:123")
      end

      it "generates correct key for session-based limiting" do
        allow(controller).to receive(:session).and_return(double(id: "session123"))
        key = controller.send(:rate_limit_key, action_name, :session)
        expect(key).to eq("rate_limit:test:#{action_name}:session123")
      end
    end

    describe "#rate_limit_remaining" do
      it "calculates remaining requests correctly" do
        allow(Rails.cache).to receive(:read).and_return(2)
        remaining = controller.send(:rate_limit_remaining, action_name)
        expect(remaining).to eq(3)
      end

      it "returns 0 when limit exceeded" do
        allow(Rails.cache).to receive(:read).and_return(10)
        remaining = controller.send(:rate_limit_remaining, action_name)
        expect(remaining).to eq(0)
      end
    end
  end
end

# Tests caching behavior
RSpec.shared_examples "caching concern" do
  describe "caching methods" do
    let(:request) { double("request", get?: true, head?: false) }

    before { allow(controller).to receive(:request).and_return(request) }

    describe "#set_cache_headers" do
      it "sets public cache headers" do
        expect(controller).to receive(:expires_in).with(300.seconds, public: true, must_revalidate: true)
        controller.send(:set_cache_headers)
      end

      it "sets private cache headers when specified" do
        expect(controller).to receive(:expires_in).with(300.seconds, private: true, must_revalidate: true)
        controller.send(:set_cache_headers, public: false)
      end

      it "does not set headers for non-GET requests" do
        allow(request).to receive(:get?).and_return(false)
        expect(controller).not_to receive(:expires_in)
        controller.send(:set_cache_headers)
      end
    end

    describe "#disable_cache" do
      let(:headers) { {} }
      let(:response) { double("response", headers: headers) }

      before { allow(controller).to receive(:response).and_return(response) }

      it "sets no-cache headers" do
        controller.send(:disable_cache)
        expect(headers["Cache-Control"]).to eq("no-cache, no-store, must-revalidate")
        expect(headers["Pragma"]).to eq("no-cache")
        expect(headers["Expires"]).to eq("0")
      end
    end
  end
end

# Tests error handling behavior
RSpec.shared_examples "error handling concern" do
  describe "error handling" do
    describe "#handle_not_found" do
      it "handles ActiveRecord::RecordNotFound" do
        expect(controller).to receive(:respond_to)
        controller.send(:handle_not_found)
      end
    end

    describe "#handle_validation_error" do
      let(:record) { double("record", errors: double(full_messages: [ "Error message" ])) }
      let(:exception) { ActiveRecord::RecordInvalid.new(record) }

      it "handles validation errors" do
        expect(controller).to receive(:respond_to)
        controller.send(:handle_validation_error, exception)
      end
    end

    describe "#handle_unexpected_error" do
      let(:exception) { StandardError.new("Test error") }

      before do
        allow(exception).to receive(:backtrace).and_return([ "line1", "line2" ])
        allow(controller).to receive(:controller_name).and_return("test")
      end

      it "logs error and handles gracefully" do
        expect(Rails.logger).to receive(:error).twice
        expect(controller).to receive(:respond_to)
        controller.send(:handle_unexpected_error, exception)
      end
    end
  end
end

# Tests API configuration behavior
RSpec.shared_examples "api configuration concern" do
  describe "API configuration" do
    describe "#api_config" do
      let(:config) { controller.api_config }

      it "returns configuration hash with all sections" do
        expect(config).to have_key(:pagination)
        expect(config).to have_key(:cache)
        expect(config).to have_key(:rate_limit)
        expect(config).to have_key(:version)
      end

      it "includes correct pagination defaults" do
        expect(config[:pagination][:default_size]).to eq(25)
        expect(config[:pagination][:max_size]).to eq(100)
        expect(config[:pagination][:min_size]).to eq(1)
      end

      it "includes version information" do
        expect(config[:version][:current]).to eq("v1")
        expect(config[:version][:supported]).to include("v1")
      end
    end

    describe "#paginate_with_limits" do
      let(:collection) { double("collection") }
      let(:params) { {} }

      before { allow(controller).to receive(:params).and_return(params) }

      it "applies default page size when none specified" do
        expect(collection).to receive(:limit).with(25).and_return(collection)
        expect(collection).to receive(:offset).with(0)
        controller.send(:paginate_with_limits, collection)
      end

      it "respects maximum page size limit" do
        params[:per_page] = "200"
        expect(collection).to receive(:limit).with(100).and_return(collection)
        expect(collection).to receive(:offset).with(0)
        controller.send(:paginate_with_limits, collection)
      end

      it "enforces minimum page size" do
        params[:per_page] = "0"
        expect(collection).to receive(:limit).with(25).and_return(collection)
        expect(collection).to receive(:offset).with(0)
        controller.send(:paginate_with_limits, collection)
      end
    end
  end
end

# Tests security headers behavior
RSpec.shared_examples "security headers concern" do
  describe "security headers" do
    let(:headers) { {} }
    let(:response) { double("response", headers: headers) }

    before { allow(controller).to receive(:response).and_return(response) }

    describe "#set_security_headers" do
      it "sets all required security headers" do
        controller.send(:set_security_headers)

        expect(headers["X-Frame-Options"]).to eq("DENY")
        expect(headers["X-Content-Type-Options"]).to eq("nosniff")
        expect(headers["X-XSS-Protection"]).to eq("1; mode=block")
        expect(headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
        expect(headers["Content-Security-Policy"]).to be_present
      end
    end

    describe "#content_security_policy" do
      let(:csp) { controller.send(:content_security_policy) }

      it "includes default-src directive" do
        expect(csp).to include("default-src 'self'")
      end

      it "includes script-src directive" do
        expect(csp).to include("script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net")
      end

      it "includes frame-ancestors directive" do
        expect(csp).to include("frame-ancestors 'none'")
      end
    end
  end
end

# Tests audit logging behavior
RSpec.shared_examples "audit logging concern" do
  describe "audit logging" do
    describe "#log_admin_action" do
      let(:user) { build_stubbed(:admin_user, id: 123, email: "admin@example.com") }
      let(:request) { double("request", remote_ip: "127.0.0.1", user_agent: "Test Agent") }

      before do
        allow(controller).to receive(:current_admin_user).and_return(user)
        allow(controller).to receive(:request).and_return(request)
      end

      it "logs admin action with proper structure" do
        freeze_time do
          expected_log = {
            event: "admin_action",
            admin_user_id: 123,
            admin_email: "admin@example.com",
            action: "test_action",
            details: { key: "value" },
            ip_address: "127.0.0.1",
            user_agent: "Test Agent",
            timestamp: Time.current.iso8601
          }.to_json

          expect(Rails.logger).to receive(:info).with(expected_log)
          controller.send(:log_admin_action, "test_action", { key: "value" })
        end
      end
    end

    describe "#log_user_action" do
      let(:user) { build_stubbed(:admin_user, id: 456) }
      let(:request) { double("request", remote_ip: "192.168.1.1") }

      before do
        allow(controller).to receive(:current_user).and_return(user)
        allow(controller).to receive(:request).and_return(request)
        allow(controller).to receive(:controller_name).and_return("expenses")
        allow(controller).to receive(:action_name).and_return("create")
      end

      it "logs user action with proper structure" do
        freeze_time do
          expected_log = {
            event: "user_action",
            user_id: 456,
            action: "test_action",
            details: {},
            controller: "expenses",
            action_name: "create",
            ip_address: "192.168.1.1",
            timestamp: Time.current.iso8601
          }.to_json

          expect(Rails.logger).to receive(:info).with(expected_log)
          controller.send(:log_user_action, "test_action")
        end
      end
    end
  end
end
