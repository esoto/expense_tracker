# frozen_string_literal: true

require "rails_helper"

# Cross-tenant isolation contract for BulkCategorizationActionsController.
#
# BulkCategorizationActionsController is fully gated by UserAuthentication
# (require_authentication runs as a before_action on ApplicationController,
# with no skip in this controller), so current_user is guaranteed present
# before #set_expenses / #set_bulk_operation run. Both now scope through
# `for_user(current_user)`. #set_expenses is used by :categorize, a MUTATING
# action — this spec verifies user B cannot read or mutate user A's expenses
# via forged expense_ids, and cannot undo user A's bulk operation.
RSpec.describe "BulkCategorizationActions data isolation", type: :request, unit: true do
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  let!(:email_account_a) { create(:email_account, user: user_a) }
  let!(:email_account_b) { create(:email_account, user: user_b) }
  let!(:category) { create(:category) }
  let!(:expense_a) { create(:expense, email_account: email_account_a, category: nil) }

  describe "POST /bulk_categorizations/categorize" do
    it "does not let user_b categorize user_a's expense via a forged expense_ids param" do
      sign_in_as(user_b)

      expect {
        post bulk_categorizations_categorize_path, params: {
          expense_ids: [ expense_a.id ],
          category_id: category.id
        }, as: :json
      }.not_to change { expense_a.reload.category_id }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("No accessible expenses found")
    end

    it "lets the owner categorize their own expense (happy path)" do
      sign_in_as(user_a)

      post bulk_categorizations_categorize_path, params: {
        expense_ids: [ expense_a.id ],
        category_id: category.id
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(expense_a.reload.category_id).to eq(category.id)
    end

    it "returns a scoped-empty forbidden response for a mixed batch of own + another user's expenses" do
      expense_b = create(:expense, email_account: email_account_b, category: nil)
      sign_in_as(user_a)

      post bulk_categorizations_categorize_path, params: {
        expense_ids: [ expense_a.id, expense_b.id ],
        category_id: category.id
      }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(expense_a.reload.category_id).to be_nil
      expect(expense_b.reload.category_id).to be_nil
    end
  end

  describe "POST /bulk_categorizations/:id/undo" do
    let!(:bulk_operation_a) do
      operation = create(:bulk_operation, user: user_a, operation_type: :categorization,
                          status: :completed, expense_count: 1, total_amount: expense_a.amount)
      create(:bulk_operation_item, bulk_operation: operation, expense: expense_a, status: :completed)
      operation
    end

    it "returns 404 when user_b tries to undo user_a's bulk operation" do
      sign_in_as(user_b)

      post undo_bulk_categorization_path(bulk_operation_a), as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Operation not found")
      expect(bulk_operation_a.reload.status).to eq("completed")
    end

    it "lets the owner's request reach the undo service, unblocked by scoping (happy path)" do
      # NOTE: doesn't assert the undo actually succeeds — BulkOperation#undo!
      # has a pre-existing, unrelated bug (references an undefined `Current`
      # constant) that makes it always fail; out of scope for this IDOR fix.
      # This only asserts set_bulk_operation's for_user scoping doesn't block
      # the owner the way it correctly blocks a cross-tenant request above.
      sign_in_as(user_a)

      post undo_bulk_categorization_path(bulk_operation_a), as: :json

      expect(response).not_to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).not_to eq("Operation not found")
    end
  end

  describe "POST /bulk_categorizations/auto_categorize" do
    it "does not sweep another user's expenses into user_b's auto-categorization" do
      sign_in_as(user_b)

      # No filters → the broadest possible scope; user_a's uncategorized
      # expense must still be invisible to user_b's run.
      post "/bulk_categorizations/auto_categorize", params: { dry_run: "false" }, as: :json

      expect(expense_a.reload.category).to be_nil
    end
  end
end
