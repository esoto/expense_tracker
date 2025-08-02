require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  let(:category) { create(:category) }
  let(:email_account) { create(:email_account, :bac) }
  let(:expense) { create(:expense, category: category, email_account: email_account) }
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
      currency: 'invalid',
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
      expect(assigns(:expenses)).to eq([expense1, expense2])
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
      expect(assigns(:total_amount)).to eq(300.0)
      expect(assigns(:expense_count)).to eq(2)
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
        expect(created_expense.bank_name).to eq("Manual Entry")
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
        expect(response).to have_http_status(:unprocessable_entity)
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
        expect(response).to have_http_status(:unprocessable_entity)
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
    let!(:current_month_expense) { create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account) }
    let!(:last_month_expense) { create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account) }

    it "returns a success response" do
      get :dashboard
      expect(response).to be_successful
    end

    it "calculates total statistics" do
      get :dashboard
      expect(assigns(:total_expenses)).to eq(300.0)
      expect(assigns(:expense_count)).to eq(2)
    end

    it "calculates current month totals" do
      get :dashboard
      expect(assigns(:current_month_total)).to eq(100.0)
    end

    it "calculates last month totals" do
      get :dashboard
      expect(assigns(:last_month_total)).to eq(200.0)
    end

    it "loads recent expenses" do
      get :dashboard
      expect(assigns(:recent_expenses)).to include(current_month_expense)
      expect(assigns(:recent_expenses).size).to be <= 10
    end

    it "calculates category totals" do
      get :dashboard
      expect(assigns(:category_totals)).to be_a(Hash)
      expect(assigns(:sorted_categories)).to be_present
    end

    it "generates monthly trend data" do
      get :dashboard
      expect(assigns(:monthly_data)).to be_a(Hash)
    end

    it "calculates bank totals" do
      get :dashboard
      expect(assigns(:bank_totals)).to be_present
    end

    it "finds top merchants" do
      get :dashboard
      expect(assigns(:top_merchants)).to be_present
      expect(assigns(:top_merchants).size).to be <= 10
    end

    it "loads active email accounts" do
      get :dashboard
      expect(assigns(:email_accounts)).to include(email_account)
    end

    it "gets last sync info" do
      get :dashboard
      expect(assigns(:last_sync_info)).to be_present
    end
  end

  describe "POST #sync_emails" do
    context "with specific email account" do
      it "enqueues ProcessEmailsJob for specific account" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id)
        
        post :sync_emails, params: { email_account_id: email_account.id }
      end

      it "redirects with success message" do
        allow(ProcessEmailsJob).to receive(:perform_later)
        
        post :sync_emails, params: { email_account_id: email_account.id }
        
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to include("Sincronización iniciada para #{email_account.email}")
      end

      context "with non-existent account" do
        it "redirects with error message" do
          post :sync_emails, params: { email_account_id: 99999 }
          
          expect(response).to redirect_to(dashboard_expenses_path)
          expect(flash[:alert]).to eq("Cuenta de correo no encontrada.")
        end
      end

      context "with inactive account" do
        let(:inactive_account) { create(:email_account, :inactive) }

        it "redirects with error message" do
          post :sync_emails, params: { email_account_id: inactive_account.id }
          
          expect(response).to redirect_to(dashboard_expenses_path)
          expect(flash[:alert]).to eq("La cuenta de correo está inactiva.")
        end
      end
    end

    context "without email account (sync all)" do
      let!(:account2) { create(:email_account, :gmail) }

      it "enqueues ProcessEmailsJob for all accounts" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(no_args)
        
        post :sync_emails
      end

      it "redirects with success message including account count" do
        allow(ProcessEmailsJob).to receive(:perform_later)
        
        post :sync_emails
        
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to include("Sincronización iniciada para 2 cuentas de correo")
      end

      context "with no active accounts" do
        before do
          EmailAccount.update_all(active: false)
        end

        it "redirects with error message" do
          post :sync_emails
          
          expect(response).to redirect_to(dashboard_expenses_path)
          expect(flash[:alert]).to eq("No hay cuentas de correo activas configuradas.")
        end
      end
    end

    context "when an error occurs" do
      before do
        allow(ProcessEmailsJob).to receive(:perform_later).and_raise(StandardError.new("Test error"))
      end

      it "catches exceptions and redirects with error message" do
        post :sync_emails, params: { email_account_id: email_account.id }
        
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:alert]).to eq("Error al iniciar la sincronización. Por favor, inténtalo de nuevo.")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Error starting email sync/)
        
        post :sync_emails, params: { email_account_id: email_account.id }
      end
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

    describe "#get_last_sync_info" do
      let!(:expense1) { create(:expense, email_account: email_account, created_at: 1.hour.ago) }
      let!(:expense2) { create(:expense, email_account: email_account, created_at: 30.minutes.ago) }

      it "calculates last sync times per email account" do
        get :dashboard
        sync_info = assigns(:last_sync_info)
        
        expect(sync_info[email_account.id][:last_sync]).to be_within(1.second).of(expense2.created_at)
        expect(sync_info[email_account.id][:account]).to eq(email_account)
      end

      it "checks for running jobs" do
        # Mock SolidQueue::Job to avoid database dependency
        allow(SolidQueue::Job).to receive(:where).and_return(double(exists?: false, count: 0))
        
        get :dashboard
        sync_info = assigns(:last_sync_info)
        
        expect(sync_info[:has_running_jobs]).to eq(false)
        expect(sync_info[:running_job_count]).to eq(0)
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

    it "includes associations to avoid N+1 queries in dashboard" do
      expect(Expense).to receive(:includes).with(:category, :email_account).and_call_original
      get :dashboard
    end

    it "limits expensive queries in dashboard" do
      # Mock groupdate to avoid time zone issues in tests
      allow_any_instance_of(ActiveRecord::Relation).to receive(:group_by_month).and_return(double(sum: {}))
      
      get :dashboard
      expect(assigns(:recent_expenses).size).to be <= 10
      expect(assigns(:top_merchants).size).to be <= 10
    end
  end
end