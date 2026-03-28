# frozen_string_literal: true

require "rails_helper"

# PER-232: /api/health returns 503 when pattern_cache is empty on app start
RSpec.describe "Api::Health empty pattern cache", type: :request, unit: true do
  let(:health_check_double) { instance_double(Services::Categorization::Monitoring::HealthCheck) }

  before do
    allow(Services::Categorization::Monitoring::HealthCheck).to receive(:new).and_return(health_check_double)
  end

  describe "GET /api/health" do
    context "when pattern cache is empty (fresh app start)" do
      before do
        allow(health_check_double).to receive(:check_all).and_return({
          status: :degraded,
          healthy: true,
          timestamp: Time.current.iso8601,
          uptime_seconds: 5,
          checks: {
            database: { status: :healthy, connected: true },
            pattern_cache: { status: :degraded, entries: 0 }
          },
          errors: []
        })
        allow(health_check_double).to receive(:healthy?).and_return(true)
      end

      it "returns 200 even with empty pattern cache" do
        get "/api/health"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["healthy"]).to be true
      end

      it "reports degraded status in the response body" do
        get "/api/health"

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("degraded")
      end
    end

    context "when pattern cache has entries" do
      before do
        allow(health_check_double).to receive(:check_all).and_return({
          status: :healthy,
          healthy: true,
          timestamp: Time.current.iso8601,
          uptime_seconds: 300,
          checks: {
            database: { status: :healthy, connected: true },
            pattern_cache: { status: :healthy, entries: 50, hit_rate: 0.85 }
          },
          errors: []
        })
        allow(health_check_double).to receive(:healthy?).and_return(true)
      end

      it "returns 200 with healthy status" do
        get "/api/health"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["healthy"]).to be true
        expect(json["status"]).to eq("healthy")
      end
    end
  end

  describe "GET /api/health/ready" do
    context "when pattern cache is empty (fresh app start)" do
      before do
        allow(health_check_double).to receive(:check_all)
        allow(health_check_double).to receive(:ready?).and_return(true)
        allow(health_check_double).to receive(:checks).and_return({
          database: { status: :healthy, connected: true },
          pattern_cache: { status: :degraded, entries: 0 }
        })
      end

      it "returns 200 even with empty pattern cache" do
        get "/api/health/ready"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ready")
      end
    end
  end
end
