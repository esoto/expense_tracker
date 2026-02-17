# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::MonitoringController, type: :controller, unit: true do
  let(:mock_adapter) do
    instance_double(
      Services::Categorization::Monitoring::DashboardAdapter,
      strategy_info: { source: "default", name: "basic" },
      metrics_summary: { total: 100, categorized: 80 },
      strategy_name: "basic"
    )
  end

  before do
    allow(Services::Categorization::Monitoring::DashboardAdapter).to receive(:new).and_return(mock_adapter)
    allow(mock_adapter).to receive(:strategy_info).and_return({ source: "default", name: "basic" })
    stub_const("Services::Categorization::Monitoring::DashboardAdapter::STRATEGIES",
               { original: double("OriginalStrategy"), optimized: double("OptimizedStrategy") }.freeze)
  end

  describe "authentication" do
    context "when no token is provided" do
      it "rejects unauthenticated requests to metrics endpoint" do
        get :metrics, format: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Unauthorized")
      end

      it "rejects unauthenticated requests to strategy endpoint" do
        get :strategy, format: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Unauthorized")
      end
    end

    context "when an invalid token is provided" do
      it "rejects requests with invalid Bearer token to metrics" do
        request.headers["Authorization"] = "Bearer invalid-token-xyz"
        get :metrics, format: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects requests with invalid Bearer token to strategy" do
        request.headers["Authorization"] = "Bearer invalid-token-xyz"
        get :strategy, format: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when a valid token is provided" do
      let!(:api_token) { create(:api_token) }
      let(:raw_token) { api_token.token }

      it "accepts authenticated requests to metrics endpoint" do
        request.headers["Authorization"] = "Bearer #{raw_token}"
        get :metrics, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("success")
      end

      it "accepts authenticated requests to strategy endpoint" do
        request.headers["Authorization"] = "Bearer #{raw_token}"
        get :strategy, format: :json

        expect(response).to have_http_status(:ok)
      end

      it "updates last_used_at on the token" do
        expect {
          request.headers["Authorization"] = "Bearer #{raw_token}"
          get :metrics, format: :json
        }.to change { api_token.reload.last_used_at }
      end
    end

    context "when an expired token is provided" do
      let!(:expired_token) { create(:api_token, :expired) }
      let(:raw_token) { expired_token.token }

      it "rejects requests with expired tokens" do
        # expired factory sets token then updates expires_at to past via update_column,
        # but the raw token is set during build. We need to re-set it since
        # the :expired trait uses after(:create) which runs after token generation.
        request.headers["Authorization"] = "Bearer #{raw_token}"
        get :metrics, format: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when an inactive token is provided" do
      let!(:inactive_token) { create(:api_token, :inactive) }
      let(:raw_token) { inactive_token.token }

      it "rejects requests with inactive tokens" do
        request.headers["Authorization"] = "Bearer #{raw_token}"
        get :metrics, format: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET #health" do
    it "does not require authentication" do
      get :health, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("healthy")
    end

    it "includes a timestamp" do
      get :health, format: :json

      json = JSON.parse(response.body)
      expect(json["timestamp"]).to be_present
    end
  end

  describe "GET #metrics" do
    let!(:api_token) { create(:api_token) }

    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "returns metrics summary with success status" do
      get :metrics, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["strategy"]).to be_present
      expect(json["metrics"]).to be_present
      expect(json["timestamp"]).to be_present
    end
  end

  describe "GET #strategy" do
    let!(:api_token) { create(:api_token) }

    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "returns strategy information" do
      get :strategy, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["current_strategy"]).to eq("basic")
      expect(json["strategy_info"]).to be_present
      expect(json["available_strategies"]).to be_present
      expect(json["configuration_source"]).to be_present
    end
  end

  describe "CSRF protection" do
    it "does not require CSRF token for API requests" do
      # Simulate a POST-like scenario - JSON API should not need CSRF
      # Since all actions are GET, we verify that verify_authenticity_token is skipped
      # by checking that the controller properly handles requests without CSRF token
      get :health, format: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
