require "rails_helper"

RSpec.describe ExpensesController, type: :controller, unit: true do
  let(:email_account) { create(:email_account) }
  let(:expense) { create(:expense, email_account: email_account) }
  let(:category) { create(:category) }
  let(:current_user_id) { "user_123" }

  before do
    # Use instance-level mocking (not class-level skip_before_action which pollutes other specs)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:authorize_expense!).and_return(true)
    allow(controller).to receive(:authorize_bulk_operation!).and_return(true)

    # Mock current user methods
    allow(controller).to receive(:current_user_for_bulk_operations).and_return(current_user_id)
    allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))
    allow(controller).to receive(:can_modify_expense?).and_return(true)
  end

  describe "GET #index", unit: true do
    let(:filter_service) { double("Services::ExpenseFilterService") }
    let(:service_result) do
      double("ServiceResult", {
        success?: true,
        expenses: [ expense ],
        total_count: 1,
        performance_metrics: { query_time: 50 },
        metadata: {
          filters_applied: {},
          page: 1,
          per_page: 25
        }
      })
    end

    before do
      allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
      allow(filter_service).to receive(:call).and_return(service_result)
      allow(controller).to receive(:setup_navigation_context)
      allow(controller).to receive(:calculate_summary_from_result)
      allow(controller).to receive(:build_filter_description).and_return("All expenses")
    end

    it "creates filter service with account IDs and filter params" do
      expect(Services::ExpenseFilterService).to receive(:new).with(
        hash_including(account_ids: [ email_account.id ])
      )

      get :index
    end

    it "calls the filter service" do
      expect(filter_service).to receive(:call)

      get :index
    end

    context "when service succeeds" do
      it "assigns expenses and metadata from service result" do
        get :index

        expect(assigns(:expenses)).to eq([ expense ])
        expect(assigns(:total_count)).to eq(1)
        expect(assigns(:performance_metrics)).to eq({ query_time: 50 })
        expect(assigns(:filters_applied)).to eq({})
        expect(assigns(:current_page)).to eq(1)
        expect(assigns(:per_page)).to eq(25)
      end

      it "calculates summary from result" do
        expect(controller).to receive(:calculate_summary_from_result).with(service_result)

        get :index
      end

      it "builds filter description" do
        expect(controller).to receive(:build_filter_description).and_return("All expenses")

        get :index
        expect(assigns(:filter_description)).to eq("All expenses")
      end

      it "sets scroll target when provided" do
        get :index, params: { scroll_to: "expense_123" }

        expect(assigns(:scroll_to)).to eq("expense_123")
      end
    end

    context "when service fails" do
      before do
        allow(service_result).to receive(:success?).and_return(false)
      end

      it "sets empty fallback values" do
        get :index

        expect(assigns(:expenses)).to eq([])
        expect(assigns(:total_count)).to eq(0)
        expect(assigns(:performance_metrics)).to eq({ error: true })
        expect(flash.now[:alert]).to eq("Error loading expenses. Please try again.")
      end
    end

    context "with different formats" do
      it "renders HTML format" do
        get :index
        expect(response).to render_template(:index)
      end

      it "renders JSON format" do
        get :index, format: :json
        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "GET #show", unit: true do
    before do
      allow(controller).to receive(:set_expense)
      controller.instance_variable_set(:@expense, expense)
    end

    it "sets the expense" do
      expect(controller).to receive(:set_expense)
      get :show, params: { id: expense.id }
    end

    it "renders the show template" do
      get :show, params: { id: expense.id }
      expect(response).to render_template(:show)
    end
  end

  describe "GET #new", unit: true do
    it "builds a new expense with default values" do
      get :new

      new_expense = assigns(:expense)
      expect(new_expense).to be_a_new(Expense)
      # Test that it's a new expense object - don't test internal defaults
      expect(new_expense.persisted?).to be_falsy
    end

    it "renders the new template" do
      get :new
      expect(response).to render_template(:new)
    end
  end

  describe "GET #edit", unit: true do
    before do
      allow(controller).to receive(:set_expense)
      controller.instance_variable_set(:@expense, expense)
    end

    it "sets the expense" do
      expect(controller).to receive(:set_expense)
      get :edit, params: { id: expense.id }
    end

    it "renders the edit template" do
      get :edit, params: { id: expense.id }
      expect(response).to render_template(:edit)
    end
  end

  describe "POST #create", unit: true do
    let(:expense_params) { { description: "New expense", amount: 100 } }

    context "with valid parameters" do
      let(:new_expense) { build(:expense, description: "New expense") }

      before do
        allow(Expense).to receive(:new).and_return(new_expense)
        allow(new_expense).to receive(:save).and_return(true)
      end

      it "creates new expense with permitted params" do
        expect(Expense).to receive(:new)
        expect(new_expense).to receive(:save)

        post :create, params: { expense: expense_params }
      end

      it "redirects to expenses index with success notice" do
        post :create, params: { expense: expense_params }

        expect(response).to redirect_to(expenses_path)
        expect(flash[:notice]).to eq("Gasto creado exitosamente.")
      end
    end

    context "with invalid parameters" do
      let(:new_expense) { build(:expense) }

      before do
        allow(Expense).to receive(:new).and_return(new_expense)
        allow(new_expense).to receive(:save).and_return(false)
      end

      it "renders new template with unprocessable content status" do
        post :create, params: { expense: expense_params }

        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH #update", unit: true do
    let(:expense_params) { { description: "Updated expense" } }

    before do
      allow(controller).to receive(:set_expense)
      controller.instance_variable_set(:@expense, expense)
    end

    context "with valid parameters" do
      before do
        allow(expense).to receive(:update).and_return(true)
      end

      it "updates the expense with permitted params" do
        expect(expense).to receive(:update)

        patch :update, params: { id: expense.id, expense: expense_params }
      end

      it "redirects to expense with success notice" do
        patch :update, params: { id: expense.id, expense: expense_params }

        expect(response).to redirect_to(expense)
        expect(flash[:notice]).to eq("Gasto actualizado exitosamente.")
      end
    end

    context "with invalid parameters" do
      before do
        allow(expense).to receive(:update).and_return(false)
      end

      it "renders edit template with unprocessable content status" do
        patch :update, params: { id: expense.id, expense: expense_params }

        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE #destroy", unit: true do
    let(:undo_entry) { instance_double(UndoHistory, id: 42, time_remaining: 1800) }

    before do
      allow(controller).to receive(:set_expense)
      controller.instance_variable_set(:@expense, expense)
      allow(expense).to receive(:soft_delete!)
      allow(UndoHistory).to receive(:create_for_deletion).and_return(undo_entry)
    end

    it "soft deletes the expense" do
      expect(expense).to receive(:soft_delete!)

      delete :destroy, params: { id: expense.id }
    end

    it "creates an undo history entry" do
      expect(UndoHistory).to receive(:create_for_deletion).with(expense, user: nil)

      delete :destroy, params: { id: expense.id }
    end

    it "redirects to expenses index with undo notice" do
      delete :destroy, params: { id: expense.id }

      expect(response).to redirect_to(expenses_path)
      expect(flash[:notice]).to eq("Gasto eliminado. Puedes deshacer esta acción.")
    end

    it "includes undo_id in flash" do
      delete :destroy, params: { id: expense.id }

      expect(flash[:undo_id]).to eq(42)
    end

    it "includes undo_time_remaining in flash" do
      delete :destroy, params: { id: expense.id }

      expect(flash[:undo_time_remaining]).to eq(1800)
    end

    context "with JSON format" do
      it "returns undo information in JSON response" do
        delete :destroy, params: { id: expense.id }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to eq(true)
        expect(json["undo_id"]).to eq(42)
        expect(json["undo_time_remaining"]).to eq(1800)
        expect(json["message"]).to eq("Gasto eliminado. Puedes deshacer esta acción.")
      end
    end
  end

  describe "GET #dashboard", unit: true do
    let(:metrics_calculator) { double("Services::MetricsCalculator") }
    let(:dashboard_service) { double("Services::DashboardService") }
    let(:batch_results) do
      {
        year: { metrics: { total_amount: 1000, transaction_count: 50 }, trends: { previous_period_total: 900 } },
        month: { metrics: { total_amount: 300, transaction_count: 15 }, trends: { previous_period_total: 250 } },
        week: { metrics: { total_amount: 75, transaction_count: 5 }, trends: { previous_period_total: 60 } },
        day: { metrics: { total_amount: 25, transaction_count: 2 }, trends: { previous_period_total: 20 } }
      }
    end
    let(:dashboard_data) do
      {
        totals: { total_expenses: 1000, expense_count: 50, current_month_total: 300, last_month_total: 250 },
        recent_expenses: [ expense ],
        category_breakdown: { totals: {}, sorted: [] },
        monthly_trend: [],
        bank_breakdown: {},
        top_merchants: [],
        email_accounts: [ email_account ],
        sync_info: {},
        sync_sessions: { active_session: nil, last_completed: nil }
      }
    end

    before do
      allow(EmailAccount).to receive(:active).and_return(double(first: email_account))
      allow(Services::MetricsCalculator).to receive(:batch_calculate).and_return(batch_results)
      allow(Services::DashboardService).to receive(:new).and_return(dashboard_service)
      allow(dashboard_service).to receive(:analytics).and_return(dashboard_data)
    end

    it "calculates metrics using Services::MetricsCalculator" do
      expect(Services::MetricsCalculator).to receive(:batch_calculate).with(
        email_account: email_account,
        periods: [ :year, :month, :week, :day ],
        reference_date: Date.current
      )

      get :dashboard
    end

    it "assigns dashboard metrics variables" do
      get :dashboard

      expect(assigns(:total_metrics)).to eq(batch_results[:year])
      expect(assigns(:month_metrics)).to eq(batch_results[:month])
      expect(assigns(:week_metrics)).to eq(batch_results[:week])
      expect(assigns(:day_metrics)).to eq(batch_results[:day])
    end

    it "assigns legacy compatibility variables" do
      get :dashboard

      expect(assigns(:total_expenses)).to eq(1000)
      expect(assigns(:expense_count)).to eq(50)
      expect(assigns(:current_month_total)).to eq(300)
      expect(assigns(:last_month_total)).to eq(250)
      expect(assigns(:recent_expenses)).to eq([ expense ])
    end

    it "renders dashboard template" do
      get :dashboard
      expect(response).to render_template(:dashboard)
    end
  end

  describe "POST #sync_emails", unit: true do
    let(:sync_service) { double("Services::Email::SyncService") }
    let(:sync_result) { { success: true, message: "Synced successfully" } }

    before do
      # Mock the Services::Email::SyncService class
      services_module = Module.new
      stub_const("Services", services_module)
      email_module = Module.new
      services_module.const_set("Email", email_module)
      sync_service_class = Class.new
      sync_error_class = Class.new(StandardError)
      sync_service_class.const_set("SyncError", sync_error_class)
      email_module.const_set("SyncService", sync_service_class)
      allow(sync_service_class).to receive(:new).and_return(sync_service)
      allow(sync_service).to receive(:sync_emails).and_return(sync_result)
    end

    it "calls email sync service" do
      expect(Services::Email::SyncService).to receive(:new)
      expect(sync_service).to receive(:sync_emails).with(email_account_id: nil)

      post :sync_emails
    end

    context "when sync succeeds" do
      it "redirects with success notice" do
        post :sync_emails

        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to eq("Synced successfully")
      end
    end

    context "when sync fails" do
      before do
        allow(sync_service).to receive(:sync_emails).and_raise(Services::Email::SyncService::SyncError, "Sync failed")
      end

      it "redirects with error alert" do
        post :sync_emails

        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:alert]).to eq("Sync failed")
      end
    end
  end

  describe "POST #correct_category", unit: true do
    let(:correction_params) { { category_id: category.id } }

    before do
      allow(controller).to receive(:set_expense)
      controller.instance_variable_set(:@expense, expense)
      allow(expense).to receive(:reject_ml_suggestion!)
      allow(Category).to receive(:exists?).and_return(true)
    end

    it "validates category exists and calls reject_ml_suggestion!" do
      expect(Category).to receive(:exists?).with(id: category.id.to_s)
      expect(expense).to receive(:reject_ml_suggestion!).with(category.id.to_s)

      post :correct_category, params: { id: expense.id, **correction_params }
    end

    it "responds with JSON success" do
      post :correct_category, params: { id: expense.id, **correction_params }, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to eq(true)
    end
  end

  describe "POST #bulk_categorize", unit: true do
    let(:bulk_params) do
      {
        expense_ids: [ expense.id ],
        category_id: category.id
      }
    end
    let(:categorization_service) { double("Services::BulkOperations::CategorizationService") }
    let(:service_result) { { success: true, message: "Categorized successfully", affected_count: 1, failures: [], background: false, job_id: nil } }

    before do
      # Mock the Services::BulkOperations::CategorizationService
      categorization_service_class = Class.new do
        def initialize(expense_ids:, category_id:, user:, options:)
          # Mock constructor that accepts the parameters
        end

        def call
          # Mock call method
        end
      end
      stub_const("Services::BulkOperations::CategorizationService", categorization_service_class)
      allow(categorization_service_class).to receive(:new).and_return(categorization_service)
      allow(categorization_service).to receive(:call).and_return(service_result)
      allow(controller).to receive(:authorize_bulk_operation!).and_return(true)
    end

    it "uses the bulk categorization service" do
      expect(Services::BulkOperations::CategorizationService).to receive(:new).with(
        expense_ids: [ expense.id.to_s ],
        category_id: category.id.to_s,
        user: current_user_id, # Controller returns current_user_id from before block
        options: { broadcast_updates: true, track_ml_corrections: true }
      )
      expect(categorization_service).to receive(:call)

      post :bulk_categorize, params: bulk_params, format: :json
    end

    it "responds with JSON success and count" do
      post :bulk_categorize, params: bulk_params, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to eq(true)
      expect(json_response["affected_count"]).to eq(1)
    end
  end

  describe "before_actions", unit: true do
    describe "#set_expense" do
      it "finds expense by ID and assigns to instance variable" do
        # Test the actual private method
        controller.params = ActionController::Parameters.new(id: expense.id)
        controller.send(:set_expense)

        expect(controller.instance_variable_get(:@expense)).to eq(expense)
      end
    end

    describe "#authorize_expense!" do
      before do
        controller.instance_variable_set(:@expense, expense)
        # Remove the mock so we test the real method
        allow(controller).to receive(:authorize_expense!).and_call_original
      end

      it "calls can_modify_expense? to check permissions" do
        expect(controller).to receive(:can_modify_expense?).with(expense).and_return(true)

        controller.send(:authorize_expense!)
      end
    end
  end

  describe "private methods", unit: true do
    describe "#expense_params" do
      let(:params_hash) do
        {
          expense: {
            description: "Test expense",
            amount: 100,
            category_id: category.id,
            unauthorized_param: "should_not_be_permitted"
          }
        }
      end

      before do
        controller.params = ActionController::Parameters.new(params_hash)
      end

      it "permits only allowed parameters" do
        permitted_params = controller.send(:expense_params)

        expect(permitted_params).to include("description", "amount", "category_id")
        expect(permitted_params).not_to include("unauthorized_param")
      end
    end

    describe "#filter_params" do
      let(:filter_hash) do
        {
          status: "pending",
          date_from: "2023-01-01",
          page: 1,
          unauthorized_filter: "should_not_be_permitted"
        }
      end

      before do
        controller.params = ActionController::Parameters.new(filter_hash)
      end

      it "permits only allowed filter parameters" do
        permitted_params = controller.send(:filter_params)

        expect(permitted_params.keys).to include("status", "date_from", "page")
        expect(permitted_params.keys).not_to include("unauthorized_filter")
      end
    end

    describe "#current_user_expenses" do
      it "returns expenses scoped to user's email accounts" do
        allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))

        result = controller.send(:current_user_expenses)

        expect(result).to be_a(ActiveRecord::Relation)
        expect(result.to_sql).to include("email_account_id")
      end
    end

    describe "#can_modify_expense?" do
      # Remove the global mock for these tests to test the actual method behavior
      before do
        allow(controller).to receive(:can_modify_expense?).and_call_original
      end

      it "returns true for expenses belonging to user's accounts" do
        allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))

        result = controller.send(:can_modify_expense?, expense)

        expect(result).to be_truthy
      end

      it "returns false for expenses not belonging to user's accounts" do
        other_account = create(:email_account, email: "other@example.com")
        other_expense = build(:expense, email_account: other_account)
        allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.none)

        result = controller.send(:can_modify_expense?, other_expense)

        expect(result).to be_falsy
      end
    end

    describe "#build_filter_description" do
      it "returns nil when no filters are applied" do
        controller.params = ActionController::Parameters.new({})

        description = controller.send(:build_filter_description)

        expect(description).to be_nil
      end

      it "returns period description when active_period is set" do
        controller.params = ActionController::Parameters.new(period: "month")
        controller.instance_variable_set(:@active_period, "month")

        description = controller.send(:build_filter_description)

        expect(description).to eq("Gastos de este mes")
      end
    end
  end

  describe "error handling", unit: true do
    context "when expense is not found" do
      it "redirects with error message instead of raising" do
        # The controller's set_expense method catches RecordNotFound and redirects
        get :show, params: { id: 99999 }

        expect(response).to redirect_to(expenses_path)
        expect(flash[:alert]).to eq("Gasto no encontrado o no tienes permiso para verlo.")
      end
    end

    context "when service raises an error" do
      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_raise(StandardError, "Service error")
      end

      it "does not rescue the error (lets Rails handle it)" do
        expect {
          get :index
        }.to raise_error(StandardError, "Service error")
      end
    end
  end
end
