# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CategorizationMetricsController, type: :controller, unit: true do
  # PR-12: Unified user.
  let(:admin_user) { create(:user, :admin, email: "admin_#{SecureRandom.hex(4)}@example.com") }

  before do
    allow(controller).to receive(:require_authentication).and_return(true)
    allow(controller).to receive(:check_session_expiry).and_return(true)
    allow(controller).to receive(:current_app_user).and_return(admin_user)
    allow(controller).to receive(:current_admin_user).and_return(admin_user)
  end

  describe "GET #index" do
    let(:overview_data) do
      { accuracy: 85.0, fallback_rate: 15.0, correction_rate: 10.0, api_spend: 0.05 }
    end
    let(:layer_data) do
      [
        { layer: "pattern", total: 80, correct: 70, corrected: 10,
          accuracy: 87.5, avg_confidence: 0.9, avg_time: 12.0 },
        { layer: "haiku", total: 20, correct: 15, corrected: 5,
          accuracy: 75.0, avg_confidence: 0.7, avg_time: 200.0 }
      ]
    end

    let(:budget_status_data) do
      { current_spend: 1.25, budget: 5.0, percentage: 25.0, status: "healthy" }
    end

    let(:problem_merchants_data) do
      [
        { merchant: "walmart", category_name: "Groceries", correction_count: 5,
          last_seen_at: 3.days.ago }
      ]
    end

    before do
      service = instance_double(Services::Categorization::Monitoring::MetricsDashboardService)
      allow(Services::Categorization::Monitoring::MetricsDashboardService).to receive(:new).and_return(service)
      allow(service).to receive(:overview).and_return(overview_data)
      allow(service).to receive(:api_budget_status).and_return(budget_status_data)
      allow(service).to receive(:layer_performance).and_return(layer_data)
      allow(service).to receive(:problem_merchants).and_return(problem_merchants_data)
    end

    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns overview data" do
      get :index
      expect(assigns(:overview)).to eq(overview_data)
    end

    it "assigns budget status data" do
      get :index
      expect(assigns(:budget_status)).to eq(budget_status_data)
    end

    it "assigns layer performance data" do
      get :index
      expect(assigns(:layer_performance)).to eq(layer_data)
    end

    it "assigns problem merchants data" do
      get :index
      expect(assigns(:problem_merchants)).to eq(problem_merchants_data)
    end

    it "renders the index template" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "authentication" do
    before do
      # PR-12: Undo the outer require_authentication stub so the real before_action fires.
      allow(controller).to receive(:require_authentication).and_call_original
      allow(controller).to receive(:current_app_user).and_return(nil)
      allow(controller).to receive(:current_admin_user).and_return(nil)
      allow(controller).to receive(:app_user_signed_in?).and_return(false)
    end

    it "redirects unauthenticated users to login" do
      get :index
      expect(response).to redirect_to(login_path)
    end
  end
end
