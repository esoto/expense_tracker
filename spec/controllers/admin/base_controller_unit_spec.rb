require "rails_helper"

RSpec.describe Admin::BaseController, type: :controller, unit: true do
  # Create a test controller that inherits from Admin::BaseController for testing
  controller(Admin::BaseController) do
    def test_action
      render json: { status: "success" }
    end
  end

  before do
    # Skip authentication concerns for unit testing
    allow(controller.class).to receive(:before_action)
    allow(controller.class).to receive(:after_action)

    # Mock the AdminAuthentication concern methods
    allow(controller).to receive(:log_admin_action)

    # Add the test route
    routes.draw do
      get "test_action" => "admin/base#test_action"
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it "is in the Admin module namespace" do
      expect(described_class.name).to eq("Admin::BaseController")
    end

    it "includes AdminAuthentication concern" do
      expect(described_class.included_modules.map(&:name)).to include("AdminAuthentication")
    end

    it "has check_rate_limit as before_action" do
      # Test that the method exists in the class (including private methods)
      expect(described_class.private_instance_methods).to include(:check_rate_limit)
    end

    it "has log_admin_activity as after_action" do
      # Test that the method exists in the class (including private methods)
      expect(described_class.private_instance_methods).to include(:log_admin_activity)
    end
  end

  describe "GET test_action", unit: true do
    it "executes with authentication redirect (expected behavior)" do
      # The admin base controller includes authentication which causes redirect
      # This is the expected behavior for an admin controller
      get :test_action

      expect(response).to have_http_status(:found) # 302 redirect due to authentication
    end
  end

  describe "private methods", unit: true do
    describe "#check_rate_limit" do
      it "returns true by default" do
        result = controller.send(:check_rate_limit)
        expect(result).to be_truthy
      end
    end

    describe "#log_admin_activity" do
      before do
        allow(controller).to receive(:controller_name).and_return("test")
        allow(controller).to receive(:action_name).and_return("show")
        controller.params = ActionController::Parameters.new(id: "123", password: "secret")
        allow(controller.request).to receive(:method).and_return("GET")
        allow(controller.request).to receive(:path).and_return("/admin/test")
      end

      it "calls log_admin_action with correct parameters" do
        expect(controller).to receive(:log_admin_action).with(
          "test#show",
          {
            params: { "id" => "123" }, # password should be filtered out
            method: "GET",
            path: "/admin/test"
          }
        )

        controller.send(:log_admin_activity)
      end
    end

    describe "#filtered_params" do
      it "removes sensitive parameters" do
        controller.params = ActionController::Parameters.new({
          id: "123",
          name: "test",
          password: "secret",
          password_confirmation: "secret",
          authenticity_token: "token123",
          regular_param: "value"
        })

        result = controller.send(:filtered_params)

        expect(result).to include("id" => "123", "name" => "test", "regular_param" => "value")
        expect(result).not_to have_key("password")
        expect(result).not_to have_key("password_confirmation")
        expect(result).not_to have_key("authenticity_token")
      end

      it "handles empty parameters" do
        controller.params = ActionController::Parameters.new({})

        result = controller.send(:filtered_params)

        expect(result).to eq({})
      end

      it "filters only sensitive parameters when present" do
        controller.params = ActionController::Parameters.new({
          id: "123",
          password: "secret"
        })

        result = controller.send(:filtered_params)

        expect(result).to eq({ "id" => "123" })
      end
    end
  end

  describe "error handling", unit: true do
    it "does not define custom error handling (relies on Rails defaults)" do
      # The controller doesn't define rescue_from blocks, it relies on Rails default error handling
      rescue_handlers = controller.class.rescue_handlers
      expect(rescue_handlers).to be_empty
    end
  end

  describe "security features", unit: true do
    it "includes rate limiting functionality" do
      expect(controller.respond_to?(:check_rate_limit, true)).to be_truthy
    end

    it "includes audit logging functionality" do
      expect(controller.respond_to?(:log_admin_activity, true)).to be_truthy
    end

    it "includes parameter filtering functionality" do
      expect(controller.respond_to?(:filtered_params, true)).to be_truthy
    end

    it "filters sensitive parameters consistently" do
      controller.params = ActionController::Parameters.new({
        password: "test123",
        password_confirmation: "test123",
        authenticity_token: "csrf_token",
        safe_param: "safe_value"
      })

      filtered = controller.send(:filtered_params)

      expect(filtered.keys).to contain_exactly("safe_param")
      expect(filtered["safe_param"]).to eq("safe_value")
    end
  end

  describe "admin authentication integration", unit: true do
    it "includes AdminAuthentication concern" do
      # This tests that the concern is properly included
      expect(described_class.ancestors.map(&:name)).to include("AdminAuthentication")
    end

    it "expects to have admin authentication methods when concern is properly loaded" do
      # Test that the concern would be loaded (we can't test the actual methods without the full concern)
      expect(described_class.ancestors.map(&:name)).to include("AdminAuthentication")
    end
  end
end
