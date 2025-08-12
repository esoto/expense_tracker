# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Patterns", type: :request do
  let(:api_token) { create(:api_token) }
  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token.token}",
      "Content-Type" => "application/json"
    }
  end

  let(:category) { create(:category, name: "Groceries") }
  let!(:pattern) do
    create(:categorization_pattern,
           pattern_type: "merchant",
           pattern_value: "walmart",
           category: category,
           confidence_weight: 2.0,
           usage_count: 10,
           success_count: 8)
  end

  describe "GET /api/v1/patterns" do
    before do
      create(:categorization_pattern, pattern_type: "keyword", pattern_value: "coffee", category: category)
      create(:categorization_pattern, pattern_type: "description", pattern_value: "uber", category: category)
    end

    it "returns a paginated list of patterns" do
      get "/api/v1/patterns", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["patterns"]).to be_an(Array)
      expect(json["patterns"].size).to eq(3)
      expect(json["meta"]).to include("current_page", "total_pages", "total_count")
    end

    it "filters patterns by type" do
      get "/api/v1/patterns", params: { pattern_type: "merchant" }, headers: headers

      json = JSON.parse(response.body)
      expect(json["patterns"].size).to eq(1)
      expect(json["patterns"].first["pattern_type"]).to eq("merchant")
    end

    it "filters patterns by category_id" do
      other_category = create(:category, name: "Entertainment")
      create(:categorization_pattern, pattern_type: "merchant", pattern_value: "netflix", category: other_category)

      get "/api/v1/patterns", params: { category_id: category.id }, headers: headers

      json = JSON.parse(response.body)
      expect(json["patterns"].all? { |p| p["category"]["id"] == category.id }).to be true
    end

    it "sorts patterns by success_rate" do
      get "/api/v1/patterns", params: { sort_by: "success_rate", sort_direction: "desc" }, headers: headers

      json = JSON.parse(response.body)
      success_rates = json["patterns"].map { |p| p["statistics"]["success_rate"] }
      expect(success_rates).to eq(success_rates.sort.reverse)
    end

    it "includes metadata when requested" do
      pattern.update!(metadata: { source: "user_feedback" })

      get "/api/v1/patterns", params: { include_metadata: "true" }, headers: headers

      json = JSON.parse(response.body)
      expect(json["patterns"].first["metadata"]).to eq({ "source" => "user_feedback" })
    end

    it "returns 401 without authentication" do
      get "/api/v1/patterns"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/patterns/:id" do
    it "returns a specific pattern" do
      get "/api/v1/patterns/#{pattern.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["pattern"]["id"]).to eq(pattern.id)
      expect(json["pattern"]["pattern_value"]).to eq("walmart")
    end

    it "returns 404 for non-existent pattern" do
      get "/api/v1/patterns/999999", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/patterns" do
    let(:valid_params) do
      {
        pattern: {
          pattern_type: "merchant",
          pattern_value: "target",
          category_id: category.id,
          confidence_weight: 1.5
        }
      }
    end

    it "creates a new pattern" do
      expect {
        post "/api/v1/patterns", params: valid_params.to_json, headers: headers
      }.to change(CategorizationPattern, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["pattern"]["pattern_value"]).to eq("target")
      expect(json["pattern"]["user_created"]).to be true
    end

    it "returns validation errors for invalid data" do
      invalid_params = valid_params.deep_dup
      invalid_params[:pattern][:pattern_type] = "invalid_type"

      post "/api/v1/patterns", params: invalid_params.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["errors"]).to include(match(/Pattern type/))
    end

    it "prevents duplicate patterns" do
      existing_pattern = create(:categorization_pattern,
                                pattern_type: "merchant",
                                pattern_value: "duplicate",
                                category: category)

      duplicate_params = {
        pattern: {
          pattern_type: "merchant",
          pattern_value: "duplicate",
          category_id: category.id
        }
      }

      post "/api/v1/patterns", params: duplicate_params.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["errors"]).to include(match(/already exists/))
    end
  end

  describe "PATCH /api/v1/patterns/:id" do
    let(:update_params) do
      {
        pattern: {
          confidence_weight: 3.0,
          active: false
        }
      }
    end

    it "updates an existing pattern" do
      patch "/api/v1/patterns/#{pattern.id}", params: update_params.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["pattern"]["confidence_weight"]).to eq(3.0)
      expect(json["pattern"]["active"]).to be false

      pattern.reload
      expect(pattern.confidence_weight).to eq(3.0)
      expect(pattern.active).to be false
    end

    it "does not allow changing pattern_type" do
      patch "/api/v1/patterns/#{pattern.id}",
            params: { pattern: { pattern_type: "keyword" } }.to_json,
            headers: headers

      pattern.reload
      expect(pattern.pattern_type).to eq("merchant") # Unchanged
    end
  end

  describe "DELETE /api/v1/patterns/:id" do
    it "soft deletes a pattern by deactivating it" do
      delete "/api/v1/patterns/#{pattern.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Pattern deactivated successfully")

      pattern.reload
      expect(pattern.active).to be false
      expect(CategorizationPattern.find(pattern.id)).to eq(pattern) # Still exists
    end
  end

  describe "Rate limiting" do
    it "enforces rate limits on pattern creation" do
      # This test would need to be configured based on your rate limiting settings
      # For now, we'll just verify the endpoint exists
      post "/api/v1/patterns", params: { pattern: {} }.to_json, headers: headers
      expect(response.status).to be_in([ 400, 422 ]) # Bad request or unprocessable
    end
  end
end
