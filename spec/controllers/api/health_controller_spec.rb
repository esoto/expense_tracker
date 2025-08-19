# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::HealthController, type: :controller, performance: true do
  before do
    # Create sufficient data for health checks to pass
    category = create(:category)
    # Create enough patterns to meet minimum threshold (10)
    create_list(:categorization_pattern, 15, category: category, active: true,
                success_rate: 0.8, usage_count: 5)
    create_list(:expense, 3, category: category)

    # Initialize pattern cache with some entries
    cache = Categorization::PatternCache.instance
    allow(cache).to receive(:stats).and_return({
      entries: 15,
      memory_bytes: 1024,
      hit_rate: 0.75,
      hits: 100,
      misses: 25,
      evictions: 0
    })
  end

  describe "GET #index", performance: true do
    it "returns health status" do
      get :index, format: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        "status",
        "healthy",
        "timestamp",
        "checks"
      )
    end

    it "returns 503 when unhealthy" do
      health_check = instance_double(Categorization::Monitoring::HealthCheck)
      allow(Categorization::Monitoring::HealthCheck).to receive(:new).and_return(health_check)
      allow(health_check).to receive(:check_all).and_return({
        status: :unhealthy,
        healthy: false,
        timestamp: Time.current.iso8601,
        checks: {},
        errors: [ "Database connection failed" ]
      })
      allow(health_check).to receive(:healthy?).and_return(false)

      get :index, format: :json

      expect(response).to have_http_status(:service_unavailable)

      json_response = JSON.parse(response.body)
      expect(json_response["healthy"]).to be false
    end
  end

  describe "GET #ready", performance: true do
    it "returns ready status when system is ready" do
      get :ready, format: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("ready")
    end

    it "returns 503 when not ready" do
      health_check = instance_double(Categorization::Monitoring::HealthCheck)
      allow(Categorization::Monitoring::HealthCheck).to receive(:new).and_return(health_check)
      allow(health_check).to receive(:check_all)
      allow(health_check).to receive(:ready?).and_return(false)
      allow(health_check).to receive(:checks).and_return({
        database: { status: :unhealthy }
      })

      get :ready, format: :json

      expect(response).to have_http_status(:service_unavailable)

      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("not_ready")
    end
  end

  describe "GET #live", performance: true do
    it "returns live status" do
      get :live, format: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("live")
    end

    it "returns 503 when not live" do
      health_check = instance_double(Categorization::Monitoring::HealthCheck)
      allow(Categorization::Monitoring::HealthCheck).to receive(:new).and_return(health_check)
      allow(health_check).to receive(:live?).and_return(false)

      get :live, format: :json

      expect(response).to have_http_status(:service_unavailable)

      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("dead")
    end
  end

  describe "GET #metrics", performance: true do
    before do
      # Create enough test data for health checks
      category = create(:category)
      create_list(:expense, 3, category: category)
      create_list(:expense, 2, category: nil)
      create_list(:categorization_pattern, 15, category: category)
    end

    it "returns metrics data" do
      get :metrics, format: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        "timestamp",
        "categorization",
        "patterns",
        "performance",
        "system"
      )

      expect(json_response["categorization"]).to include(
        "total_expenses",
        "categorized_expenses",
        "uncategorized_expenses",
        "success_rate"
      )

      expect(json_response["patterns"]).to include(
        "total",
        "active",
        "high_confidence",
        "recently_updated"
      )
    end

    it "handles errors gracefully" do
      allow_any_instance_of(Api::HealthController).to receive(:collect_metrics).and_raise(StandardError, "Test error")

      get :metrics, format: :json

      expect(response).to have_http_status(:internal_server_error)

      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to eq("Failed to collect metrics")
      expect(json_response["message"]).to eq("Test error")
    end
  end
end
