# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Patterns Security", type: :request, integration: true do
  let(:category) { create(:category, name: "Test Category") }

  describe "Authentication", integration: true do
    let(:pattern) { create(:categorization_pattern, category: category) }

    context "without token" do
      it "returns 401 for index" do
        get "/api/v1/patterns"
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Missing API token")
      end

      it "returns 401 for show" do
        get "/api/v1/patterns/#{pattern.id}"
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 for create" do
        post "/api/v1/patterns", params: { pattern: {} }.to_json
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 for update" do
        patch "/api/v1/patterns/#{pattern.id}", params: { pattern: {} }.to_json
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 for delete" do
        delete "/api/v1/patterns/#{pattern.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid token" do
      let(:headers) { { "Authorization" => "Bearer invalid_token" } }

      it "returns 401 with invalid token message" do
        get "/api/v1/patterns", headers: headers
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired API token")
      end
    end

    context "with expired token" do
      let(:expired_token) do
        token = create(:api_token, expires_at: 1.day.from_now)
        token.update_column(:expires_at, 1.day.ago) # Bypass validation
        token
      end
      let(:headers) { { "Authorization" => "Bearer #{expired_token.token}" } }

      it "returns 401 for expired token" do
        get "/api/v1/patterns", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with inactive token" do
      let(:inactive_token) { create(:api_token, active: false) }
      let(:headers) { { "Authorization" => "Bearer #{inactive_token.token}" } }

      it "returns 401 for inactive token" do
        get "/api/v1/patterns", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "Token BCrypt verification", integration: true do
    let(:api_token) { create(:api_token) }
    let(:raw_token) { api_token.token }

    it "authenticates with correct token using BCrypt" do
      headers = { "Authorization" => "Bearer #{raw_token}" }
      get "/api/v1/patterns", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "rejects tampered tokens" do
      tampered_token = raw_token + "tampered"
      headers = { "Authorization" => "Bearer #{tampered_token}" }
      get "/api/v1/patterns", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "updates last_used_at on successful authentication" do
      expect {
        headers = { "Authorization" => "Bearer #{raw_token}" }
        get "/api/v1/patterns", headers: headers
      }.to change { api_token.reload.last_used_at }
    end
  end

  describe "SQL Injection Prevention", integration: true do
    let(:api_token) { create(:api_token) }
    let(:headers) { { "Authorization" => "Bearer #{api_token.token}" } }

    it "safely handles SQL injection attempts in pattern_type filter" do
      get "/api/v1/patterns",
          params: { pattern_type: "'; DROP TABLE categorization_patterns; --" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(CategorizationPattern.table_exists?).to be true
    end

    it "safely handles SQL injection attempts in sorting" do
      get "/api/v1/patterns",
          params: { sort_by: "created_at; DROP TABLE categorization_patterns; --" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(CategorizationPattern.table_exists?).to be true
    end
  end

  describe "Input Validation", integration: true do
    let(:api_token) { create(:api_token) }
    let(:headers) do
      {
        "Authorization" => "Bearer #{api_token.token}",
        "Content-Type" => "application/json"
      }
    end

    it "accepts special characters in pattern values" do
      params = {
        pattern: {
          pattern_type: "merchant",
          pattern_value: "<script>alert('XSS')</script>",
          category_id: category.id
        }
      }

      post "/api/v1/patterns", params: params.to_json, headers: headers

      expect(response.status).to eq(201)
      json = JSON.parse(response.body)
      # Pattern values are normalized to lowercase for consistent matching
      expect(json["pattern"]["pattern_value"]).to eq("<script>alert('xss')</script>")
    end
  end

  describe "Mass Assignment Protection", integration: true do
    let(:api_token) { create(:api_token) }
    let(:headers) do
      {
        "Authorization" => "Bearer #{api_token.token}",
        "Content-Type" => "application/json"
      }
    end

    it "prevents setting protected attributes" do
      params = {
        pattern: {
          pattern_type: "merchant",
          pattern_value: "test",
          category_id: category.id,
          id: 999999,
          created_at: 1.year.ago,
          updated_at: 1.year.ago,
          usage_count: 1000,
          success_count: 999
        }
      }

      post "/api/v1/patterns", params: params.to_json, headers: headers

      if response.status == 201
        json = JSON.parse(response.body)
        pattern = CategorizationPattern.find(json["pattern"]["id"])

        expect(pattern.id).not_to eq(999999)
        expect(pattern.usage_count).to eq(0)
        expect(pattern.success_count).to eq(0)
        expect(pattern.created_at).to be > 1.minute.ago
      end
    end
  end
end
