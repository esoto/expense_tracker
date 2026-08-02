# frozen_string_literal: true

require "rails_helper"

# Session-based authorization contract for Api::QueueController.
#
# Replaces the old ApiToken / X-Admin-Key / dev-env-bypass authentication
# (security-audit follow-up #1: "any ApiToken = queue admin"). Read-only
# endpoints (status, metrics, health) require any authenticated session
# user; state-changing endpoints (pause, resume, retry_job, clear_job,
# retry_all_failed) require an admin session. This is a JSON API consumed
# by fetch() — auth/authz failures render JSON, never a login redirect.
RSpec.describe "Api::Queue authorization", type: :request, unit: true do
  let(:json_headers) { { "Accept" => "application/json" } }

  before do
    allow(Services::QueueMonitor).to receive(:queue_status).and_return({
      pending: 1, processing: 0, completed: 0, failed: 0,
      health_status: "healthy",
      queue_depth_by_name: {}, paused_queues: [],
      active_jobs: [], failed_jobs: [],
      processing_rate: 0.0, estimated_completion_time: nil,
      worker_status: { healthy: 1, total: 1 }
    })
    allow(Services::QueueMonitor).to receive(:pause_queue).and_return(true)
    allow(Services::QueueMonitor).to receive(:paused_queues).and_return([])
  end

  describe "unauthenticated" do
    it "returns JSON 401 for status (no redirect)" do
      get "/api/queue/status", headers: json_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
      json = JSON.parse(response.body)
      expect(json["error"]).to be_present
    end

    it "returns JSON 401 for pause (no redirect)" do
      post "/api/queue/pause", headers: json_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "signed-in non-admin user" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "allows status" do
      get "/api/queue/status", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "rejects pause with JSON 403 and does not touch queue state" do
      expect(Services::QueueMonitor).not_to receive(:pause_queue)

      post "/api/queue/pause", headers: json_headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["success"]).to be false
      expect(json["error"]).to be_present
    end

    it "rejects retry_job with JSON 403" do
      post "/api/queue/jobs/123/retry", headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["success"]).to be false
    end

    it "rejects clear_job with JSON 403" do
      post "/api/queue/jobs/123/clear", headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["success"]).to be false
    end

    it "rejects retry_all_failed with JSON 403" do
      post "/api/queue/retry_all_failed", headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["success"]).to be false
    end
  end

  describe "admin user" do
    let(:admin) { create(:user, :admin) }

    before { sign_in_as(admin) }

    it "allows status" do
      get "/api/queue/status", headers: json_headers

      expect(response).to have_http_status(:ok)
    end

    it "allows pause and calls Services::QueueMonitor" do
      expect(Services::QueueMonitor).to receive(:pause_queue).with(nil).and_return(true)

      post "/api/queue/pause", headers: json_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end
  end

  describe "regression: ApiToken bearer header alone is not accepted (audit finding closed)" do
    let(:admin_user) { create(:user, :admin) }
    let(:api_token) { create(:api_token, :with_known_token, user: admin_user) }

    it "returns 401 on pause with only a valid Bearer token, no session" do
      post "/api/queue/pause",
        headers: json_headers.merge("Authorization" => "Bearer #{api_token.token}")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "CSRF protection" do
    it "rejects a mutation without a valid authenticity token when forgery protection is enforced" do
      admin = create(:user, :admin)
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      begin
        sign_in_as(admin)

        post "/api/queue/pause", headers: json_headers

        expect([ 401, 403, 422 ]).to include(response.status)
      ensure
        ActionController::Base.allow_forgery_protection = original
      end
    end
  end
end
