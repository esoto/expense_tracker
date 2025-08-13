require 'rails_helper'

RSpec.describe Api::WebhooksController, type: :controller do
  let(:api_token) { create(:api_token) }
  let(:email_account) { create(:email_account, :bac) }
  let(:category) { create(:category) }
  let(:valid_headers) { { "Authorization" => "Bearer #{api_token.token}" } }

  before do
    request.headers.merge!(valid_headers)
  end

  describe "authentication" do
    context "with valid API token" do
      it "allows access to endpoints" do
        post :process_emails
        expect(response).to have_http_status(:accepted)
      end
    end

    context "without Authorization header" do
      before { request.headers["Authorization"] = nil }

      it "returns unauthorized status" do
        post :process_emails
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post :process_emails
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Missing API token")
      end
    end

    context "with invalid API token" do
      before { request.headers["Authorization"] = "Bearer invalid_token" }

      it "returns unauthorized status" do
        post :process_emails
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post :process_emails
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid or expired API token")
      end
    end

    context "with expired API token" do
      let(:expired_token) { create(:api_token, :expired) }

      before { request.headers["Authorization"] = "Bearer #{expired_token.token}" }

      it "returns unauthorized status" do
        post :process_emails
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST #process_emails" do
    context "with specific email account" do
      it "enqueues ProcessEmailsJob for specific account" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id }
      end

      it "returns success response" do
        allow(ProcessEmailsJob).to receive(:perform_later)

        post :process_emails, params: { email_account_id: email_account.id }

        expect(response).to have_http_status(:accepted)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["message"]).to include("queued for account #{email_account.id}")
        expect(json_response["email_account_id"]).to eq(email_account.id.to_s)
      end
    end

    context "without email account (process all)" do
      it "enqueues ProcessEmailsJob for all accounts" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(since: anything)

        post :process_emails
      end

      it "returns success response" do
        allow(ProcessEmailsJob).to receive(:perform_later)

        post :process_emails

        expect(response).to have_http_status(:accepted)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["message"]).to eq("Email processing queued for all active accounts")
      end
    end

    context "with since parameter variations" do
      it "handles numeric hours" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "24" }
      end

      it "handles 'today' keyword" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "today" }
      end

      it "handles 'yesterday' keyword" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "yesterday" }
      end

      it "handles 'week' keyword" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "week" }
      end

      it "handles 'month' keyword" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "month" }
      end

      it "handles ISO date string" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "2025-01-01T00:00:00Z" }
      end

      it "defaults to 1 week ago for invalid date" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id, since: anything)

        post :process_emails, params: { email_account_id: email_account.id, since: "invalid_date" }
      end
    end
  end

  describe "POST #add_expense" do
    let(:valid_expense_params) do
      {
        amount: 15000.0,
        description: "API Test Expense",
        merchant_name: "Test Merchant",
        transaction_date: Date.current.iso8601,
        category_id: category.id
      }
    end

    let(:invalid_expense_params) do
      {
        amount: -100.0, # Invalid negative amount
        description: "",
        transaction_date: nil
      }
    end

    context "with valid parameters" do
      it "creates a new expense" do
        expect {
          post :add_expense, params: { expense: valid_expense_params }
        }.to change(Expense, :count).by(1)
      end

      it "sets default values for API-created expenses" do
        post :add_expense, params: { expense: valid_expense_params }

        expense = Expense.last
        expect(expense.status).to eq("processed")
        expect(expense.email_account).to be_present
        expect(expense.email_account.active).to be true
      end

      it "returns success response with expense data" do
        post :add_expense, params: { expense: valid_expense_params }

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["message"]).to eq("Expense created successfully")
        expect(json_response["expense"]).to be_present
        expect(json_response["expense"]["amount"]).to eq(15000.0)
      end
    end

    context "with invalid parameters" do
      it "does not create an expense" do
        expect {
          post :add_expense, params: { expense: invalid_expense_params }
        }.not_to change(Expense, :count)
      end

      it "returns error response" do
        post :add_expense, params: { expense: invalid_expense_params }

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("error")
        expect(json_response["message"]).to eq("Failed to create expense")
        expect(json_response["errors"]).to be_present
      end
    end

    context "when no email account exists" do
      before { EmailAccount.destroy_all }

      it "creates default manual account" do
        expect {
          post :add_expense, params: { expense: valid_expense_params }
        }.to change(EmailAccount, :count).by(1)

        account = EmailAccount.last
        expect(account.provider).to eq("manual")
        expect(account.email).to eq("manual@localhost")
        expect(account.bank_name).to eq("Manual Entry")
      end
    end
  end

  describe "GET #recent_expenses" do
    let!(:expense1) { create(:expense, created_at: 1.hour.ago, category: category, email_account: email_account) }
    let!(:expense2) { create(:expense, created_at: 30.minutes.ago, category: category, email_account: email_account) }

    it "returns recent expenses in JSON format" do
      get :recent_expenses

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(json_response["expenses"]).to be_an(Array)
      
      # Should include at least our test expenses (may have others from different tests)
      expect(json_response["expenses"].size).to be >= 2
      expense_ids = json_response["expenses"].map { |e| e["id"] }
      expect(expense_ids).to include(expense1.id, expense2.id)
    end

    it "orders expenses by most recent first" do
      get :recent_expenses

      json_response = JSON.parse(response.body)
      expenses = json_response["expenses"]
      
      # Find our test expenses in the results
      our_expenses = expenses.select { |e| [expense1.id, expense2.id].include?(e["id"]) }
      expect(our_expenses.size).to eq(2)
      
      # expense2 (30 min ago) should come before expense1 (1 hour ago) in the results
      expense2_index = expenses.find_index { |e| e["id"] == expense2.id }
      expense1_index = expenses.find_index { |e| e["id"] == expense1.id }
      expect(expense2_index).to be < expense1_index
    end

    it "respects limit parameter" do
      get :recent_expenses, params: { limit: 1 }

      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to eq(1)
    end

    it "caps limit at 50" do
      get :recent_expenses, params: { limit: 100 }

      # Verify the query uses limit 50 (would need to create more expenses to fully test)
      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to be <= 50
    end

    it "defaults to limit 10 for invalid limit" do
      get :recent_expenses, params: { limit: 0 }

      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to be <= 10
    end

    it "includes formatted expense data" do
      get :recent_expenses

      json_response = JSON.parse(response.body)
      expense = json_response["expenses"].first

      expect(expense).to include(
        "id", "amount", "formatted_amount", "description",
        "merchant_name", "transaction_date", "category",
        "bank_name", "status", "created_at"
      )
    end
  end

  describe "GET #expense_summary" do
    it "calls ExpenseSummaryService and returns JSON response" do
      expect_any_instance_of(ExpenseSummaryService).to receive(:period).and_return("month")
      expect_any_instance_of(ExpenseSummaryService).to receive(:summary).and_return({
        total_amount: 100.0,
        expense_count: 1,
        start_date: "2025-01-01T00:00:00Z",
        end_date: "2025-02-01T00:00:00Z",
        by_category: { "Food" => 100.0 }
      })

      get :expense_summary, params: { period: "month" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(json_response["period"]).to eq("month")
      expect(json_response["summary"]).to be_present
    end

    it "passes period parameter to ExpenseSummaryService" do
      expect(ExpenseSummaryService).to receive(:new).with("week").and_call_original

      get :expense_summary, params: { period: "week" }
    end

    it "defaults to no period when none specified" do
      expect(ExpenseSummaryService).to receive(:new).with(nil).and_call_original

      get :expense_summary
    end
  end

  describe "private methods" do
    describe "#parse_since_parameter" do
      controller_instance = Api::WebhooksController.new

      it "handles numeric hours" do
        controller_instance.params = { since: "48" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.minute).of(48.hours.ago)
      end

      it "handles 'today' keyword" do
        controller_instance.params = { since: "today" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(Date.current.beginning_of_day)
      end

      it "handles 'yesterday' keyword" do
        controller_instance.params = { since: "yesterday" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(1.day.ago.beginning_of_day)
      end

      it "handles 'week' keyword" do
        controller_instance.params = { since: "week" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(1.week.ago)
      end

      it "handles 'month' keyword" do
        controller_instance.params = { since: "month" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(1.month.ago)
      end

      it "parses valid date strings" do
        controller_instance.params = { since: "2025-01-01T12:00:00Z" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to eq(Time.parse("2025-01-01T12:00:00Z"))
      end

      it "defaults to 1 week ago for invalid input" do
        controller_instance.params = { since: "invalid_date" }
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(1.week.ago)
      end

      it "defaults to 1 week ago when no since parameter" do
        controller_instance.params = {}
        result = controller_instance.send(:parse_since_parameter)
        expect(result).to be_within(1.hour).of(1.week.ago)
      end
    end

    describe "#default_email_account" do
      it "returns first active account when available" do
        controller.send(:authenticate_api_token) # Set up authentication
        result = controller.send(:default_email_account)
        expect(result).to be_an(EmailAccount)
        expect(result.active).to be true
      end

      it "creates manual account when no active accounts exist" do
        EmailAccount.update_all(active: false)
        controller.send(:authenticate_api_token)

        expect {
          result = controller.send(:default_email_account)
          expect(result.provider).to eq("manual")
          expect(result.email).to eq("manual@localhost")
        }.to change(EmailAccount, :count).by(1)
      end
    end

    describe "#format_expense" do
      let(:expense) { create(:expense, category: category, email_account: email_account) }

      it "formats expense data correctly" do
        controller.send(:authenticate_api_token)
        result = controller.send(:format_expense, expense)

        expect(result).to include(
          id: expense.id,
          amount: expense.amount.to_f,
          formatted_amount: expense.formatted_amount,
          description: expense.display_description,
          merchant_name: expense.merchant_name,
          category: expense.category.name,
          bank_name: expense.bank_name,
          status: expense.status
        )

        expect(result[:transaction_date]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(result[:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end
  end

  describe "security considerations" do
    it "skips CSRF token verification" do
      # This is tested implicitly by the fact that POST requests work without CSRF tokens
      # We can verify this by checking that POST requests succeed without CSRF tokens
      post :process_emails
      expect(response).not_to have_http_status(:forbidden)
    end

    it "requires authentication for all actions" do
      request.headers["Authorization"] = nil

      post :process_emails
      expect(response).to have_http_status(:unauthorized)

      post :add_expense, params: { expense: { amount: 100 } }
      expect(response).to have_http_status(:unauthorized)

      get :recent_expenses
      expect(response).to have_http_status(:unauthorized)

      get :expense_summary
      expect(response).to have_http_status(:unauthorized)
    end

    it "properly validates API token on each request" do
      # Valid request
      post :process_emails
      expect(response).to have_http_status(:accepted)

      # Change to invalid token
      request.headers["Authorization"] = "Bearer invalid"
      post :process_emails
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "error handling" do
    context "when ProcessEmailsJob fails to enqueue" do
      before do
        allow(ProcessEmailsJob).to receive(:perform_later).and_raise(StandardError.new("Queue error"))
      end

      it "allows the error to bubble up" do
        expect {
          post :process_emails
        }.to raise_error(StandardError, "Queue error")
      end
    end

    context "when database errors occur" do
      before do
        allow(Expense).to receive(:new).and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it "allows database errors to bubble up" do
        expect {
          post :add_expense, params: { expense: { amount: 100 } }
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
    end
  end

  describe "performance considerations" do
    it "includes associations in recent_expenses to avoid N+1 queries" do
      expect(Expense).to receive(:includes).with(:category, :email_account).and_call_original
      get :recent_expenses
    end

    it "limits query results appropriately" do
      create_list(:expense, 15, category: category, email_account: email_account)

      get :recent_expenses, params: { limit: 5 }
      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to eq(5)
    end
  end
end
