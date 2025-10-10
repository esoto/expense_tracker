require "rails_helper"

RSpec.describe BulkCategorizationActionsController, type: :controller, unit: true do
  setup_authentication_mocks

  let(:current_user) { instance_double("User", id: "user_123") }
  let(:expense) { create(:expense, category: nil) }
  let(:category) { create(:category) }
  let(:bulk_operation) { create(:bulk_operation, expense_count: 1, user_id: current_user.id) }
  let(:bulk_categorization_service) { instance_double(Categorization::BulkServices::CategorizationService) }
  let(:undo_service) { instance_double(BulkCategorization::UndoService) }

  before do
    # Skip authentication for unit tests and mock current_user
    controller.class.skip_before_action :authenticate_user!, raise: false
    mock_user_authentication(current_user)

    # Mock Expense queries (since we no longer use user scoping)
    expenses_relation = instance_double("ActiveRecord::Relation")
    allow(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
    allow(expenses_relation).to receive(:where).and_return(expenses_relation)
    allow(expenses_relation).to receive(:count).and_return(1)
    allow(expenses_relation).to receive(:empty?).and_return(false)
    allow(expenses_relation).to receive(:limit).and_return(expenses_relation)
    allow(expenses_relation).to receive(:offset).and_return(expenses_relation)

    # Mock BulkOperation queries
    allow(BulkOperation).to receive(:find).and_return(bulk_operation)
  end

  describe "POST #categorize", unit: true do
    let(:expense_ids) { [ expense.id ] }
    let(:category_id) { category.id }
    let(:result) { { success: true, updated_count: 1, failed_count: 0, errors: [], undo_operation_id: 123 } }

    before do
      # Update mock to return the relation properly for specific IDs
      expenses_relation = instance_double("ActiveRecord::Relation")
      allow(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
      allow(expenses_relation).to receive(:where).with(id: expense_ids).and_return(expenses_relation)
      allow(expenses_relation).to receive(:count).and_return(1)
      allow(expenses_relation).to receive(:empty?).and_return(false)

      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:apply!).and_return(result)
    end

    it "creates service with correct parameters" do
      expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
        expenses: anything,
        category_id: category_id.to_s,
        user: current_user,
        options: {
          confidence_threshold: 0.7,
          apply_learning: false,
          update_patterns: false
        }
      )

      post :categorize, params: { expense_ids: expense_ids, category_id: category_id }, format: :json
    end

    it "calls apply! on the service" do
      expect(bulk_categorization_service).to receive(:apply!)
      post :categorize, params: { expense_ids: expense_ids, category_id: category_id }, format: :json
    end

    context "with custom options" do
      it "passes confidence threshold" do
        expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
          hash_including(options: hash_including(confidence_threshold: 0.9))
        )

        post :categorize, params: {
          expense_ids: expense_ids,
          category_id: category_id,
          confidence_threshold: "0.9"
        }, format: :json
      end

      it "passes apply_learning option" do
        expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
          hash_including(options: hash_including(apply_learning: true))
        )

        post :categorize, params: {
          expense_ids: expense_ids,
          category_id: category_id,
          apply_learning: "true"
        }, format: :json
      end
    end

    context "with JSON format" do
      it "renders result as JSON" do
        post :categorize, params: { expense_ids: expense_ids, category_id: category_id }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(result.deep_stringify_keys)
      end
    end

    context "with empty expense_ids" do
      it "returns error" do
        post :categorize, params: { expense_ids: [], category_id: category_id }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to eq("No expenses selected")
      end
    end
  end

  describe "POST #suggest", unit: true do
    let(:expense_ids) { [ expense.id ] }
    let(:suggestions) { { expense.id => { suggested_category: category, confidence: 0.9, reason: "Pattern match" } } }

    before do
      # Update mock to return the relation properly for specific IDs
      expenses_relation = Expense.includes(:category, :email_account)
      allow(expenses_relation).to receive(:where).with(id: expense_ids).and_return(expenses_relation)

      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:suggest_categories).and_return(suggestions)
    end

    it "creates service with correct parameters" do
      expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
        expenses: anything,
        user: current_user,
        options: {
          max_suggestions: 3,
          include_confidence: false
        }
      )

      post :suggest, params: { expense_ids: expense_ids }, format: :json
    end

    it "calls suggest_categories on the service" do
      expect(bulk_categorization_service).to receive(:suggest_categories)
      post :suggest, params: { expense_ids: expense_ids }, format: :json
    end

    context "with JSON format" do
      it "renders suggestions as JSON" do
        post :suggest, params: { expense_ids: expense_ids }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "POST #preview", unit: true do
    let(:expense_ids) { [ expense.id ] }
    let(:category_id) { category.id }
    let(:preview_data) {
      {
        expenses: [ { id: expense.id, will_change: true } ],
        summary: { total_count: 1, total_amount: 100 }
      }
    }

    before do
      # Update mock to return the relation properly for specific IDs
      expenses_relation = Expense.includes(:category, :email_account)
      allow(expenses_relation).to receive(:where).with(id: expense_ids).and_return(expenses_relation)

      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:preview).and_return(preview_data)
    end

    it "creates service with correct parameters" do
      expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
        expenses: anything,
        category_id: category_id.to_s,
        user: current_user
      )

      post :preview, params: { expense_ids: expense_ids, category_id: category_id }, format: :json
    end

    it "calls preview on the service" do
      expect(bulk_categorization_service).to receive(:preview)
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
    let(:expenses) { create_list(:expense, 3, category: nil) }
    let(:result) {
      {
        success: true,
        categorized_count: 3,
        failed_count: 0,
        total_processed: 3
      }
    }

    before do
      # Mock expense filtering with proper chaining for uncategorized expenses
      scope = double("ActiveRecord::Relation")
      allow(Expense).to receive(:includes).with(:category, :email_account).and_return(scope)
      allow(scope).to receive(:where).with(category: nil).and_return(scope)
      allow(scope).to receive(:where).and_return(scope)
      allow(scope).to receive(:limit).with(1000).and_return(expenses)

      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:auto_categorize!).and_return(result)
    end

    it "filters expenses based on parameters" do
      scope = double("ActiveRecord::Relation")
      allow(Expense).to receive(:includes).with(:category, :email_account).and_return(scope)
      allow(scope).to receive(:where).with(category: nil).and_return(scope)

      expect(scope).to receive(:where).with("transaction_date >= ?", Date.parse("2023-01-01")).ordered.and_return(scope)
      expect(scope).to receive(:where).with("transaction_date <= ?", Date.parse("2023-12-31")).ordered.and_return(scope)
      expect(scope).to receive(:limit).with(1000).and_return(expenses)

      post :auto_categorize, params: {
        date_from: "2023-01-01",
        date_to: "2023-12-31"
      }, format: :json
    end

    it "creates service with filtered expenses" do
      expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
        expenses: kind_of(Array),
        user: current_user,
        options: {
          dry_run: false,
          override_existing: false
        }
      )

      post :auto_categorize, format: :json
    end

    it "passes dry_run option correctly" do
      expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
        hash_including(options: hash_including(dry_run: true))
      )

      post :auto_categorize, params: { dry_run: "true" }, format: :json
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
    let(:expense_ids) { [ expense.id ] }
    let(:csv_data) { "ID,Description,Amount\n1,Test Expense,100.00" }
    let(:json_data) { [ { id: 1, description: "Test Expense", amount: 100.00 } ].to_json }

    before do
      # Update mock to return the relation properly for specific IDs
      expenses_relation = Expense.includes(:category, :email_account)
      allow(expenses_relation).to receive(:where).with(id: expense_ids).and_return(expenses_relation)

      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:export).with(format: :csv).and_return(csv_data)
      allow(bulk_categorization_service).to receive(:export).with(format: :json).and_return(json_data)
    end

    context "with CSV format" do
      it "creates service and exports as CSV" do
        expect(Categorization::BulkServices::CategorizationService).to receive(:new).with(
          expenses: anything,
          user: current_user
        )
        expect(bulk_categorization_service).to receive(:export).with(format: :csv)

        get :export, params: { expense_ids: expense_ids }, format: :csv
      end

      it "sends CSV data with correct headers" do
        get :export, params: { expense_ids: expense_ids }, format: :csv

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("text/csv")
        expect(response.body).to eq(csv_data)

        expected_date = Date.current.strftime('%Y%m%d')
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("bulk_categorizations_#{expected_date}.csv")
      end
    end

    context "with JSON format" do
      it "exports as JSON" do
        get :export, params: { expense_ids: expense_ids }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to eq(JSON.parse(json_data))
      end
    end
  end

  describe "POST #undo", unit: true do
    let(:operation_id) { bulk_operation.id }
    let(:success_result) {
      OpenStruct.new(
        success?: true,
        message: "Successfully undone categorization for 5 expenses",
        operation: bulk_operation
      )
    }
    let(:failure_result) {
      OpenStruct.new(
        success?: false,
        message: "Operation cannot be undone",
        operation: bulk_operation
      )
    }

    before do
      allow(BulkCategorization::UndoService).to receive(:new).and_return(undo_service)
    end

    context "with valid operation" do
      before do
        allow(undo_service).to receive(:call).and_return(success_result)
      end

      it "finds operation by ID" do
        expect(BulkOperation).to receive(:find).with(operation_id.to_s)
        post :undo, params: { id: operation_id }, format: :json
      end

      it "creates undo service with operation" do
        expect(BulkCategorization::UndoService).to receive(:new).with(
          bulk_operation: bulk_operation
        )
        post :undo, params: { id: operation_id }, format: :json
      end

      it "calls the undo service" do
        expect(undo_service).to receive(:call)
        post :undo, params: { id: operation_id }, format: :json
      end

      context "with successful undo" do
        it "renders success response" do
          post :undo, params: { id: operation_id }, format: :json

          expect(response).to have_http_status(:success)
          expect(response.content_type).to include("application/json")

          body = JSON.parse(response.body)
          expect(body["success"]).to be true
          expect(body["message"]).to eq("Successfully undone categorization for 5 expenses")
        end
      end
    end

    context "with failed undo" do
      before do
        allow(undo_service).to receive(:call).and_return(failure_result)
      end

      it "renders error response" do
        post :undo, params: { id: operation_id }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.content_type).to include("application/json")

        body = JSON.parse(response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to eq("Operation cannot be undone")
      end
    end

    context "when operation is not found" do
      before do
        allow(BulkOperation).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "returns not found error" do
        post :undo, params: { id: 99999 }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Operation not found")
      end
    end
  end

  describe "error handling", unit: true do
    context "when service raises a standard error" do
      before do
        # Mock the full Expense query chain that allows service creation but raises an error on apply!
        expenses_relation = instance_double("ActiveRecord::Relation")
        allow(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
        allow(expenses_relation).to receive(:where).with(id: [ expense.id ]).and_return(expenses_relation)
        allow(expenses_relation).to receive(:empty?).and_return(false)
        allow(expenses_relation).to receive(:count).and_return(1)  # Add count method

        # Allow service creation but make apply! fail
        error_service = instance_double(Categorization::BulkServices::CategorizationService)
        allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(error_service)
        allow(error_service).to receive(:apply!).and_raise(StandardError, "Service error")
      end

      it "handles the error gracefully" do
        post :categorize, params: { expense_ids: [ expense.id ], category_id: category.id }, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["error"]).to eq("Internal server error")
        expect(JSON.parse(response.body)["message"]).to eq("Service error")
      end
    end

    context "when record not found" do
      before do
        # Mock an empty relation
        empty_relation = instance_double("ActiveRecord::Relation")
        allow(empty_relation).to receive(:empty?).and_return(true)
        allow(empty_relation).to receive(:count).and_return(0)

        # Setup the mock chain without user scoping
        expenses_relation = instance_double("ActiveRecord::Relation")
        allow(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
        allow(expenses_relation).to receive(:where).with(id: [ 99999 ]).and_return(empty_relation)
      end

      it "returns not found error" do
        post :categorize, params: { expense_ids: [ 99999 ], category_id: category.id }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("No accessible expenses found")
      end
    end
  end

  describe "security", unit: true do
    it "requires authentication" do
      # Verify the Authentication concern is included in the controller
      controller_source = File.read(Rails.root.join('app/controllers/bulk_categorization_actions_controller.rb'))
      expect(controller_source).to include('include Authentication')
    end

    it "finds expenses by ID" do
      # Set up proper mock for successful categorization
      expenses_relation = instance_double("ActiveRecord::Relation")
      allow(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
      allow(expenses_relation).to receive(:where).with(id: [ expense.id ]).and_return(expenses_relation)
      allow(expenses_relation).to receive(:empty?).and_return(false)
      allow(expenses_relation).to receive(:count).and_return(1)  # Add count method
      allow(Categorization::BulkServices::CategorizationService).to receive(:new).and_return(bulk_categorization_service)
      allow(bulk_categorization_service).to receive(:apply!).and_return({ success: true })

      post :categorize, params: { expense_ids: [ expense.id ], category_id: category.id }, format: :json
      expect(response).to have_http_status(:ok)
    end

    it "finds bulk operations by ID" do
      allow(BulkCategorization::UndoService).to receive(:new).and_return(undo_service)
      allow(undo_service).to receive(:call).and_return(OpenStruct.new(success?: true, message: "Success", operation: bulk_operation))
      post :undo, params: { id: bulk_operation.id }, format: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
