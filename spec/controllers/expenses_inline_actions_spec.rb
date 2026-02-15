require 'rails_helper'

RSpec.describe ExpensesController, type: :controller, integration: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:new_category) { create(:category, name: "New Category") }
  let(:expense) { create(:expense, email_account: email_account, category: category, status: "pending") }

  before do
    # Mock authentication and authorization
    allow(controller).to receive(:authenticate_user!)
    allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))
  end

  describe "PATCH #update_status", integration: true do
    context "with valid status" do
      it "updates the expense status from pending to processed" do
        patch :update_status, params: { id: expense.id, status: "processed" }
        expense.reload
        expect(expense.status).to eq("processed")
      end

      it "updates the expense status from processed to pending" do
        expense.update!(status: "processed")
        patch :update_status, params: { id: expense.id, status: "pending" }
        expense.reload
        expect(expense.status).to eq("pending")
      end

      it "returns success JSON response" do
        patch :update_status, params: { id: expense.id, status: "processed" }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be true
        expect(json_response["expense"]["id"]).to eq(expense.id)
      end

      it "responds with turbo stream for turbo requests" do
        patch :update_status, params: { id: expense.id, status: "processed" }, format: :turbo_stream
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "with invalid status" do
      it "rejects invalid status values" do
        patch :update_status, params: { id: expense.id, status: "invalid" }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Invalid status")
      end

      it "does not update the expense" do
        original_status = expense.status
        patch :update_status, params: { id: expense.id, status: "invalid" }
        expense.reload
        expect(expense.status).to eq(original_status)
      end
    end

    context "with authorization" do
      it "prevents updating expenses from other accounts" do
        other_account = create(:email_account)
        other_expense = create(:expense, email_account: other_account)

        patch :update_status, params: { id: other_expense.id, status: "processed" }
        expect(response).to redirect_to(expenses_path)
        expect(flash[:alert]).to include("no encontrado")
      end
    end
  end

  describe "POST #duplicate", integration: true do
    it "creates a duplicate of the expense" do
      # Ensure expense is created before measuring the change
      expense_id = expense.id
      expect {
        post :duplicate, params: { id: expense_id }
      }.to change(Expense, :count).by(1)
    end

    it "duplicates with correct attributes" do
      post :duplicate, params: { id: expense.id }
      duplicated = Expense.order(created_at: :desc).first

      expect(duplicated.amount).to eq(expense.amount)
      expect(duplicated.merchant_name).to eq(expense.merchant_name)
      expect(duplicated.description).to eq(expense.description)
      expect(duplicated.category_id).to eq(expense.category_id)
      expect(duplicated.email_account_id).to eq(expense.email_account_id)
    end

    it "resets certain attributes for the duplicate" do
      expense.update!(
        status: "processed",
        ml_confidence: 0.95,
        ml_suggested_category_id: new_category.id,
        ml_correction_count: 5
      )

      post :duplicate, params: { id: expense.id }
      duplicated = Expense.order(created_at: :desc).first

      expect(duplicated.transaction_date).to eq(Date.current)
      expect(duplicated.status).to eq("pending")
      expect(duplicated.ml_confidence).to be_nil
      expect(duplicated.ml_suggested_category_id).to be_nil
      expect(duplicated.ml_correction_count).to eq(0)
    end

    it "returns success JSON response" do
      post :duplicate, params: { id: expense.id }, format: :json
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to be true
      expect(json_response["expense"]["merchant_name"]).to eq(expense.merchant_name)
    end

    it "responds with turbo stream for turbo requests" do
      post :duplicate, params: { id: expense.id }, format: :turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end

    context "when duplication fails" do
      it "handles validation errors gracefully" do
        # Mock save to fail
        allow_any_instance_of(Expense).to receive(:save).and_return(false)

        post :duplicate, params: { id: expense.id }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
      end
    end

    context "with authorization" do
      it "prevents duplicating expenses from other accounts" do
        other_account = create(:email_account)
        other_expense = create(:expense, email_account: other_account)

        expect {
          post :duplicate, params: { id: other_expense.id }
        }.not_to change(Expense, :count)

        expect(response).to redirect_to(expenses_path)
      end
    end
  end


  describe "DELETE #destroy via inline actions", integration: true do
    it "deletes the expense" do
      expense # create the expense
      expect {
        delete :destroy, params: { id: expense.id }
      }.to change(Expense, :count).by(-1)
    end

    it "responds with turbo stream for AJAX requests" do
      delete :destroy, params: { id: expense.id }, format: :turbo_stream
      expect(response).to be_successful
    end

    context "with authorization" do
      it "prevents deleting expenses from other accounts" do
        other_account = create(:email_account)
        other_expense = create(:expense, email_account: other_account)

        expect {
          delete :destroy, params: { id: other_expense.id }
        }.not_to change(Expense, :count)

        expect(response).to redirect_to(expenses_path)
      end
    end
  end
end
