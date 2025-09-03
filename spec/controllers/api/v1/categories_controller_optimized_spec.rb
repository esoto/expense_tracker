require "rails_helper"

RSpec.describe Api::V1::CategoriesController, type: :controller, unit: true do
  # OPTIMIZATION 1: Use build_stubbed instead of create for faster tests
  let(:category1) { build_stubbed(:category, id: 1, name: "TestFood", color: "#FF5733", description: "Food expenses") }
  let(:category2) { build_stubbed(:category, id: 2, name: "TestTransport", color: "#33C4FF", description: "Transportation costs") }

  # OPTIMIZATION 2: Remove transaction rollback - use database_cleaner strategy instead
  # The around(:each) block with ActiveRecord::Rollback is removed

  before do
    # Skip CSRF token verification for API tests
    controller.class.skip_before_action :verify_authenticity_token, raise: false
  end

  describe "GET #index", unit: true do
    # OPTIMIZATION 3: Use shared examples to reduce redundancy
    shared_examples "returns categories response" do
      it "returns success status and JSON content type" do
        get :index, format: :json
        
        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
      end
    end

    context "with stubbed categories" do
      before do
        # OPTIMIZATION 4: Stub the database query instead of creating records
        allow(Category).to receive(:all).and_return(
          Category.where(id: [category1.id, category2.id])
        )
        allow(Category).to receive_message_chain(:all, :order).and_return([category1, category2])
      end

      include_examples "returns categories response"

      it "returns categories with correct structure and ordering" do
        get :index, format: :json
        json_response = JSON.parse(response.body)
        
        expect(json_response).to be_an(Array)
        expect(json_response.length).to eq(2)
        
        # Verify structure and ordering in one pass
        expect(json_response[0]).to include(
          "id" => 1,
          "name" => "TestFood",
          "color" => "#FF5733",
          "description" => "Food expenses"
        )
        expect(json_response[1]).to include(
          "id" => 2,
          "name" => "TestTransport",
          "color" => "#33C4FF",
          "description" => "Transportation costs"
        )
      end
    end

    context "when no categories exist" do
      before do
        # OPTIMIZATION 5: Stub empty result instead of destroying records
        allow(Category).to receive_message_chain(:all, :order).and_return([])
      end

      it "returns empty array" do
        get :index, format: :json
        expect(JSON.parse(response.body)).to eq([])
      end
    end

    context "with alphabetical ordering" do
      let(:zebra) { build_stubbed(:category, id: 3, name: "Zebra") }
      let(:apple) { build_stubbed(:category, id: 4, name: "Apple") }
      let(:banana) { build_stubbed(:category, id: 5, name: "Banana") }

      before do
        allow(Category).to receive_message_chain(:all, :order)
          .with(:name)
          .and_return([apple, banana, zebra])
      end

      it "maintains alphabetical ordering" do
        get :index, format: :json
        
        json_response = JSON.parse(response.body)
        category_names = json_response.map { |c| c["name"] }
        
        expect(category_names).to eq(["Apple", "Banana", "Zebra"])
      end
    end

    context "with nil description" do
      let(:nil_category) { build_stubbed(:category, id: 6, name: "Test", description: nil) }

      before do
        allow(Category).to receive_message_chain(:all, :order).and_return([nil_category])
      end

      it "handles nil description gracefully" do
        get :index, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.first["description"]).to be_nil
      end
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "verifies controller setup" do
      expect(described_class.superclass).to eq(ApplicationController)
      expect(described_class.name).to eq("Api::V1::CategoriesController")
    end
  end

  describe "error handling", unit: true do
    context "when database raises an error" do
      before do
        allow(Category).to receive(:all).and_raise(StandardError, "Database error")
      end

      it "does not rescue the error" do
        expect {
          get :index, format: :json
        }.to raise_error(StandardError, "Database error")
      end
    end

    context "when Category.all returns nil" do
      before do
        allow(Category).to receive(:all).and_return(nil)
      end

      it "raises NoMethodError" do
        expect {
          get :index, format: :json
        }.to raise_error(NoMethodError)
      end
    end
  end

  describe "response format", unit: true do
    before do
      allow(Category).to receive_message_chain(:all, :order).and_return([category1])
    end

    it "responds to multiple formats" do
      get :index, format: :html
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      
      get :index, format: :json
      expect(response.content_type).to include("application/json")
    end
  end
end