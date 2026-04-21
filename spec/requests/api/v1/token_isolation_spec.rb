# frozen_string_literal: true

require "rails_helper"

# PR 11 — Cross-user isolation contract
#
# Every /api/v1/* endpoint that returns user-owned data must return ONLY data
# belonging to the token's owner. Tokens from user_b must not leak user_a's data.
RSpec.describe "API token isolation (PR 11)", type: :request, unit: true do
  let(:user_a) { create(:user, :admin) }
  let(:user_b) { create(:user, :admin) }

  let(:token_a) { create(:api_token, user: user_a) }
  let(:token_b) { create(:api_token, user: user_b) }

  let(:headers_a) do
    { "Authorization" => "Bearer #{token_a.token}" }
  end

  let(:headers_b) do
    { "Authorization" => "Bearer #{token_b.token}" }
  end

  let(:json_headers_a) do
    { "Authorization" => "Bearer #{token_a.token}", "Content-Type" => "application/json" }
  end

  let(:email_account_a) { create(:email_account, user: user_a) }
  let(:email_account_b) { create(:email_account, user: user_b) }

  let!(:expense_a1) { create(:expense, user: user_a, email_account: email_account_a) }
  let!(:expense_a2) { create(:expense, user: user_a, email_account: email_account_a) }
  let!(:expense_b1) { create(:expense, user: user_b, email_account: email_account_b) }

  describe "GET /api/webhooks/recent_expenses" do
    it "returns only user_a's expenses for token_a" do
      get "/api/webhooks/recent_expenses", headers: headers_a

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      returned_ids = json["expenses"].map { |e| e["id"] }
      expect(returned_ids).to include(expense_a1.id, expense_a2.id)
      expect(returned_ids).not_to include(expense_b1.id)
    end

    it "returns only user_b's expenses for token_b" do
      get "/api/webhooks/recent_expenses", headers: headers_b

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      returned_ids = json["expenses"].map { |e| e["id"] }
      expect(returned_ids).to include(expense_b1.id)
      expect(returned_ids).not_to include(expense_a1.id, expense_a2.id)
    end
  end

  describe "GET /api/webhooks/expense_summary" do
    it "returns user_a's summary only for token_a" do
      get "/api/webhooks/expense_summary", headers: headers_a

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      # Summary should reflect only user_a's count
      expect(json["summary"]["expense_count"]).to eq(
        Expense.for_user(user_a).by_date_range(1.month.ago.beginning_of_day, Time.current.end_of_day).count
      )
    end
  end

  describe "POST /api/webhooks/process_emails" do
    # Use plain (non-JSON) headers so params are sent as form data — the
    # webhooks controller reads params, not a JSON body.
    it "allows processing own email account" do
      post "/api/webhooks/process_emails",
           params: { email_account_id: email_account_a.id },
           headers: headers_a

      expect(response).to have_http_status(:accepted)
    end

    it "returns 404 when trying to process another user's email account" do
      post "/api/webhooks/process_emails",
           params: { email_account_id: email_account_b.id },
           headers: headers_a

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "locked user token" do
    # locked_at: 5.minutes.ago is within LOCK_DURATION (30 min), so locked? returns true.
    # The :locked trait uses 1.hour.ago which exceeds the lock window (unlock_eligible? = true).
    let(:locked_user) { create(:user, :admin, locked_at: 5.minutes.ago, failed_login_attempts: 5) }
    let(:locked_token) { create(:api_token, user: locked_user) }
    let(:locked_headers) do
      { "Authorization" => "Bearer #{locked_token.token}" }
    end

    it "returns 401 for a locked user's token on webhooks endpoint" do
      get "/api/webhooks/recent_expenses", headers: locked_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a locked user's token on v1 patterns endpoint" do
      get "/api/v1/patterns", headers: locked_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "cross-user isolation on v1 patterns (global data)" do
    it "both tokens can read global category patterns" do
      get "/api/v1/patterns", headers: headers_a
      expect(response).to have_http_status(:ok)

      get "/api/v1/patterns", headers: headers_b
      expect(response).to have_http_status(:ok)
    end
  end
end
