require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  let(:category) { create(:category) }
  let(:email_account) { create(:email_account, :bac) }
  let!(:expense) { create(:expense, category: category, email_account: email_account) }
  let(:valid_attributes) do
    {
      amount: 15000.0,
      currency: 'crc',
      transaction_date: Date.current,
      merchant_name: 'Test Merchant',
      description: 'Test expense',
      category_id: category.id,
      email_account_id: email_account.id
    }
  end

  let(:invalid_attributes) do
    {
      amount: -100.0, # Invalid negative amount
      transaction_date: nil,
      category_id: nil
    }
  end

  describe "GET #index" do
    let!(:expense1) { create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account) }
    let!(:expense2) { create(:expense, amount: 200.0, transaction_date: 1.day.ago, category: category, email_account: email_account) }

    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns @expenses ordered by transaction_date desc" do
      get :index
      expenses = assigns(:expenses).to_a
      expect(expenses).to include(expense1, expense2)
      # Verify they're ordered by transaction_date desc, then created_at desc
      expect(expenses.first.transaction_date).to be >= expenses.last.transaction_date
    end

    it "includes associations for efficiency" do
      expect(Expense).to receive(:includes).with(:category, :email_account).and_call_original
      get :index
    end

    it "limits results to 25 expenses" do
      expect_any_instance_of(ActiveRecord::Relation).to receive(:limit).with(25).and_call_original
      get :index
    end

    it "calculates summary statistics" do
      get :index
      expect(assigns(:total_amount)).to be > 0
      expect(assigns(:expense_count)).to be >= 2
      expect(assigns(:categories_summary)).to be_present
    end

    context "with category filter" do
      let(:other_category) { create(:category, name: 'Other Category') }
      let!(:other_expense) { create(:expense, category: other_category, email_account: email_account) }

      it "filters expenses by category" do
        get :index, params: { category: category.name }
        expect(assigns(:expenses)).to include(expense1, expense2)
        expect(assigns(:expenses)).not_to include(other_expense)
      end
    end

    context "with date range filter" do
      let!(:old_expense) { create(:expense, transaction_date: 1.week.ago, category: category, email_account: email_account) }

      it "filters expenses by date range" do
        start_date = 2.days.ago.to_date
        end_date = Date.current

        get :index, params: { start_date: start_date, end_date: end_date }

        expect(assigns(:expenses)).to include(expense1, expense2)
        expect(assigns(:expenses)).not_to include(old_expense)
      end
    end

    context "with bank filter" do
      let!(:other_expense) { create(:expense, :usd, category: category) }

      before do
        expense1.update(bank_name: 'BAC')
        expense2.update(bank_name: 'BAC')
        other_expense.update(bank_name: 'BCR')
      end

      it "filters expenses by bank" do
        get :index, params: { bank: 'BAC' }
        expect(assigns(:expenses)).to include(expense1, expense2)
        expect(assigns(:expenses)).not_to include(other_expense)
      end
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { id: expense.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested expense" do
      get :show, params: { id: expense.to_param }
      expect(assigns(:expense)).to eq(expense)
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end

    it "assigns a new expense" do
      get :new
      expect(assigns(:expense)).to be_a_new(Expense)
    end

    it "loads categories and email accounts" do
      category # Ensure category exists
      email_account # Ensure email account exists

      get :new
      expect(assigns(:categories)).to be_present
      expect(assigns(:email_accounts)).to be_present
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { id: expense.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested expense" do
      get :edit, params: { id: expense.to_param }
      expect(assigns(:expense)).to eq(expense)
    end

    it "loads categories and email accounts" do
      get :edit, params: { id: expense.to_param }
      expect(assigns(:categories)).to be_present
      expect(assigns(:email_accounts)).to be_present
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Expense" do
        expect {
          post :create, params: { expense: valid_attributes }
        }.to change(Expense, :count).by(1)
      end

      it "sets manual entry defaults" do
        post :create, params: { expense: valid_attributes }
        created_expense = Expense.last
        expect(created_expense.read_attribute(:bank_name)).to eq("Manual Entry")
        expect(created_expense.status).to eq("processed")
      end

      it "defaults to CRC currency if blank" do
        attributes_without_currency = valid_attributes.except(:currency)
        post :create, params: { expense: attributes_without_currency }
        created_expense = Expense.last
        expect(created_expense.currency).to eq("crc")
      end

      it "redirects to the created expense" do
        post :create, params: { expense: valid_attributes }
        expect(response).to redirect_to(Expense.last)
      end

      it "sets a success notice" do
        post :create, params: { expense: valid_attributes }
        expect(flash[:notice]).to eq("Gasto creado exitosamente.")
      end
    end

    context "with invalid params" do
      it "does not create a new Expense" do
        expect {
          post :create, params: { expense: invalid_attributes }
        }.to change(Expense, :count).by(0)
      end

      it "renders the new template" do
        post :create, params: { expense: invalid_attributes }
        expect(response).to render_template("new")
      end

      it "returns unprocessable entity status" do
        post :create, params: { expense: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "loads categories and email accounts for form" do
        post :create, params: { expense: invalid_attributes }
        expect(assigns(:categories)).to be_present
        expect(assigns(:email_accounts)).to be_present
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) do
        {
          amount: 25000.0,
          description: 'Updated expense'
        }
      end

      it "updates the requested expense" do
        put :update, params: { id: expense.to_param, expense: new_attributes }
        expense.reload
        expect(expense.amount).to eq(25000.0)
        expect(expense.description).to eq('Updated expense')
      end

      it "redirects to the expense" do
        put :update, params: { id: expense.to_param, expense: new_attributes }
        expect(response).to redirect_to(expense)
      end

      it "sets a success notice" do
        put :update, params: { id: expense.to_param, expense: new_attributes }
        expect(flash[:notice]).to eq("Gasto actualizado exitosamente.")
      end
    end

    context "with invalid params" do
      it "renders the edit template" do
        put :update, params: { id: expense.to_param, expense: invalid_attributes }
        expect(response).to render_template("edit")
      end

      it "returns unprocessable entity status" do
        put :update, params: { id: expense.to_param, expense: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "loads categories and email accounts for form" do
        put :update, params: { id: expense.to_param, expense: invalid_attributes }
        expect(assigns(:categories)).to be_present
        expect(assigns(:email_accounts)).to be_present
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested expense" do
      expense # Create the expense
      expect {
        delete :destroy, params: { id: expense.to_param }
      }.to change(Expense, :count).by(-1)
    end

    it "redirects to the expenses list" do
      delete :destroy, params: { id: expense.to_param }
      expect(response).to redirect_to(expenses_url)
    end

    it "sets a success notice" do
      delete :destroy, params: { id: expense.to_param }
      expect(flash[:notice]).to eq("Gasto eliminado exitosamente.")
    end
  end

  describe "GET #dashboard" do
    it "returns a success response" do
      get :dashboard
      expect(response).to be_successful
    end

    it "calls DashboardService and assigns data for the view" do
      expect_any_instance_of(DashboardService).to receive(:analytics).and_call_original

      get :dashboard

      # Verify all expected instance variables are assigned
      expect(assigns(:total_expenses)).to be_present
      expect(assigns(:expense_count)).to be_present
      expect(assigns(:current_month_total)).to be_present
      expect(assigns(:last_month_total)).to be_present
      expect(assigns(:recent_expenses)).to be_present
      expect(assigns(:category_totals)).to be_present
      expect(assigns(:sorted_categories)).to be_present
      expect(assigns(:monthly_data)).to be_present
      expect(assigns(:bank_totals)).to be_present
      expect(assigns(:top_merchants)).to be_present
      expect(assigns(:email_accounts)).to be_present
      expect(assigns(:last_sync_info)).to be_present
    end
  end

  describe "POST #sync_emails" do
    it "calls SyncService and redirects with success message" do
      expect_any_instance_of(SyncService).to receive(:sync_emails)
        .with(email_account_id: email_account.id.to_s)
        .and_return({ message: "Sync started successfully" })

      post :sync_emails, params: { email_account_id: email_account.id }

      expect(response).to redirect_to(dashboard_expenses_path)
      expect(flash[:notice]).to eq("Sync started successfully")
    end

    it "handles SyncService::SyncError and redirects with alert" do
      expect_any_instance_of(SyncService).to receive(:sync_emails)
        .and_raise(SyncService::SyncError.new("Account not found"))

      post :sync_emails, params: { email_account_id: 99999 }

      expect(response).to redirect_to(dashboard_expenses_path)
      expect(flash[:alert]).to eq("Account not found")
    end

    it "handles general errors and redirects with generic message" do
      expect_any_instance_of(SyncService).to receive(:sync_emails)
        .and_raise(StandardError.new("Unexpected error"))

      expect(Rails.logger).to receive(:error).with(/Error starting email sync/)

      post :sync_emails

      expect(response).to redirect_to(dashboard_expenses_path)
      expect(flash[:alert]).to eq("Error al iniciar la sincronización. Por favor, inténtalo de nuevo.")
    end
  end

  describe "private methods" do
    describe "#set_expense" do
      it "finds the expense by id" do
        get :show, params: { id: expense.to_param }
        expect(assigns(:expense)).to eq(expense)
      end

      it "raises error for non-existent expense" do
        expect {
          get :show, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "#expense_params" do
      it "permits expected parameters" do
        params = ActionController::Parameters.new(
          expense: {
            amount: 100.0,
            currency: 'crc',
            transaction_date: Date.current,
            merchant_name: 'Test',
            description: 'Test',
            category_id: 1,
            email_account_id: 1,
            notes: 'Test notes',
            forbidden_param: 'should not be included'
          }
        )

        controller.params = params
        permitted = controller.send(:expense_params)

        expect(permitted).to include(:amount, :currency, :transaction_date, :merchant_name, :description, :category_id, :email_account_id, :notes)
        expect(permitted).not_to include(:forbidden_param)
      end
    end
  end

  describe "error handling" do
    context "when expense not found" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when database error occurs" do
      before do
        allow(Expense).to receive(:includes).and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it "allows database errors to bubble up" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
    end
  end

  describe "performance considerations" do
    it "includes associations to avoid N+1 queries in index" do
      expect(Expense).to receive(:includes).with(:category, :email_account).and_call_original
      get :index
    end
  end
end
