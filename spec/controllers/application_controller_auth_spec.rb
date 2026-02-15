# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller, unit: true do
  controller do
    def index
      render plain: "OK"
    end
  end

  describe "Authentication inclusion", unit: true do
    it "includes the Authentication concern" do
      expect(ApplicationController.ancestors).to include(Authentication)
    end

    it "has authenticate_user! as a before_action" do
      callbacks = ApplicationController._process_action_callbacks.select { |c| c.kind == :before }
      filter_names = callbacks.map(&:filter)
      expect(filter_names).to include(:authenticate_user!)
    end
  end

  describe "unauthenticated access", unit: true do
    it "redirects to login page when not authenticated" do
      get :index
      expect(response).to redirect_to(admin_login_path)
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
    let!(:admin_user) do
      AdminUser.create!(
        name: "Auth Test User",
        email: "auth-test@example.com",
        password: "SecurePassword123!",
        role: "admin"
      )
    end

    before do
      admin_user.regenerate_session_token unless admin_user.session_token.present?
      session[:admin_session_token] = admin_user.reload.session_token
      allow(AdminUser).to receive(:find_by_valid_session)
        .with(admin_user.session_token)
        .and_return(admin_user)
    end

    it "allows access with a valid session" do
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("OK")
    end

    it "exposes current_user helper" do
      get :index
      expect(controller.send(:current_user)).to eq(admin_user)
    end

    it "reports user as signed in" do
      get :index
      expect(controller.send(:user_signed_in?)).to be true
    end
  end

  describe "controllers that skip authentication", unit: true do
    let(:controllers_with_skip) do
      [
        Admin::SessionsController,
        Admin::BaseController,
        Api::BaseController,
        Api::WebhooksController,
        Api::HealthController,
        Api::ClientErrorsController,
        Api::QueueController,
        Api::MonitoringController,
        Api::SyncSessionsController,
        Api::V1::CategoriesController,
        UxMockupsController
      ]
    end

    it "each has skip_before_action for authenticate_user!" do
      controllers_with_skip.each do |controller_class|
        callbacks = controller_class._process_action_callbacks.select do |c|
          c.kind == :before && c.filter == :authenticate_user!
        end

        # If the callback exists, it should be skipped (no callback found means it was removed by skip)
        # OR the callback is present but the controller has its own auth
        # The most reliable check: the :authenticate_user! before_action should NOT be active
        has_active_auth = callbacks.any? { |c| !c.instance_variable_get(:@if)&.any? && !c.instance_variable_get(:@unless)&.any? }

        # Better approach: check that the filter chain does NOT include an active authenticate_user!
        active_filters = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :authenticate_user!
        }

        # skip_before_action removes the callback from the chain entirely
        expect(active_filters).to be_empty,
          "Expected #{controller_class.name} to skip :authenticate_user! but it was found in the callback chain"
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
        SyncPerformanceController,
        SyncSessionsController,
        BulkCategorizationsController,
        BulkCategorizationActionsController
      ]
    end

    it "each inherits authenticate_user! from ApplicationController" do
      controllers_requiring_auth.each do |controller_class|
        callbacks = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :authenticate_user!
        }

        expect(callbacks).not_to be_empty,
          "Expected #{controller_class.name} to have :authenticate_user! before_action but it was not found"
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

    it "each skips authenticate_user! (inherited from Api::BaseController)" do
      api_v1_controllers.each do |controller_class|
        active_filters = controller_class._process_action_callbacks.select { |c|
          c.kind == :before && c.filter == :authenticate_user!
        }

        expect(active_filters).to be_empty,
          "Expected #{controller_class.name} to skip :authenticate_user! but it was found in the callback chain"
      end
    end
  end

  describe "controllers inheriting through Admin::BaseController", unit: true do
    it "Analytics::PatternDashboardController skips authenticate_user!" do
      active_filters = Analytics::PatternDashboardController._process_action_callbacks.select { |c|
        c.kind == :before && c.filter == :authenticate_user!
      }

      expect(active_filters).to be_empty,
        "Expected Analytics::PatternDashboardController to skip :authenticate_user!"
    end
  end
end
