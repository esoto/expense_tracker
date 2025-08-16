require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  let(:email_account) { create(:email_account) }
  let(:category1) { create(:category, name: "Food") }
  let(:category2) { create(:category, name: "Transport") }
  let(:expenses) do
    [
      create(:expense, email_account: email_account, category: nil, amount: 100),
      create(:expense, email_account: email_account, category: nil, amount: 200),
      create(:expense, email_account: email_account, category: category1, amount: 300)
    ]
  end

  describe "POST #bulk_categorize" do
    context "with valid parameters" do
      it "categorizes selected expenses" do
        expense_ids = expenses.map(&:id)

        post :bulk_categorize, params: {
          expense_ids: expense_ids,
          category_id: category2.id
        }, format: :json

        expect(response).to have_http_status(:success),
          "Expected success but got #{response.status}: #{response.body}"
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be true
        expect(json_response['affected_count']).to eq(3)

        # Verify expenses were updated
        expenses.each(&:reload)
        expect(expenses.all? { |e| e.category_id == category2.id }).to be true
      end
    end

    context "with invalid parameters" do
      it "returns error when no expenses provided" do
        post :bulk_categorize, params: {
          expense_ids: [],
          category_id: category2.id
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end

      it "returns error when category not found" do
        post :bulk_categorize, params: {
          expense_ids: expenses.map(&:id),
          category_id: 999999
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end
    end
  end

  describe "POST #bulk_update_status" do
    context "with valid parameters" do
      it "updates status of selected expenses" do
        expense_ids = expenses.map(&:id)

        post :bulk_update_status, params: {
          expense_ids: expense_ids,
          status: "processed"
        }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be true
        expect(json_response['affected_count']).to eq(3)

        # Verify expenses were updated
        expenses.each(&:reload)
        expect(expenses.all? { |e| e.status == "processed" }).to be true
      end
    end

    context "with invalid parameters" do
      it "returns error for invalid status" do
        post :bulk_update_status, params: {
          expense_ids: expenses.map(&:id),
          status: "invalid_status"
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end
    end
  end

  describe "DELETE #bulk_destroy" do
    context "with valid parameters" do
      it "deletes selected expenses" do
        expense_ids = expenses.map(&:id)
        initial_count = Expense.count

        delete :bulk_destroy, params: {
          expense_ids: expense_ids
        }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be true
        expect(json_response['affected_count']).to eq(3)
        expect(json_response['reload']).to be true

        # Verify expenses were deleted
        expect(Expense.count).to eq(initial_count - 3)
        expect(Expense.where(id: expense_ids).count).to eq(0)
      end
    end

    context "with empty expense list" do
      it "returns error" do
        delete :bulk_destroy, params: {
          expense_ids: []
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end
    end
  end
end
