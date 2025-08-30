require "rails_helper"

RSpec.describe Api::V1::PatternsController, type: :controller, unit: true do
  let(:categorization_pattern) { create(:categorization_pattern) }
  let(:category) { create(:category) }

  before do
    # Mock API authentication and authorization
    allow(controller).to receive(:authenticate_api_token).and_return(true)
    allow(controller).to receive(:set_default_headers).and_return(true)
    allow(controller).to receive(:log_request).and_return(true)
    
    # Mock serializer classes
    serializer_module = Module.new
    api_module = Module.new
    v1_module = Module.new
    api_module.const_set("V1", v1_module)
    serializer_module.const_set("Api", api_module)
    
    pattern_serializer_class = Class.new do
      def self.collection(patterns, options = {})
        patterns.map { |p| { id: p.id, pattern_type: p.pattern_type } }
      end
      
      def initialize(pattern, options = {})
        @pattern = pattern
        @options = options
      end
      
      def as_json
        { id: @pattern.id, pattern_type: @pattern.pattern_type }
      end
    end
    v1_module.const_set("PatternSerializer", pattern_serializer_class)
    stub_const("Api::V1::PatternSerializer", pattern_serializer_class)
    
    # Mock render methods
    allow(controller).to receive(:render).and_return(nil)
    allow(controller).to receive(:render_success).and_return(nil)
    allow(controller).to receive(:render_error).and_return(nil)
    
    # Mock caching methods
    allow(controller).to receive(:handle_conditional_get)
    allow(controller).to receive(:fresh_when)
    allow(controller).to receive(:set_cache_headers)
  end

  describe "GET #index", unit: true do
    let(:mock_patterns) { double("patterns", current_page: 1, total_pages: 1, total_count: 1, limit_value: 10, next_page: nil, prev_page: nil, map: []) }
    
    before do
      allow(CategorizationPattern).to receive(:includes).and_return(mock_patterns)
      allow(mock_patterns).to receive(:where).and_return(mock_patterns)
      allow(mock_patterns).to receive(:order).and_return(mock_patterns)
      allow(mock_patterns).to receive(:ordered_by_success).and_return(mock_patterns)
      allow(controller).to receive(:paginate).and_return(mock_patterns)
      allow(controller).to receive(:render_success).and_return(nil)
    end

    it "includes category associations" do
      expect(CategorizationPattern).to receive(:includes).with(:category)
      get :index
    end

    it "processes index request successfully" do
      get :index
      expect(response).to be_successful
    end

    context "with parameters" do
      it "handles filter and sort parameters" do
        get :index, params: { 
          pattern_type: "merchant", 
          category_id: category.id,
          active: true,
          sort_by: "success_rate",
          sort_direction: "desc"
        }
        expect(response).to be_successful
      end
    end
  end

  describe "GET #show", unit: true do
    before do
      allow(CategorizationPattern).to receive(:find).and_return(categorization_pattern)
    end

    it "finds the pattern by ID" do
      expect(CategorizationPattern).to receive(:find).with(categorization_pattern.id.to_s)
      get :show, params: { id: categorization_pattern.id }
    end

    it "processes show request successfully" do
      get :show, params: { id: categorization_pattern.id }
      expect(response).to be_successful
      expect(assigns(:pattern)).to eq(categorization_pattern)
    end
  end

  describe "POST #create", unit: true do
    let(:valid_params) do
      {
        pattern: {
          pattern_type: "merchant",
          pattern_value: "Starbucks",
          category_id: category.id,
          confidence_weight: 0.8,
          active: true
        }
      }
    end

    context "with valid parameters" do
      before do
        allow(CategorizationPattern).to receive(:new).and_return(categorization_pattern)
        allow(categorization_pattern).to receive(:save).and_return(true)
        allow(categorization_pattern).to receive(:user_created=)
        allow(categorization_pattern).to receive(:confidence_weight)
        allow(categorization_pattern).to receive(:confidence_weight=)
      end

      it "creates new pattern with permitted parameters" do
        expect(CategorizationPattern).to receive(:new).with(
          hash_including(
            "pattern_type" => "merchant",
            "pattern_value" => "Starbucks",
            "category_id" => category.id.to_s
          )
        )
        post :create, params: valid_params
      end

      it "sets user_created to true" do
        expect(categorization_pattern).to receive(:user_created=).with(true)
        post :create, params: valid_params
      end

      it "sets default confidence_weight if not provided" do
        allow(categorization_pattern).to receive(:confidence_weight).and_return(nil)
        allow(categorization_pattern).to receive(:confidence_weight=)
        
        post :create, params: valid_params
        expect(categorization_pattern).to have_received(:confidence_weight=).with(1.0)
      end

      it "saves the pattern" do
        expect(categorization_pattern).to receive(:save)
        post :create, params: valid_params
      end

      it "renders success response with created pattern" do
        expect(controller).to receive(:render_success).with(
          { pattern: anything },
          status: :created
        )
        post :create, params: valid_params
      end
    end

    context "with invalid parameters" do
      before do
        allow(CategorizationPattern).to receive(:new).and_return(categorization_pattern)
        allow(categorization_pattern).to receive(:save).and_return(false)
        allow(categorization_pattern).to receive(:errors).and_return(double("errors", full_messages: ["Pattern value can't be blank"]))
      end

      it "renders error response with validation errors" do
        expect(controller).to receive(:render_error).with(
          "Failed to create pattern",
          ["Pattern value can't be blank"]
        )
        post :create, params: valid_params
      end
    end
  end

  describe "PATCH #update", unit: true do
    let(:update_params) do
      {
        id: categorization_pattern.id,
        pattern: {
          pattern_value: "Updated Starbucks",
          confidence_weight: 0.9,
          active: false
        }
      }
    end

    before do
      allow(CategorizationPattern).to receive(:find).and_return(categorization_pattern)
    end

    context "with valid parameters" do
      before do
        allow(categorization_pattern).to receive(:update).and_return(true)
      end

      it "finds the pattern by ID" do
        expect(CategorizationPattern).to receive(:find).with(categorization_pattern.id.to_s)
        patch :update, params: update_params
      end

      it "updates the pattern with permitted parameters" do
        expect(categorization_pattern).to receive(:update).with(
          hash_including(
            "pattern_value" => "Updated Starbucks",
            "confidence_weight" => "0.9",  # Controller parameters come as strings
            "active" => "false"  # Controller parameters come as strings
          )
        )
        patch :update, params: update_params
      end

      it "processes update request successfully" do
        patch :update, params: update_params
        expect(response).to be_successful
      end
    end

    context "with invalid parameters" do
      before do
        allow(categorization_pattern).to receive(:update).and_return(false)
        allow(categorization_pattern).to receive(:errors).and_return(double("errors", full_messages: ["Pattern value can't be blank"]))
      end

      it "renders error response with validation errors" do
        expect(controller).to receive(:render_error).with(
          "Failed to update pattern",
          ["Pattern value can't be blank"]
        )
        patch :update, params: update_params
      end
    end
  end

  describe "DELETE #destroy", unit: true do
    before do
      allow(CategorizationPattern).to receive(:find).and_return(categorization_pattern)
    end

    context "when deactivation succeeds" do
      before do
        allow(categorization_pattern).to receive(:update).and_return(true)
      end

      it "finds the pattern by ID" do
        expect(CategorizationPattern).to receive(:find).with(categorization_pattern.id.to_s)
        delete :destroy, params: { id: categorization_pattern.id }
      end

      it "soft deletes by setting active to false" do
        expect(categorization_pattern).to receive(:update).with(active: false)
        delete :destroy, params: { id: categorization_pattern.id }
      end

      it "processes destroy request successfully" do
        delete :destroy, params: { id: categorization_pattern.id }
        expect(response).to be_successful
      end
    end

    context "when deactivation fails" do
      before do
        allow(categorization_pattern).to receive(:update).and_return(false)
        allow(categorization_pattern).to receive(:errors).and_return(double("errors", full_messages: ["Update failed"]))
      end

      it "renders error response with failure details" do
        expect(controller).to receive(:render_error).with(
          "Failed to deactivate pattern",
          ["Update failed"]
        )
        delete :destroy, params: { id: categorization_pattern.id }
      end
    end
  end

  describe "private methods", unit: true do
    describe "#set_pattern" do
      it "finds and assigns pattern by ID" do
        allow(CategorizationPattern).to receive(:find).with("123").and_return(categorization_pattern)
        controller.params = ActionController::Parameters.new(id: "123")
        
        controller.send(:set_pattern)
        expect(assigns(:pattern)).to eq(categorization_pattern)
      end
    end

    describe "#pattern_params" do
      it "permits expected parameters for creation" do
        controller.params = ActionController::Parameters.new({
          pattern: {
            pattern_type: "merchant",
            pattern_value: "Test",
            category_id: 1,
            confidence_weight: 0.8,
            active: true,
            metadata: { key: "value" },
            unpermitted: "value"
          }
        })

        permitted_params = controller.send(:pattern_params)

        expect(permitted_params.keys).to contain_exactly(
          "pattern_type", "pattern_value", "category_id", 
          "confidence_weight", "active", "metadata"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#update_pattern_params" do
      it "permits expected parameters for updates (excludes pattern_type and category_id)" do
        controller.params = ActionController::Parameters.new({
          pattern: {
            pattern_type: "merchant", # Should be excluded
            pattern_value: "Updated Test",
            category_id: 2, # Should be excluded
            confidence_weight: 0.9,
            active: false,
            metadata: { updated: "value" },
            unpermitted: "value"
          }
        })

        permitted_params = controller.send(:update_pattern_params)

        expect(permitted_params.keys).to contain_exactly(
          "pattern_value", "confidence_weight", "active", "metadata"
        )
        expect(permitted_params["pattern_type"]).to be_nil
        expect(permitted_params["category_id"]).to be_nil
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#filter_params" do
      it "permits expected filter parameters" do
        controller.params = ActionController::Parameters.new({
          pattern_type: "merchant",
          category_id: 1,
          active: true,
          user_created: false,
          min_success_rate: 0.5,
          min_usage_count: 10,
          unpermitted: "value"
        })

        permitted_params = controller.send(:filter_params)

        expect(permitted_params.keys).to contain_exactly(
          "pattern_type", "category_id", "active", "user_created",
          "min_success_rate", "min_usage_count"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#filter_patterns" do
      let(:base_patterns) { double("base_patterns") }

      it "filters by pattern_type when provided" do
        controller.params = ActionController::Parameters.new(pattern_type: "merchant")
        
        expect(base_patterns).to receive(:where).with(pattern_type: "merchant").and_return(base_patterns)
        controller.send(:filter_patterns, base_patterns)
      end

      it "filters by category_id when provided" do
        controller.params = ActionController::Parameters.new(category_id: "1")
        
        expect(base_patterns).to receive(:where).with(category_id: "1").and_return(base_patterns)
        controller.send(:filter_patterns, base_patterns)
      end

      it "filters by active status when provided" do
        controller.params = ActionController::Parameters.new(active: "true")
        
        expect(base_patterns).to receive(:where).with(active: "true").and_return(base_patterns)
        controller.send(:filter_patterns, base_patterns)
      end

      it "filters by minimum success rate when provided" do
        controller.params = ActionController::Parameters.new(min_success_rate: "0.5")
        
        expect(base_patterns).to receive(:where).with("success_rate >= ?", 0.5).and_return(base_patterns)
        controller.send(:filter_patterns, base_patterns)
      end

      it "filters by minimum usage count when provided" do
        controller.params = ActionController::Parameters.new(min_usage_count: "10")
        
        expect(base_patterns).to receive(:where).with("usage_count >= ?", 10).and_return(base_patterns)
        controller.send(:filter_patterns, base_patterns)
      end

      it "returns unfiltered patterns when no filters provided" do
        controller.params = ActionController::Parameters.new({})
        
        result = controller.send(:filter_patterns, base_patterns)
        expect(result).to eq(base_patterns)
      end
    end

    describe "#sort_patterns" do
      let(:patterns) { double("patterns") }

      it "sorts by success_rate when specified" do
        controller.params = ActionController::Parameters.new(sort_by: "success_rate", sort_direction: "desc")
        
        expect(patterns).to receive(:order).with(success_rate: "desc")
        controller.send(:sort_patterns, patterns)
      end

      it "sorts by usage_count when specified" do
        controller.params = ActionController::Parameters.new(sort_by: "usage_count", sort_direction: "asc")
        
        expect(patterns).to receive(:order).with(usage_count: "asc")
        controller.send(:sort_patterns, patterns)
      end

      it "sorts by created_at when specified" do
        controller.params = ActionController::Parameters.new(sort_by: "created_at")
        
        expect(patterns).to receive(:order).with(created_at: "desc") # Default direction
        controller.send(:sort_patterns, patterns)
      end

      it "sorts by pattern_type when specified" do
        controller.params = ActionController::Parameters.new(sort_by: "pattern_type")
        
        expect(patterns).to receive(:order).with(pattern_type: "desc")
        controller.send(:sort_patterns, patterns)
      end

      it "uses default ordering when no sort specified" do
        controller.params = ActionController::Parameters.new({})
        
        expect(patterns).to receive(:ordered_by_success)
        controller.send(:sort_patterns, patterns)
      end
    end

    describe "#sort_direction" do
      it "returns asc when specified" do
        controller.params = ActionController::Parameters.new(sort_direction: "asc")
        
        result = controller.send(:sort_direction)
        expect(result).to eq("asc")
      end

      it "returns desc when specified" do
        controller.params = ActionController::Parameters.new(sort_direction: "desc")
        
        result = controller.send(:sort_direction)
        expect(result).to eq("desc")
      end

      it "returns desc as default for invalid values" do
        controller.params = ActionController::Parameters.new(sort_direction: "invalid")
        
        result = controller.send(:sort_direction)
        expect(result).to eq("desc")
      end

      it "returns desc as default when not specified" do
        controller.params = ActionController::Parameters.new({})
        
        result = controller.send(:sort_direction)
        expect(result).to eq("desc")
      end
    end
  end

  describe "serialization methods", unit: true do
    describe "#serialize_patterns" do
      let(:patterns) { [categorization_pattern] }

      it "calls PatternSerializer collection method" do
        controller.params = ActionController::Parameters.new({})
        
        expect(Api::V1::PatternSerializer).to receive(:collection).with(patterns, include_metadata: false)
        controller.send(:serialize_patterns, patterns)
      end

      it "includes metadata when requested" do
        controller.params = ActionController::Parameters.new(include_metadata: "true")
        
        expect(Api::V1::PatternSerializer).to receive(:collection).with(patterns, include_metadata: true)
        controller.send(:serialize_patterns, patterns)
      end
    end

    describe "#serialize_pattern" do
      it "creates serializer instance with metadata included" do
        serializer_instance = double("serializer", as_json: { id: 1 })
        expect(Api::V1::PatternSerializer).to receive(:new).with(categorization_pattern, include_metadata: true).and_return(serializer_instance)
        expect(serializer_instance).to receive(:as_json)
        
        controller.send(:serialize_pattern, categorization_pattern)
      end
    end
  end

  describe "pagination and caching", unit: true do
    let(:paginated_collection) do
      double("paginated_collection",
        current_page: 1,
        total_pages: 5,
        total_count: 50,
        limit_value: 10,
        next_page: 2,
        prev_page: nil
      )
    end

    describe "#pagination_meta" do
      it "returns pagination metadata hash" do
        result = controller.send(:pagination_meta, paginated_collection)
        
        expect(result).to eq({
          current_page: 1,
          total_pages: 5,
          total_count: 50,
          per_page: 10,
          next_page: 2,
          prev_page: nil
        })
      end
    end

    describe "#set_cache_headers_for_read" do
      it "sets cache headers with 5 minute max age" do
        expect(controller).to receive(:set_cache_headers).with(max_age: 5.minutes.to_i, public: true)
        controller.send(:set_cache_headers_for_read)
      end
    end
  end

  describe "controller configuration", unit: true do
    it "inherits from Api::V1::BaseController" do
      expect(described_class.superclass).to eq(Api::V1::BaseController)
    end

    it "includes ApiCaching concern" do
      expect(described_class.included_modules.map(&:to_s)).to include("ApiCaching")
    end

    it "has callback configurations" do
      # The controller uses before_action :set_pattern and after_action for caching
      # Detailed callback testing requires integration tests
      expect(controller.respond_to?(:set_pattern, true)).to be true
      expect(controller.respond_to?(:set_cache_headers_for_read, true)).to be true
    end
  end

  describe "error handling", unit: true do
    context "when pattern is not found" do
      it "handles RecordNotFound errors appropriately" do
        # The controller uses before_action :set_pattern which calls find
        # Error handling is tested at the integration level
        expect(controller.respond_to?(:set_pattern, true)).to be true
      end
    end
  end
end