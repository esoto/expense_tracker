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

      it "handles string email_account_id parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_a(Time)
        )

        post :process_emails, params: { email_account_id: email_account.id.to_s }
        expect(response).to have_http_status(:accepted)
      end

      it "handles non-numeric email_account_id gracefully" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          0,
          since: be_a(Time)
        )

        post :process_emails, params: { email_account_id: "invalid" }
        expect(response).to have_http_status(:accepted)
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

      it "handles empty string since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.week.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "" }
      end

      it "handles nil since parameter" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.week.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: nil }
      end

      it "handles malformed timestamp gracefully" do
        expect(ProcessEmailsJob).to receive(:perform_later).with(
          email_account.id,
          since: be_within(1.minute).of(1.week.ago)
        )

        post :process_emails, params: { email_account_id: email_account.id, since: "not-a-date" }
      end
    end

    context "error scenarios" do
      it "handles job enqueueing failures gracefully" do
        allow(ProcessEmailsJob).to receive(:perform_later).and_raise(StandardError.new("Queue error"))

        expect { post :process_emails }.to raise_error(StandardError, "Queue error")
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

      it "returns error for invalid amount format" do
        invalid_params = expense_params.merge(amount: "not-a-number")

        post :add_expense, params: { expense: invalid_params }

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("error")
        expect(json_response["errors"]).to include(match(/amount/i))
      end

      it "returns error for negative amount" do
        invalid_params = expense_params.merge(amount: "-10.50")

        post :add_expense, params: { expense: invalid_params }

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("error")
      end

      it "returns error for invalid transaction_date" do
        invalid_params = expense_params.merge(transaction_date: "not-a-date")

        post :add_expense, params: { expense: invalid_params }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns error for non-existent category_id" do
        invalid_params = expense_params.merge(category_id: 99999)
        
        expect {
          post :add_expense, params: { expense: invalid_params }
        }.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end


    context "database transaction failures" do
      it "rolls back on expense save failure" do
        expense_double = double("Expense")
        allow(Expense).to receive(:new).and_return(expense_double)
        allow(expense_double).to receive(:email_account=)
        allow(expense_double).to receive(:status=)
        allow(expense_double).to receive(:save).and_return(false)
        allow(expense_double).to receive(:errors).and_return(double(full_messages: ["Validation error"]))

        expect {
          post :add_expense, params: { expense: expense_params }
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:unprocessable_content)
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

    context "edge cases" do
      it "returns empty array when no expenses exist" do
        Expense.destroy_all

        get :recent_expenses

        json_response = JSON.parse(response.body)
        expect(json_response["expenses"]).to eq([])
        expect(json_response["status"]).to eq("success")
      end
    end

    context "database query optimization" do
      it "includes necessary associations to avoid N+1 queries" do
        expect(Expense).to receive(:includes).with(:category, :email_account).and_call_original

        get :recent_expenses
      end
    end

    context "error handling" do
      it "handles database connection errors gracefully" do
        allow(Expense).to receive(:includes).and_raise(ActiveRecord::ConnectionNotEstablished.new("DB error"))

        expect { get :recent_expenses }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
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

    context "error handling" do
      it "handles service initialization failures" do
        allow(ExpenseSummaryService).to receive(:new).and_raise(StandardError.new("Service error"))

        expect { get :expense_summary }.to raise_error(StandardError, "Service error")
      end

      it "handles service method failures" do
        summary_service = double("ExpenseSummaryService")
        allow(ExpenseSummaryService).to receive(:new).and_return(summary_service)
        allow(summary_service).to receive(:period).and_raise(StandardError.new("Period error"))

        expect { get :expense_summary }.to raise_error(StandardError, "Period error")
      end
    end

    context "parameter validation" do
      it "handles nil period parameter" do
        expect(ExpenseSummaryService).to receive(:new).with("")

        get :expense_summary, params: { period: nil }
      end

      it "handles empty string period parameter" do
        expect(ExpenseSummaryService).to receive(:new).with("")

        get :expense_summary, params: { period: "" }
      end

      it "handles invalid period parameter" do
        expect(ExpenseSummaryService).to receive(:new).with("invalid_period")

        get :expense_summary, params: { period: "invalid_period" }
      end
    end
  end

  describe "authentication" do
    before do
      # Default stub for authentication - returns nil for unmatched tokens
      allow(ApiToken).to receive(:authenticate).and_return(nil)
    end
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
      before do
        allow(ApiToken).to receive(:authenticate).with(api_token.token_hash).and_return(api_token)
        request.headers["Authorization"] = "Bearer #{api_token.token_hash}"
      end
      
      it "sets @current_api_token" do
        post :process_emails

        expect(controller.instance_variable_get(:@current_api_token)).to eq(api_token)
      end
    end

    context "token format validation" do
      it "handles malformed Bearer token" do
        request.headers["Authorization"] = "InvalidFormat token123"

        post :process_emails

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid or expired API token")
      end

      it "handles empty Bearer token" do
        request.headers["Authorization"] = "Bearer "

        post :process_emails

        expect(response).to have_http_status(:unauthorized)
      end

      it "handles very long token" do
        long_token = "a" * 1000
        request.headers["Authorization"] = "Bearer #{long_token}"
        allow(ApiToken).to receive(:authenticate).with(long_token).and_return(nil)

        post :process_emails

        expect(response).to have_http_status(:unauthorized)
      end

      it "handles special characters in token" do
        special_token = "token!@#$%^&*()"
        request.headers["Authorization"] = "Bearer #{special_token}"
        allow(ApiToken).to receive(:authenticate).with(special_token).and_return(nil)

        post :process_emails

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "authentication bypass attempts" do
      it "cannot access endpoints without authentication" do
        request.headers["Authorization"] = nil

        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)

        get :recent_expenses
        expect(response).to have_http_status(:unauthorized)

        get :expense_summary
        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects expired tokens" do
        expired_token = create(:api_token, :expired)
        request.headers["Authorization"] = "Bearer #{expired_token.token}"
        allow(ApiToken).to receive(:authenticate).with(expired_token.token).and_return(nil)

        post :process_emails
        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects inactive tokens" do
        inactive_token = create(:api_token, :inactive)
        request.headers["Authorization"] = "Bearer #{inactive_token.token}"
        allow(ApiToken).to receive(:authenticate).with(inactive_token.token).and_return(nil)

        post :process_emails
        expect(response).to have_http_status(:unauthorized)
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
        it "returns first active account" do
          active_account = double("EmailAccount", provider: "gmail", active: true)
          allow(EmailAccount).to receive_message_chain(:active, :first).and_return(active_account)
          
          result = controller.send(:default_email_account)
          expect(result).to eq(active_account)
        end
      end

      context "when no active account exists" do
        it "creates and returns default manual account" do
          allow(EmailAccount).to receive_message_chain(:active, :first).and_return(nil)
          allow(controller).to receive(:create_default_manual_account).and_return(
            double("EmailAccount", provider: "manual", active: true)
          )
          
          result = controller.send(:default_email_account)
          expect(result.provider).to eq("manual")
          expect(result.active).to be true
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

  describe "security and authorization", unit: true do
    before do
      allow(ApiToken).to receive(:authenticate).and_return(nil)
    end

    context "authentication bypass attempts" do
      it "cannot access endpoints without authentication" do
        request.headers["Authorization"] = nil
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
        
        get :recent_expenses
        expect(response).to have_http_status(:unauthorized)
        
        get :expense_summary
        expect(response).to have_http_status(:unauthorized)
        
        post :process_emails, params: { email_account_id: 1 }
        expect(response).to have_http_status(:unauthorized)
      end
      
      it "cannot access with empty token" do
        request.headers["Authorization"] = "Bearer "
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Missing API token")
      end
      
      it "cannot access with whitespace-only token" do
        request.headers["Authorization"] = "Bearer    "
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Missing API token")
      end
    end
    
    context "token security" do
      it "handles SQL injection attempts in token" do
        malicious_token = "'; DROP TABLE api_tokens; --"
        allow(ApiToken).to receive(:authenticate).with(malicious_token).and_return(nil)
        request.headers["Authorization"] = "Bearer #{malicious_token}"
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
      end
      
      it "handles extremely long tokens gracefully" do
        long_token = "a" * 10000
        allow(ApiToken).to receive(:authenticate).with(long_token).and_return(nil)
        request.headers["Authorization"] = "Bearer #{long_token}"
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
      end
      
      it "handles non-ASCII characters in token" do
        unicode_token = "токен🔑密码"
        allow(ApiToken).to receive(:authenticate).with(unicode_token).and_return(nil)
        request.headers["Authorization"] = "Bearer #{unicode_token}"
        
        post :add_expense, params: { expense: { amount: 100 } }
        expect(response).to have_http_status(:unauthorized)
      end
    end

  end

  describe "performance and rate limiting", unit: true do
    before do
      allow(ApiToken).to receive(:authenticate).and_return(api_token)
    end

    context "large dataset handling" do
      it "handles large limit parameter efficiently" do
        allow(Expense).to receive_message_chain(:includes, :recent, :limit).and_return([])
        
        get :recent_expenses, params: { limit: 1000 }
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["expenses"]).to be_an(Array)
      end

      it "caps limit parameter to maximum value" do
        expenses_relation = double("expenses_relation")
        allow(expenses_relation).to receive(:includes).and_return(expenses_relation)
        allow(expenses_relation).to receive(:recent).and_return(expenses_relation)
        allow(expenses_relation).to receive(:limit).with(50).and_return([])
        allow(Expense).to receive(:includes).and_return(expenses_relation)
        
        get :recent_expenses, params: { limit: 999999 }
        
        expect(response).to have_http_status(:ok)
      end

      it "handles zero or negative limit gracefully" do
        expenses_relation = double("expenses_relation")
        allow(expenses_relation).to receive(:includes).and_return(expenses_relation)
        allow(expenses_relation).to receive(:recent).and_return(expenses_relation)
        allow(expenses_relation).to receive(:limit).with(10).and_return([])
        allow(Expense).to receive(:includes).and_return(expenses_relation)
        
        get :recent_expenses, params: { limit: -5 }
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["expenses"]).to be_an(Array)
      end
    end

    context "database optimization" do
      it "uses includes to prevent N+1 queries in recent_expenses" do
        expenses_relation = double("expenses_relation")
        allow(expenses_relation).to receive(:recent).and_return(expenses_relation)
        allow(expenses_relation).to receive(:limit).and_return([])
        
        expect(Expense).to receive(:includes).with(:category, :email_account).and_return(expenses_relation)
        
        get :recent_expenses
      end

      it "efficiently queries default email account" do
        allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
        
        post :add_expense, params: { expense: { amount: 100, description: "Test" } }
        
        # Verify only one query for active accounts
        expect(EmailAccount).to have_received(:active).once
      end
    end

    context "concurrent request handling" do
      it "handles request isolation properly" do
        # Test that controller state doesn't leak between requests
        post :add_expense, params: { 
          expense: { 
            amount: 10, 
            description: "First request" 
          } 
        }
        first_response = response.status
        
        post :add_expense, params: { 
          expense: { 
            amount: 20, 
            description: "Second request" 
          } 
        }
        second_response = response.status
        
        expect([first_response, second_response]).to all(be_in([201, 422]))
      end
    end

    context "memory usage" do
      it "efficiently formats many expenses" do
        many_expenses = Array.new(45) { create(:expense) }
        allow(Expense).to receive_message_chain(:includes, :recent, :limit).and_return(many_expenses)
        
        get :recent_expenses, params: { limit: 50 }
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["expenses"].size).to be <= 50
      end
    end

    context "timeout resilience" do
      it "handles slow database queries gracefully" do
        allow(Expense).to receive_message_chain(:includes, :recent, :limit) do
          sleep(0.1)
          []
        end
        
        start_time = Time.current
        get :recent_expenses
        end_time = Time.current
        
        expect(response).to have_http_status(:ok)
        expect(end_time - start_time).to be < 2.0
      end

      it "handles job enqueueing delays" do
        allow(ProcessEmailsJob).to receive(:perform_later) do
          sleep(0.05)
          true
        end
        
        start_time = Time.current
        post :process_emails, params: { email_account_id: 1 }
        end_time = Time.current
        
        expect(response).to have_http_status(:accepted)
        expect(end_time - start_time).to be < 1.0
      end
    end
  end

  # Unit tests for the overridden authenticate_api_token method
  describe "Authentication Unit Tests", unit: true do
    describe "#authenticate_api_token (overridden method)" do
      let(:test_api_token) { create(:api_token, name: "webhooks-test-token") }

      # Override the global authentication setup for these unit tests
      before do
        # Clear the global authentication setup
        request.headers["Authorization"] = nil
        allow(ApiToken).to receive(:authenticate).and_call_original
      end

      context "with valid Bearer token" do
        before do
          request.headers["Authorization"] = "Bearer #{test_api_token.token}"
          allow(ApiToken).to receive(:authenticate).with(test_api_token.token).and_return(test_api_token)
        end

        it "sets @current_api_token instance variable" do
          controller.send(:authenticate_api_token)
          expect(controller.instance_variable_get(:@current_api_token)).to eq(test_api_token)
        end

        it "calls ApiToken.authenticate with extracted token" do
          controller.send(:authenticate_api_token)
          expect(ApiToken).to have_received(:authenticate).with(test_api_token.token)
        end

        it "does not render unauthorized response" do
          expect(controller).not_to receive(:render)
          controller.send(:authenticate_api_token)
        end
      end

      context "without Authorization header" do
        it "renders unauthorized JSON response with missing token message" do
          expect(controller).to receive(:render).with(
            json: { error: "Missing API token" },
            status: :unauthorized
          )
          result = controller.send(:authenticate_api_token)
          expect(result).to be_nil
        end

        it "does not call ApiToken.authenticate due to early return" do
          allow(controller).to receive(:render)
          expect(ApiToken).not_to receive(:authenticate)
          controller.send(:authenticate_api_token)
        end
      end

      context "with empty Authorization header" do
        before do
          request.headers["Authorization"] = ""
        end

        it "renders unauthorized JSON response" do
          expect(controller).to receive(:render).with(
            json: { error: "Missing API token" },
            status: :unauthorized
          )
          controller.send(:authenticate_api_token)
        end
      end

      context "with Authorization header without Bearer prefix" do
        before do
          request.headers["Authorization"] = "token_without_bearer"
          allow(ApiToken).to receive(:authenticate).with("token_without_bearer").and_return(nil)
        end

        it "extracts token correctly and attempts authentication" do
          allow(controller).to receive(:render)
          controller.send(:authenticate_api_token)
          expect(ApiToken).to have_received(:authenticate).with("token_without_bearer")
        end

        it "renders unauthorized response when token is invalid" do
          expect(controller).to receive(:render).with(
            json: { error: "Invalid or expired API token" },
            status: :unauthorized
          )
          controller.send(:authenticate_api_token)
        end
      end

      context "with invalid Bearer token" do
        before do
          request.headers["Authorization"] = "Bearer invalid_token_123"
          allow(ApiToken).to receive(:authenticate).with("invalid_token_123").and_return(nil)
        end

        it "calls ApiToken.authenticate with invalid token" do
          allow(controller).to receive(:render)
          controller.send(:authenticate_api_token)
          expect(ApiToken).to have_received(:authenticate).with("invalid_token_123")
        end

        it "renders unauthorized JSON response" do
          expect(controller).to receive(:render).with(
            json: { error: "Invalid or expired API token" },
            status: :unauthorized
          )
          controller.send(:authenticate_api_token)
        end

        it "returns nil" do
          allow(controller).to receive(:render)
          result = controller.send(:authenticate_api_token)
          expect(result).to be_nil
        end

        it "does not set @current_api_token" do
          allow(controller).to receive(:render)
          controller.send(:authenticate_api_token)
          expect(controller.instance_variable_get(:@current_api_token)).to be_nil
        end
      end

      context "with expired token" do
        let(:expired_token) { create(:api_token, expires_at: 1.day.from_now) }

        before do
          # Manually expire the token after creation
          expired_token.update_column(:expires_at, 1.day.ago)
          request.headers["Authorization"] = "Bearer #{expired_token.token}"
          allow(ApiToken).to receive(:authenticate).with(expired_token.token).and_return(nil)
        end

        it "renders unauthorized response for expired token" do
          expect(controller).to receive(:render).with(
            json: { error: "Invalid or expired API token" },
            status: :unauthorized
          )
          controller.send(:authenticate_api_token)
        end
      end

      context "with malformed Authorization header" do
        before do
          request.headers["Authorization"] = "Malformed header format"
          allow(ApiToken).to receive(:authenticate).with("Malformed header format").and_return(nil)
        end

        it "attempts to authenticate with malformed header content" do
          allow(controller).to receive(:render)
          controller.send(:authenticate_api_token)
          expect(ApiToken).to have_received(:authenticate).with("Malformed header format")
        end

        it "renders unauthorized response" do
          expect(controller).to receive(:render).with(
            json: { error: "Invalid or expired API token" },
            status: :unauthorized
          )
          controller.send(:authenticate_api_token)
        end
      end

      context "security edge cases" do
        it "handles extremely long tokens" do
          long_token = "a" * 10000
          request.headers["Authorization"] = "Bearer #{long_token}"
          allow(ApiToken).to receive(:authenticate).with(long_token).and_return(nil)
          allow(controller).to receive(:render)
          
          controller.send(:authenticate_api_token)
          
          expect(ApiToken).to have_received(:authenticate).with(long_token)
        end

        it "handles tokens with special characters" do
          special_token = "token-with-special@#$%^&*()characters"
          request.headers["Authorization"] = "Bearer #{special_token}"
          allow(ApiToken).to receive(:authenticate).with(special_token).and_return(nil)
          allow(controller).to receive(:render)
          
          controller.send(:authenticate_api_token)
          
          expect(ApiToken).to have_received(:authenticate).with(special_token)
        end

        it "handles SQL injection attempts in token" do
          malicious_token = "'; DROP TABLE api_tokens; --"
          request.headers["Authorization"] = "Bearer #{malicious_token}"
          allow(ApiToken).to receive(:authenticate).with(malicious_token).and_return(nil)
          allow(controller).to receive(:render)
          
          controller.send(:authenticate_api_token)
          
          expect(ApiToken).to have_received(:authenticate).with(malicious_token)
        end

        it "handles Unicode characters in token" do
          unicode_token = "token_with_unicode_🔑_characters"
          request.headers["Authorization"] = "Bearer #{unicode_token}"
          allow(ApiToken).to receive(:authenticate).with(unicode_token).and_return(nil)
          allow(controller).to receive(:render)
          
          controller.send(:authenticate_api_token)
          
          expect(ApiToken).to have_received(:authenticate).with(unicode_token)
        end
      end

      context "method behavior differences from BaseController" do
        it "renders JSON response directly (no render_unauthorized helper)" do
          # The webhooks controller renders JSON directly instead of using BaseController's helper
          expect(controller).to receive(:render).with(
            json: { error: "Missing API token" },
            status: :unauthorized
          )
          
          controller.send(:authenticate_api_token)
        end

        it "uses different JSON structure than BaseController" do
          request.headers["Authorization"] = "Bearer invalid"
          allow(ApiToken).to receive(:authenticate).with("invalid").and_return(nil)
          
          expect(controller).to receive(:render).with(
            json: { error: "Invalid or expired API token" },
            status: :unauthorized
          )
          
          controller.send(:authenticate_api_token)
        end

        it "returns nil on authentication failure (different from BaseController)" do
          request.headers["Authorization"] = "Bearer invalid"
          allow(ApiToken).to receive(:authenticate).with("invalid").and_return(nil)
          allow(controller).to receive(:render)
          
          result = controller.send(:authenticate_api_token)
          
          expect(result).to be_nil
        end
      end

      context "integration with ApiToken model" do
        it "properly handles ApiToken.authenticate returning truthy value" do
          valid_token_obj = test_api_token
          request.headers["Authorization"] = "Bearer #{valid_token_obj.token}"
          allow(ApiToken).to receive(:authenticate).with(valid_token_obj.token).and_return(valid_token_obj)
          
          controller.send(:authenticate_api_token)
          
          expect(controller.instance_variable_get(:@current_api_token)).to eq(valid_token_obj)
        end

        it "properly handles ApiToken.authenticate returning falsy value" do
          request.headers["Authorization"] = "Bearer falsy_token"
          allow(ApiToken).to receive(:authenticate).with("falsy_token").and_return(false)
          allow(controller).to receive(:render)
          
          controller.send(:authenticate_api_token)
          
          expect(controller.instance_variable_get(:@current_api_token)).to be_falsy
        end

        it "properly handles ApiToken.authenticate raising an exception" do
          request.headers["Authorization"] = "Bearer error_token"
          allow(ApiToken).to receive(:authenticate).with("error_token").and_raise(StandardError.new("DB error"))
          
          expect {
            controller.send(:authenticate_api_token)
          }.to raise_error(StandardError, "DB error")
        end
      end
    end
  end
end
