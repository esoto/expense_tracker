require "rails_helper"

RSpec.describe Api::V1::CategorizationController, type: :controller, unit: true do
  let(:expense) { create(:expense) }
  let(:category) { create(:category) }
  let(:categorization_service) { double("Categorization::EnhancedCategorizationService") }

  before do
    # Skip authentication and other base controller concerns for unit tests
    controller.class.skip_before_action :authenticate_api_token, raise: false
    controller.class.skip_before_action :set_default_headers, raise: false
    controller.class.skip_before_action :log_request, raise: false
    
    # Mock the categorization service initialization
    categorization_module = Module.new
    stub_const("Categorization", categorization_module)
    enhanced_service_class = Class.new
    categorization_module.const_set("EnhancedCategorizationService", enhanced_service_class)
    allow(enhanced_service_class).to receive(:new).and_return(categorization_service)
  end

  describe "POST #suggest", unit: true do
    let(:valid_params) { { merchant_name: "Starbucks", description: "Coffee", amount: "15.50" } }
    let(:suggestions) { [{ category: category, confidence: 0.95 }] }

    before do
      allow(categorization_service).to receive(:suggest_categories).and_return(suggestions)
      allow(controller).to receive(:format_suggestions).and_return([])
    end

    it "calls categorization service with expense data" do
      expect(categorization_service).to receive(:suggest_categories)
      
      post :suggest, params: valid_params, format: :json
    end

    it "responds with success when given valid parameters" do
      post :suggest, params: valid_params, format: :json
      
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST #feedback", unit: true do
    let(:valid_params) do
      { feedback: { expense_id: expense.id, category_id: category.id, was_correct: true } }
    end

    before do
      allow(Expense).to receive(:find).and_return(expense)
      allow(Category).to receive(:find).and_return(category)
      allow(PatternFeedback).to receive(:record_feedback).and_return(double(improvement_suggestion: "Test"))
      allow(categorization_service).to receive(:learn_from_feedback)
      allow(controller).to receive(:serialize_feedback).and_return({})
    end

    it "processes feedback successfully" do
      expect(PatternFeedback).to receive(:record_feedback)
      expect(categorization_service).to receive(:learn_from_feedback)
      
      post :feedback, params: valid_params, format: :json
      
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST #batch_suggest", unit: true do
    let(:valid_params) do
      { expenses: [{ merchant_name: "Starbucks" }, { merchant_name: "Shell" }] }
    end
    let(:batch_results) { [] }

    before do
      allow(categorization_service).to receive(:categorize_batch).and_return(batch_results)
    end

    it "processes batch suggestions successfully" do
      expect(categorization_service).to receive(:categorize_batch)
      
      post :batch_suggest, params: valid_params, format: :json
      
      expect(response).to have_http_status(:success)
    end

    it "rejects large batches" do
      large_batch = { expenses: Array.new(101) { { merchant_name: "Test" } } }
      
      post :batch_suggest, params: large_batch, format: :json
      
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET #statistics", unit: true do
    before do
      # Mock all the statistics queries
      allow(CategorizationPattern).to receive(:count).and_return(100)
      allow(CategorizationPattern).to receive_message_chain(:active, :count).and_return(80)
      allow(CategorizationPattern).to receive_message_chain(:user_created, :count).and_return(20)
      allow(CategorizationPattern).to receive_message_chain(:high_confidence, :count).and_return(50)
      allow(CategorizationPattern).to receive_message_chain(:successful, :count).and_return(70)
      allow(CategorizationPattern).to receive_message_chain(:frequently_used, :count).and_return(30)
      allow(CategorizationPattern).to receive_message_chain(:active, :average).and_return(0.85)
      allow(CategorizationPattern).to receive_message_chain(:group, :count).and_return({})
      allow(PatternFeedback).to receive_message_chain(:where, :count).and_return(25)
      allow(PatternFeedback).to receive_message_chain(:group, :count).and_return({})
      allow(controller).to receive(:top_categorized_categories).and_return([])
    end

    it "returns statistics successfully" do
      get :statistics, format: :json
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(json_response["statistics"]).to be_a(Hash)
    end
  end

  describe "controller configuration", unit: true do
    it "inherits from Api::V1::BaseController" do
      expect(described_class.superclass).to eq(Api::V1::BaseController)
    end

    it "initializes categorization service before actions" do
      callbacks = controller.class._process_action_callbacks
      expect(callbacks.any? { |cb| cb.filter == :initialize_categorization_service }).to be_truthy
    end
  end

  describe "private methods", unit: true do
    describe "#build_expense_data" do
      it "creates expense struct with provided data" do
        params = { merchant_name: "Test", amount: "25.99" }
        
        result = controller.send(:build_expense_data, params)
        
        expect(result.merchant_name).to eq("Test")
        expect(result.amount).to eq(BigDecimal("25.99"))
      end
    end

    describe "#parse_date" do
      it "parses valid date strings" do
        result = controller.send(:parse_date, "2023-12-01")
        expect(result).to eq(Date.new(2023, 12, 1))
      end

      it "returns nil for invalid dates" do
        result = controller.send(:parse_date, "invalid")
        expect(result).to be_nil
      end
    end

    describe "#determine_feedback_type" do
      it "returns provided feedback type when present" do
        result = controller.send(:determine_feedback_type, { feedback_type: "custom" })
        expect(result).to eq("custom")
      end

      it "determines type based on was_correct value" do
        result = controller.send(:determine_feedback_type, { was_correct: true })
        expect(result).to eq("accepted")
      end
    end
  end
end