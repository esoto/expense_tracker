require "rails_helper"

RSpec.describe Api::WebhooksController, type: :controller, unit: true do
  let(:api_token) { create(:api_token, :active) }
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

  before do
    # Mock authentication to use our test token
    allow(ApiToken).to receive(:authenticate).with(api_token.token).and_return(api_token)
    request.headers["Authorization"] = "Bearer #{api_token.token}"
  end

  describe "POST #process_emails" do
    context "with email_account_id parameter" do
      it "queues ProcessEmailsJob for specific account" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_a(Time)
        )

        post :process_emails, params: { email_account_id: email_account.id }

        expect(response).to have_http_status(:accepted)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["email_account_id"]).to eq(email_account.id.to_s)
      end
    end

    context "without email_account_id parameter" do
      it "queues ProcessEmailsJob for all accounts" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(since: be_a(Time))

        post :process_emails

        expect(response).to have_http_status(:accepted)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["message"]).to include("all active accounts")
      end
    end

    context "with since parameter" do
      it "parses numeric since parameter as hours ago" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(2.hours.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "2" }
      end

      it "parses 'today' since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(Date.current.beginning_of_day)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "today" }
      end

      it "parses 'yesterday' since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.day.ago.beginning_of_day)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "yesterday" }
      end

      it "parses 'week' since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.week.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "week" }
      end

      it "parses 'month' since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.month.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "month" }
      end

      it "parses ISO timestamp" do
        timestamp = "2023-12-01T10:00:00Z"
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: Time.parse(timestamp)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: timestamp }
      end

      it "defaults to 1 week ago for invalid since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.week.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "invalid" }
      end
    end
  end

  describe "POST #add_expense" do
    let(:expense_params) do
      {
        amount: "25.50",
        description: "Coffee purchase",
        merchant_name: "Starbucks",
        transaction_date: "2023-12-01",
        category_id: category.id
      }
    end

    context "with valid parameters" do
      it "creates expense successfully" do
        expect {
          post :add_expense, params: { expense: expense_params }
        }.to change(Expense, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("success")
        expect(json_response["expense"]["amount"]).to eq(25.5)
        expect(json_response["expense"]["description"]).to eq("Coffee purchase")

        created_expense = Expense.last
        expect(created_expense.status).to eq("processed")
        expect(created_expense.email_account).to be_present
      end
    end

    context "with invalid parameters" do
      it "returns error for missing amount" do
        invalid_params = expense_params.except(:amount)

        post :add_expense, params: { expense: invalid_params }

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("error")
        expect(json_response["errors"]).to be_present
      end
    end

    context "when no active email account exists" do
      before do
        EmailAccount.update_all(active: false)
      end

      it "creates default manual account" do
        expect {
          post :add_expense, params: { expense: expense_params }
        }.to change(EmailAccount, :count).by(1)

        manual_account = EmailAccount.last
        expect(manual_account.provider).to eq("manual")
        expect(manual_account.email).to eq("manual@localhost")
        expect(manual_account.bank_name).to eq("Manual Entry")
        expect(manual_account.active).to be true

        created_expense = Expense.last
        expect(created_expense.email_account).to eq(manual_account)
      end
    end
  end

  describe "GET #recent_expenses" do
    let!(:expense1) { create(:expense, transaction_date: 2.days.ago) }
    let!(:expense2) { create(:expense, transaction_date: 1.day.ago) }
    let!(:expense3) { create(:expense, transaction_date: Time.current) }

    it "returns recent expenses in descending order" do
      get :recent_expenses

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(json_response["expenses"]).to be_an(Array)

      # Should be ordered by recency
      expense_ids = json_response["expenses"].map { |e| e["id"] }
      expect(expense_ids.first).to eq(expense3.id)
    end

    it "respects limit parameter" do
      get :recent_expenses, params: { limit: 2 }

      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to eq(2)
    end

    it "uses default limit of 10 for invalid limit" do
      get :recent_expenses, params: { limit: 0 }

      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to be <= 10
    end

    it "caps limit at 50" do
      get :recent_expenses, params: { limit: 100 }

      json_response = JSON.parse(response.body)
      expect(json_response["expenses"].size).to be <= 50
    end

    it "formats expense data correctly" do
      get :recent_expenses

      json_response = JSON.parse(response.body)
      expense_data = json_response["expenses"].first

      expect(expense_data).to have_key("id")
      expect(expense_data).to have_key("amount")
      expect(expense_data).to have_key("formatted_amount")
      expect(expense_data).to have_key("description")
      expect(expense_data).to have_key("merchant_name")
      expect(expense_data).to have_key("transaction_date")
      expect(expense_data).to have_key("category")
      expect(expense_data).to have_key("bank_name")
      expect(expense_data).to have_key("status")
      expect(expense_data).to have_key("created_at")
    end
  end

  describe "GET #expense_summary" do
    before do
      # Mock the service
      summary_service = double("ExpenseSummaryService")
      allow(ExpenseSummaryService).to receive(:new).and_return(summary_service)
      allow(summary_service).to receive(:period).and_return("month")
      allow(summary_service).to receive(:summary).and_return({
        total_amount: 1250.00,
        expense_count: 45,
        average_amount: 27.78,
        categories: { "Food" => 450.00, "Transport" => 200.00 }
      })
    end

    it "returns expense summary" do
      get :expense_summary, params: { period: "month" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(json_response["period"]).to eq("month")
      expect(json_response["summary"]).to be_present
      expect(json_response["summary"]["total_amount"]).to eq(1250.00)
    end

    it "passes period parameter to service" do
      expect(ExpenseSummaryService).to receive(:new).with("week")

      get :expense_summary, params: { period: "week" }
    end
  end

  describe "authentication" do
    context "without Authorization header" do
      before do
        request.headers["Authorization"] = nil
      end

      it "returns unauthorized error" do
        post :process_emails

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Missing API token")
      end
    end

    context "with invalid token" do
      before do
        allow(ApiToken).to receive(:authenticate).and_return(nil)
      end

      it "returns unauthorized error" do
        post :process_emails

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid or expired API token")
      end
    end

    context "with valid token" do
      it "sets @current_api_token" do
        post :process_emails

        expect(controller.instance_variable_get(:@current_api_token)).to eq(api_token)
      end
    end
  end

  describe "private methods" do
    describe "#parse_since_parameter" do
      it "defaults to 1 week ago when no since parameter" do
        controller.params = ActionController::Parameters.new({})
        result = controller.send(:parse_since_parameter)
        expect(result).to be_within(1.minute).of(1.week.ago)
      end
    end

    describe "#default_email_account" do
      context "when active account exists" do
        let!(:active_account) { create(:email_account, active: true) }

        it "returns first active account" do
          result = controller.send(:default_email_account)
          expect(result).to eq(active_account)
        end
      end

      context "when no active account exists" do
        before do
          EmailAccount.update_all(active: false)
        end

        it "creates and returns default manual account" do
          expect {
            result = controller.send(:default_email_account)
            expect(result.provider).to eq("manual")
            expect(result.active).to be true
          }.to change(EmailAccount, :count).by(1)
        end
      end
    end

    describe "#format_expense" do
      let(:expense) { create(:expense, amount: 25.50, description: "Test expense") }

      it "formats expense data correctly" do
        result = controller.send(:format_expense, expense)

        expect(result[:id]).to eq(expense.id)
        expect(result[:amount]).to eq(25.5)
        expect(result[:description]).to be_present
        expect(result[:transaction_date]).to match(/\d{4}-\d{2}-\d{2}T/)
        expect(result[:created_at]).to match(/\d{4}-\d{2}-\d{2}T/)
      end
    end
  end
end
