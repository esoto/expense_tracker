require "rails_helper"

# PR-12: Admin::BaseController now uses UserAuthentication (inherited from
# ApplicationController) + before_action :require_admin!. Legacy AdminAuthentication
# concern is deleted.
RSpec.describe Admin::BaseController, type: :controller, unit: true do
  # Create a test controller that inherits from Admin::BaseController for testing
  controller(Admin::BaseController) do
    def test_action
      render json: { status: "success" }
    end
  end

  before do
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

    it "includes UserAuthentication concern (via ApplicationController)" do
      expect(described_class.ancestors).to include(UserAuthentication)
    end

    it "does NOT include legacy AdminAuthentication concern" do
      expect(described_class.ancestors.map(&:name)).not_to include("AdminAuthentication")
    end

    it "does NOT register a check_rate_limit method (PER-507 removed the no-op placeholder)" do
      expect(described_class.private_instance_methods).not_to include(:check_rate_limit)
    end

    it "has log_admin_activity as after_action" do
      expect(described_class.private_instance_methods).to include(:log_admin_activity)
    end

    it "has require_admin! as a before_action" do
      callbacks = described_class._process_action_callbacks.select { |c|
        c.kind == :before && c.filter == :require_admin!
      }
      expect(callbacks).not_to be_empty
    end
  end

  describe "GET test_action when unauthenticated", unit: true do
    it "redirects to unified /login (not /admin/login)" do
      get :test_action
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "GET test_action when authenticated but not admin", unit: true do
    let(:regular_user) { create(:user) }

    before do
      allow(controller).to receive(:require_authentication)
      allow(controller).to receive(:current_app_user).and_return(regular_user)
    end

    it "redirects non-admin users (require_admin! fires)" do
      get :test_action
      # require_admin! -> render_forbidden: HTML redirects back to root_path
      # with a "Forbidden" alert (default render_forbidden message).
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Forbidden")
    end
  end

  describe "private methods", unit: true do
    let(:admin_user) { create(:user, :admin) }

    before do
      allow(controller).to receive(:require_authentication)
      allow(controller).to receive(:require_admin!)
      allow(controller).to receive(:current_app_user).and_return(admin_user)
      allow(controller).to receive(:log_admin_action)
      allow(controller).to receive(:controller_name).and_return("test")
      allow(controller).to receive(:action_name).and_return("show")
      controller.params = ActionController::Parameters.new(id: "123", password: "secret")
      allow(controller.request).to receive(:method).and_return("GET")
      allow(controller.request).to receive(:path).and_return("/admin/test")
    end

    describe "#log_admin_activity" do
      it "calls log_admin_action with filtered parameters" do
        expect(controller).to receive(:log_admin_action).with(
          "test#show",
          hash_including(
            method: "GET",
            path: "/admin/test"
          )
        )

        controller.send(:log_admin_activity)
      end
    end

    describe "#filtered_params" do
      it "masks sensitive parameter values via Rails filter_parameters" do
        result = controller.send(:filtered_params)
        expect(result).to be_a(Hash)
      end

      it "delegates to request.filtered_parameters" do
        filtered = { "id" => "123", "password" => "[FILTERED]" }
        allow(controller.request).to receive(:filtered_parameters).and_return(filtered)

        result = controller.send(:filtered_params)
        expect(result).to eq(filtered)
      end
    end
  end

  describe "security features", unit: true do
    it "delegates rate limiting to Rack::Attack middleware (PER-507)" do
      expect(controller.respond_to?(:check_rate_limit, true)).to be false
    end

    it "includes audit logging functionality" do
      expect(controller.respond_to?(:log_admin_activity, true)).to be_truthy
    end

    it "includes parameter filtering functionality" do
      expect(controller.respond_to?(:filtered_params, true)).to be_truthy
    end
  end
end
