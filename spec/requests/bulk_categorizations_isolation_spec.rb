# frozen_string_literal: true

require "rails_helper"

# Cross-tenant isolation contract for BulkCategorizationsController.
#
# BulkCategorizationsController is fully gated by UserAuthentication
# (require_authentication runs as a before_action on ApplicationController,
# with no skip in this controller), so current_user is guaranteed present
# before #load_uncategorized_expenses / #load_bulk_operation run. Both now
# scope through `for_user(current_user)` — this spec verifies user B can
# never see user A's uncategorized expenses or bulk operations.
RSpec.describe "BulkCategorizations data isolation", type: :request, unit: true do
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  let!(:email_account_a) { create(:email_account, user: user_a) }
  let!(:email_account_b) { create(:email_account, user: user_b) }

  describe "GET /bulk_categorizations (index)" do
    let!(:expense_a) { create(:expense, email_account: email_account_a, category: nil) }
    let!(:expense_b) { create(:expense, email_account: email_account_b, category: nil) }

    before do
      allow(Services::BulkCategorization::GroupingService).to receive(:new) do |expenses|
        double("GroupingService", group_by_similarity: [
          { expenses: expenses, confidence: 0.9, total_amount: expenses.sum(&:amount) }
        ])
      end
    end

    it "only exposes user_b's own uncategorized expenses to user_b" do
      sign_in_as(user_b)

      get bulk_categorizations_path(format: :json)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expense_ids = body.flat_map { |g| g["expenses"] }.map { |e| e["id"] }
      expect(expense_ids).to include(expense_b.id)
      expect(expense_ids).not_to include(expense_a.id)
    end

    it "still shows the owner their own uncategorized expenses (happy path)" do
      sign_in_as(user_a)

      get bulk_categorizations_path(format: :json)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expense_ids = body.flat_map { |g| g["expenses"] }.map { |e| e["id"] }
      expect(expense_ids).to include(expense_a.id)
      expect(expense_ids).not_to include(expense_b.id)
    end
  end

  describe "GET /bulk_categorizations/:id (show)" do
    let!(:expense_a) { create(:expense, email_account: email_account_a, category: nil) }
    let!(:bulk_operation_a) do
      operation = create(:bulk_operation, user: user_a, expense_count: 1, total_amount: expense_a.amount)
      create(:bulk_operation_item, bulk_operation: operation, expense: expense_a)
      operation
    end

    it "returns 404 when user_b tries to view user_a's bulk operation" do
      sign_in_as(user_b)

      get bulk_categorization_path(bulk_operation_a, format: :json)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 200 when the owner views their own bulk operation" do
      sign_in_as(user_a)

      get bulk_categorization_path(bulk_operation_a, format: :json)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(bulk_operation_a.id)
    end
  end
end
