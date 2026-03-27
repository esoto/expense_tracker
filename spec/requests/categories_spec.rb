# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories API", type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }

  describe "GET /categories.json", :unit do
    context "when authenticated" do
      before { sign_in_admin(admin_user) }

      it "returns 200 with categories as JSON" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end

      it "returns all categories with expected attributes" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.length).to be >= 2

        first = json.find { |c| c["name"] == "Food" }
        expect(first).to include(
          "id" => category_food.id,
          "name" => "Food",
          "color" => "#FF6B6B"
        )
        expect(first).to have_key("parent_id")
      end

      it "returns categories ordered by name" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        json = JSON.parse(response.body)
        names = json.map { |c| c["name"] }
        expect(names).to eq(names.sort)
      end
    end

    context "when unauthenticated" do
      it "returns 401 for JSON requests instead of redirecting" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Authentication required")
      end

      it "returns 401 for XHR requests" do
        get categories_path(format: :json),
            headers: {
              "Accept" => "application/json",
              "X-Requested-With" => "XMLHttpRequest"
            }

        expect(response).to have_http_status(:unauthorized)
      end

      it "redirects to admin login for HTML requests" do
        get categories_path

        expect(response).to redirect_to(admin_login_path)
      end
    end
  end
end
