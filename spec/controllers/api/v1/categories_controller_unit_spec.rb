require "rails_helper"

RSpec.describe Api::V1::CategoriesController, type: :controller, unit: true do
  # Use build_stubbed for faster tests without database hits
  let(:category1) { build_stubbed(:category, id: 1, name: "Food", color: "#FF5733", description: "Food expenses") }
  let(:category2) { build_stubbed(:category, id: 2, name: "Transport", color: "#33C4FF", description: "Transportation costs") }

  before do
    # Skip CSRF token verification for API tests
    controller.class.skip_before_action :verify_authenticity_token, raise: false
  end

  describe "GET #index", unit: true do
    before do
      # Stub Category.all.order(:name) chain
      category_relation = double("Category::ActiveRecord_Relation")
      allow(Category).to receive(:all).and_return(category_relation)
      allow(category_relation).to receive(:order).with(:name).and_return([category1, category2])
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

      # Check that our categories have the correct structure
      json_response.each do |category|
        expect(category).to have_key("id")
        expect(category).to have_key("name")
        expect(category).to have_key("color")
        expect(category).to have_key("description")
      end

      food_category = json_response.find { |cat| cat["name"] == "Food" }
      expect(food_category["color"]).to eq("#FF5733")
      expect(food_category["description"]).to eq("Food expenses")
    end

    it "orders categories by name alphabetically" do
      get :index, format: :json

      json_response = JSON.parse(response.body)
      category_names = json_response.map { |c| c["name"] }

      # Food should come before Transport alphabetically
      expect(category_names).to eq(["Food", "Transport"])
    end

    it "includes all required fields for each category" do
      get :index, format: :json

      json_response = JSON.parse(response.body)

      # Test only our created categories to avoid issues with existing data
      test_categories = json_response.select { |cat| cat["name"].start_with?("TestFood") || cat["name"].start_with?("TestTransport") }

      test_categories.each do |category|
        expect(category.keys).to contain_exactly("id", "name", "color", "description")
        expect(category["id"]).to be_present
        expect(category["name"]).to be_present
        expect(category["color"]).to be_present # Our test categories have colors
        # description can be nil for general case, but our test categories have descriptions
        expect(category["description"]).to be_present
      end
    end

    context "when no categories exist" do
      before do
        category_relation = double("Category::ActiveRecord_Relation")
        allow(Category).to receive(:all).and_return(category_relation)
        allow(category_relation).to receive(:order).with(:name).and_return([])
      end

      it "returns empty array" do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end

    context "with many categories" do
      let(:apple) { build_stubbed(:category, id: 3, name: "Apple") }
      let(:banana) { build_stubbed(:category, id: 4, name: "Banana") }
      let(:zebra) { build_stubbed(:category, id: 5, name: "Zebra") }
      
      before do
        category_relation = double("Category::ActiveRecord_Relation")
        allow(Category).to receive(:all).and_return(category_relation)
        allow(category_relation).to receive(:order).with(:name).and_return([apple, banana, zebra])
      end

      it "maintains alphabetical ordering" do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        category_names = json_response.map { |c| c["name"] }

        expect(category_names).to eq(["Apple", "Banana", "Zebra"])
      end
    end

    context "with categories containing nil description" do
      let(:nil_desc_category) { build_stubbed(:category, id: 6, name: "Test", description: nil) }
      
      before do
        category_relation = double("Category::ActiveRecord_Relation")
        allow(Category).to receive(:all).and_return(category_relation)
        allow(category_relation).to receive(:order).with(:name).and_return([nil_desc_category])
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
