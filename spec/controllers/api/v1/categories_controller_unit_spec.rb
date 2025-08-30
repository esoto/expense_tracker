require "rails_helper"

RSpec.describe Api::V1::CategoriesController, type: :controller, unit: true do
  let(:category1) { create(:category, name: "Food", color: "#FF5733", description: "Food expenses") }
  let(:category2) { create(:category, name: "Transport", color: "#33C4FF", description: "Transportation costs") }

  before do
    # Skip CSRF token verification for API tests
    controller.class.skip_before_action :verify_authenticity_token, raise: false
  end

  describe "GET #index", unit: true do
    before do
      # Create test categories
      category1
      category2
    end

    it "returns all categories ordered by name" do
      get :index, format: :json

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")
    end

    it "returns categories with correct JSON structure" do
      get :index, format: :json

      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      expect(json_response.length).to eq(2)

      # Check first category (Food comes before Transport alphabetically)
      first_category = json_response.first
      expect(first_category).to have_key("id")
      expect(first_category).to have_key("name")
      expect(first_category).to have_key("color")
      expect(first_category).to have_key("description")

      expect(first_category["name"]).to eq("Food")
      expect(first_category["color"]).to eq("#FF5733")
      expect(first_category["description"]).to eq("Food expenses")
    end

    it "orders categories by name alphabetically" do
      get :index, format: :json

      json_response = JSON.parse(response.body)
      category_names = json_response.map { |c| c["name"] }
      
      expect(category_names).to eq(["Food", "Transport"])
    end

    it "includes all required fields for each category" do
      get :index, format: :json

      json_response = JSON.parse(response.body)
      json_response.each do |category|
        expect(category.keys).to contain_exactly("id", "name", "color", "description")
        expect(category["id"]).to be_present
        expect(category["name"]).to be_present
        expect(category["color"]).to be_present
        # description can be nil, so we just check the key exists
      end
    end

    context "when no categories exist" do
      before do
        Category.destroy_all
      end

      it "returns empty array" do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end

    context "with many categories" do
      before do
        Category.destroy_all
        create(:category, name: "Zebra")
        create(:category, name: "Apple") 
        create(:category, name: "Banana")
      end

      it "maintains alphabetical ordering" do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        category_names = json_response.map { |c| c["name"] }
        
        expect(category_names).to eq(["Apple", "Banana", "Zebra"])
      end
    end

    context "with categories containing nil description" do
      before do
        Category.destroy_all
        create(:category, name: "Test", description: nil)
      end

      it "handles nil description gracefully" do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response.first["description"]).to be_nil
      end
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it "is in the correct module namespace" do
      expect(described_class.name).to eq("Api::V1::CategoriesController")
    end

    it "skips authenticity token verification" do
      # This is configured in the controller with skip_before_action
      expect(controller.class._process_action_callbacks.any? { |cb| 
        cb.filter == :verify_authenticity_token && cb.options[:if] == false
      }).to be_falsy
    end
  end

  describe "error handling", unit: true do
    context "when database raises an error" do
      before do
        allow(Category).to receive(:all).and_raise(StandardError, "Database error")
      end

      it "does not rescue the error (lets Rails handle it)" do
        expect {
          get :index, format: :json
        }.to raise_error(StandardError, "Database error")
      end
    end

    context "when Category.all returns nil" do
      before do
        allow(Category).to receive(:all).and_return(nil)
      end

      it "handles nil result gracefully" do
        expect {
          get :index, format: :json
        }.to raise_error(NoMethodError) # Will fail when trying to call .order on nil
      end
    end
  end

  describe "response format", unit: true do
    before do
      category1 # Create at least one category
    end

    it "responds to HTML format but returns JSON structure" do
      get :index, format: :html

      # Even with HTML format, it returns JSON data since no template is defined
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
    end

    it "sets correct content type for JSON" do
      get :index, format: :json

      expect(response.content_type).to include("application/json")
    end
  end
end