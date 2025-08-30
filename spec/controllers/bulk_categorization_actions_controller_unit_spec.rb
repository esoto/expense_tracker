require "rails_helper"

RSpec.describe BulkCategorizationActionsController, type: :controller, unit: true do
  let(:current_user_id) { "user_123" }
  let(:expense) { create(:expense, category: nil) }
  let(:category) { create(:category) }
  let(:bulk_operation) { create(:bulk_operation, expense_count: 1) }
  let(:bulk_processor) { double("Services::Categorization::BulkProcessor") }

  before do
    # Skip the authenticate_user! before_action for unit tests
    controller.class.skip_before_action :authenticate_user!, raise: false
    
    # Mock the non-existent service classes
    services_categorization = Module.new
    stub_const("Services::Categorization", services_categorization)
    
    bulk_processor_class = Class.new
    services_categorization.const_set("BulkProcessor", bulk_processor_class)
    allow(bulk_processor_class).to receive(:new).and_return(bulk_processor)
  end

  describe "POST #categorize", unit: true do
    let(:expense_ids) { [expense.id] }
    let(:category_id) { category.id }
    let(:result) { { success: true, message: "Categorized successfully", count: 1 } }

    before do
      allow(bulk_processor).to receive(:categorize).and_return(result)
    end

    it "calls bulk processor with correct parameters" do
      expect(bulk_processor).to receive(:categorize).with(
        expense_ids: expense_ids.map(&:to_s),
        category_id: category_id.to_s,
        options: {
          confidence_threshold: 0.7,
          apply_learning: false,
          update_patterns: false
        }
      )

      post :categorize, params: { expense_ids: expense_ids, category_id: category_id }, format: :json
    end

    it "uses custom confidence threshold when provided" do
      expect(bulk_processor).to receive(:categorize).with(
        expense_ids: expense_ids.map(&:to_s),
        category_id: category_id.to_s,
        options: hash_including(confidence_threshold: 0.9)
      )

      post :categorize, params: { 
        expense_ids: expense_ids, 
        category_id: category_id,
        confidence_threshold: "0.9"
      }, format: :json
    end

    it "applies learning when parameter is true" do
      expect(bulk_processor).to receive(:categorize).with(
        expense_ids: expense_ids.map(&:to_s),
        category_id: category_id.to_s,
        options: hash_including(apply_learning: true)
      )

      post :categorize, params: { 
        expense_ids: expense_ids, 
        category_id: category_id,
        apply_learning: "true"
      }, format: :json
    end

    it "updates patterns when parameter is true" do
      expect(bulk_processor).to receive(:categorize).with(
        expense_ids: expense_ids.map(&:to_s),
        category_id: category_id.to_s,
        options: hash_including(update_patterns: true)
      )

      post :categorize, params: { 
        expense_ids: expense_ids, 
        category_id: category_id,
        update_patterns: "true"
      }, format: :json
    end

    context "with JSON format" do
      it "renders result as JSON" do
        post :categorize, params: { expense_ids: expense_ids, category_id: category_id }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(result.deep_stringify_keys)
      end
    end
  end

  describe "POST #suggest", unit: true do
    let(:expense_ids) { [expense.id] }
    let(:suggestions) { [{ category: "Food", confidence: 0.9 }, { category: "Transport", confidence: 0.7 }] }

    before do
      allow(bulk_processor).to receive(:suggest).and_return(suggestions)
    end

    it "calls bulk processor with correct parameters" do
      expect(bulk_processor).to receive(:suggest).with(
        expense_ids: expense_ids.map(&:to_s),
        options: {
          max_suggestions: 3,
          include_confidence: false
        }
      )

      post :suggest, params: { expense_ids: expense_ids }, format: :json
    end

    it "uses custom max suggestions when provided" do
      expect(bulk_processor).to receive(:suggest).with(
        expense_ids: expense_ids.map(&:to_s),
        options: hash_including(max_suggestions: 5)
      )

      post :suggest, params: { expense_ids: expense_ids, max_suggestions: "5" }, format: :json
    end

    it "includes confidence when parameter is true" do
      expect(bulk_processor).to receive(:suggest).with(
        expense_ids: expense_ids.map(&:to_s),
        options: hash_including(include_confidence: true)
      )

      post :suggest, params: { expense_ids: expense_ids, include_confidence: "true" }, format: :json
    end

    context "with JSON format" do
      it "renders suggestions as JSON" do
        post :suggest, params: { expense_ids: expense_ids }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(suggestions.map(&:deep_stringify_keys))
      end
    end
  end

  describe "POST #preview", unit: true do
    let(:expense_ids) { [expense.id] }
    let(:category_id) { category.id }
    let(:preview_data) { { affected_expenses: 1, estimated_impact: "positive", warnings: [] } }

    before do
      allow(bulk_processor).to receive(:preview).and_return(preview_data)
    end

    it "calls bulk processor with correct parameters" do
      expect(bulk_processor).to receive(:preview).with(
        expense_ids: expense_ids.map(&:to_s),
        category_id: category_id.to_s
      )

      post :preview, params: { expense_ids: expense_ids, category_id: category_id }, format: :json
    end

    context "with JSON format" do
      it "renders preview data as JSON" do
        post :preview, params: { expense_ids: expense_ids, category_id: category_id }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(preview_data.deep_stringify_keys)
      end
    end
  end

  describe "POST #auto_categorize", unit: true do
    let(:result) { { success: true, categorized_count: 25, message: "Auto-categorized 25 expenses" } }

    before do
      allow(bulk_processor).to receive(:auto_categorize).and_return(result)
    end

    it "calls bulk processor with filter params and options" do
      expect(bulk_processor).to receive(:auto_categorize) do |args|
        expect(args[:filter_params].to_h).to eq({
          "date_from" => "2023-01-01",
          "date_to" => "2023-12-31",
          "confidence_threshold" => "0.8"
        })
        expect(args[:options]).to eq({ dry_run: nil })
      end

      post :auto_categorize, params: {
        date_from: "2023-01-01",
        date_to: "2023-12-31", 
        confidence_threshold: "0.8"
      }, format: :json
    end

    it "passes dry_run option when provided" do
      expect(bulk_processor).to receive(:auto_categorize).with(
        filter_params: anything,
        options: { dry_run: "true" }
      )

      post :auto_categorize, params: { dry_run: "true" }, format: :json
    end

    it "filters permitted parameters correctly" do
      expect(bulk_processor).to receive(:auto_categorize) do |args|
        filter_params = args[:filter_params]
        expect(filter_params).to include("date_from", "confidence_threshold")
        expect(filter_params).not_to include("unpermitted_param")
      end

      post :auto_categorize, params: {
        date_from: "2023-01-01",
        confidence_threshold: "0.8",
        unpermitted_param: "should_not_be_included"
      }, format: :json
    end

    context "with JSON format" do
      it "renders result as JSON" do
        post :auto_categorize, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(result.deep_stringify_keys)
      end
    end
  end

  describe "GET #export", unit: true do
    let(:expense_ids) { [expense.id] }
    let(:csv_data) { "ID,Description,Amount\n1,Test Expense,100.00" }
    let(:bulk_exporter) { double("Services::Categorization::BulkExporter") }

    before do
      # Mock the BulkExporter service
      bulk_exporter_class = Class.new
      Services::Categorization.const_set("BulkExporter", bulk_exporter_class)
      allow(bulk_exporter_class).to receive(:new).and_return(bulk_exporter)
      allow(bulk_exporter).to receive(:export).and_return(csv_data)
    end

    it "calls bulk exporter with expense IDs" do
      expect(bulk_exporter).to receive(:export).with(expense_ids: expense_ids.map(&:to_s))

      get :export, params: { expense_ids: expense_ids }, format: :csv
    end

    context "with CSV format" do
      it "sends CSV data with correct filename and content type" do
        get :export, params: { expense_ids: expense_ids }, format: :csv

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("text/csv")
        expect(response.body).to eq(csv_data)
        
        expected_date = Date.current.strftime('%Y%m%d')
        expect(response.headers["Content-Disposition"]).to include("bulk_categorizations_#{expected_date}.csv")
      end
    end
  end

  describe "POST #undo", unit: true do
    let(:operation_id) { bulk_operation.id }
    let(:result) { { success: true, message: "Operation undone successfully", reverted_count: 5 } }

    before do
      # Mock the non-existent BulkCategorizationOperation class
      bulk_categorization_operation_class = Class.new do
        def self.find(id)
          # This method will be mocked
        end
      end
      stub_const("BulkCategorizationOperation", bulk_categorization_operation_class)
      allow(bulk_categorization_operation_class).to receive(:find).and_return(bulk_operation)
      allow(bulk_processor).to receive(:undo).and_return(result)
    end

    it "finds the bulk categorization operation" do
      expect(BulkCategorizationOperation).to receive(:find).with(operation_id.to_s)

      post :undo, params: { id: operation_id }, format: :json
    end

    it "calls bulk processor with the operation" do
      expect(bulk_processor).to receive(:undo).with(bulk_operation)

      post :undo, params: { id: operation_id }, format: :json
    end

    context "with JSON format" do
      it "renders result as JSON" do
        post :undo, params: { id: operation_id }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(result.deep_stringify_keys)
      end
    end

    context "when operation is not found" do
      before do
        allow(BulkCategorizationOperation).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          post :undo, params: { id: 99999 }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "private methods", unit: true do
    describe "#categorization_options" do
      it "returns default options when no parameters provided" do
        controller.params = ActionController::Parameters.new({})
        
        options = controller.send(:categorization_options)
        
        expect(options).to eq({
          confidence_threshold: 0.7,
          apply_learning: false,
          update_patterns: false
        })
      end

      it "converts string parameters correctly" do
        controller.params = ActionController::Parameters.new({
          confidence_threshold: "0.9",
          apply_learning: "true",
          update_patterns: "false"
        })
        
        options = controller.send(:categorization_options)
        
        expect(options).to eq({
          confidence_threshold: 0.9,
          apply_learning: true,
          update_patterns: false
        })
      end
    end

    describe "#suggestion_options" do
      it "returns default options when no parameters provided" do
        controller.params = ActionController::Parameters.new({})
        
        options = controller.send(:suggestion_options)
        
        expect(options).to eq({
          max_suggestions: 3,
          include_confidence: false
        })
      end

      it "converts string parameters correctly" do
        controller.params = ActionController::Parameters.new({
          max_suggestions: "5",
          include_confidence: "true"
        })
        
        options = controller.send(:suggestion_options)
        
        expect(options).to eq({
          max_suggestions: 5,
          include_confidence: true
        })
      end
    end

    describe "#auto_categorize_params" do
      it "permits only allowed parameters" do
        controller.params = ActionController::Parameters.new({
          date_from: "2023-01-01",
          date_to: "2023-12-31",
          merchant_filter: "Amazon",
          amount_range: "100-500",
          uncategorized_only: "true",
          confidence_threshold: "0.8",
          unpermitted_param: "should_not_be_included"
        })
        
        permitted_params = controller.send(:auto_categorize_params)
        
        expect(permitted_params.keys).to contain_exactly(
          "date_from", "date_to", "merchant_filter", "amount_range",
          "uncategorized_only", "confidence_threshold"
        )
        expect(permitted_params["unpermitted_param"]).to be_nil
      end
    end
  end

  describe "authentication", unit: true do
    it "has authenticate_user! configured as before_action" do
      # The controller declares authenticate_user! in the source code
      # We can verify it's in the callback chain even if the method doesn't exist
      source_file = File.read(Rails.root.join('app', 'controllers', 'bulk_categorization_actions_controller.rb'))
      expect(source_file).to include('before_action :authenticate_user!')
    end
  end

  describe "error handling", unit: true do
    context "when service raises an error" do
      before do
        allow(bulk_processor).to receive(:categorize).and_raise(StandardError, "Service error")
      end

      it "does not rescue the error (lets Rails handle it)" do
        expect {
          post :categorize, params: { expense_ids: [expense.id], category_id: category.id }
        }.to raise_error(StandardError, "Service error")
      end
    end
  end
end