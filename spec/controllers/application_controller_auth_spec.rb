# frozen_string_literal: true

require "rails_helper"

# PR-12: ApplicationController now includes UserAuthentication (unified concern).
# Legacy Authentication concern deleted.
RSpec.describe ApplicationController, type: :controller, unit: true do
  controller do
    def index
      render plain: "OK"
    end
  end

  describe "Authentication inclusion", unit: true do
    it "includes the UserAuthentication concern" do
      expect(ApplicationController.ancestors).to include(UserAuthentication)
    end

    it "has require_authentication as a before_action" do
      callbacks = ApplicationController._process_action_callbacks.select { |c| c.kind == :before }
      filter_names = callbacks.map(&:filter)
      expect(filter_names).to include(:require_authentication)
    end
  end

  describe "unauthenticated access", unit: true do
    it "redirects to unified login page when not authenticated" do
      get :index
      expect(response).to redirect_to(login_path)
    end

    it "sets an alert flash message" do
      get :index
      expect(flash[:alert]).to eq("Please sign in to continue.")
    end

    it "stores the requested location for post-login redirect" do
      get :index
      expect(session[:return_to]).to eq("/anonymous")
    end
  end

  describe "authenticated access", unit: true do
    let!(:user) do
      create(:user, :admin,
        name: "Auth Test User",
        email: "auth-test-#{SecureRandom.hex(4)}@example.com",
        password: "SecurePassword123!"
      )
    end

    before do
      user.regenerate_session_token unless user.session_token.present?
      session[:user_session_token] = user.reload.session_token
      session[:user_session_expires_at] = 2.hours.from_now.iso8601
      allow(User).to receive(:find_by_valid_session)
        .with(user.session_token, extend: false)
        .and_return(user)
    end

    it "allows access with a valid session" do
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("OK")
    end

    it "exposes current_user helper (alias for current_app_user)" do
      get :index
      expect(controller.send(:current_user)).to eq(user)
    end

    it "exposes current_admin_user helper (legacy alias — same object)" do
      get :index
      expect(controller.send(:current_admin_user)).to eq(user)
    end

    it "reports user as signed in" do
      get :index
      expect(controller.send(:user_signed_in?)).to be true
    end
  end

  describe "controllers that skip authentication", unit: true do
    let(:controllers_with_skip) do
      [
        # PR-12: Admin::SessionsController deleted — no longer in this list.
        Api::BaseController,
        Api::WebhooksController,
        Api::HealthController,
        Api::QueueController,
        Api::MonitoringController,
        Api::SyncSessionsController,
        Api::V1::CategoriesController
      ]
    end

    it "each has skip_before_action for require_authentication" do
      controllers_with_skip.each do |controller_class|
        # skip_before_action removes the callback from the chain entirely
        active_filters = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :require_authentication
        }

        expect(active_filters).to be_empty,
          "Expected #{controller_class.name} to skip :require_authentication but it was found in the callback chain"
      end
    end
  end

  describe "controllers that require authentication", unit: true do
    let(:controllers_requiring_auth) do
      [
        ExpensesController,
        BudgetsController,
        CategoriesController,
        EmailAccountsController,
        SyncConflictsController,
        SyncSessionsController,
        BulkCategorizationsController,
        BulkCategorizationActionsController
      ]
    end

    it "each inherits require_authentication from ApplicationController" do
      controllers_requiring_auth.each do |controller_class|
        callbacks = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :require_authentication
        }

        expect(callbacks).not_to be_empty,
          "Expected #{controller_class.name} to have :require_authentication before_action but it was not found"
      end
    end
  end

  describe "controllers inheriting through Api::BaseController", unit: true do
    let(:api_v1_controllers) do
      [
        Api::V1::BaseController,
        Api::V1::CategorizationController,
        Api::V1::PatternsController
      ]
    end

    it "each skips require_authentication (inherited from Api::BaseController)" do
      api_v1_controllers.each do |controller_class|
        active_filters = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :require_authentication
        }

        expect(active_filters).to be_empty,
          "Expected #{controller_class.name} to skip :require_authentication but it was found in the callback chain"
      end
    end
  end

  describe "Admin::BaseController enforces admin role", unit: true do
    it "has require_authentication active (inherits from ApplicationController via UserAuthentication)" do
      # Admin::BaseController inherits require_authentication from ApplicationController.
      # Anonymous users get redirected to /login, then require_admin! redirects non-admin.
      active_auth = Admin::BaseController._process_action_callbacks.select { |c|
        c.kind == :before && c.filter == :require_authentication
      }
      expect(active_auth).not_to be_empty,
        "Admin::BaseController must have :require_authentication to gate anonymous access"
    end

    it "has require_admin! before_action" do
      active_admin = Admin::BaseController._process_action_callbacks.select { |c|
        c.kind == :before && c.filter == :require_admin!
      }
      expect(active_admin).not_to be_empty,
        "Admin::BaseController must have :require_admin! to gate non-admin access"
    end
  end
end
