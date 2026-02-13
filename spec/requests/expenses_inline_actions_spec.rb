require "rails_helper"

RSpec.describe "Expenses Inline Actions API", type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }

  before { sign_in_admin(admin_user) }
  let!(:category) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:new_category) { create(:category, name: "Transport", color: "#4ECDC4") }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category,
      status: "pending",
      merchant_name: "Test Restaurant",
      amount: 5000
    )
  end

  describe "POST /expenses/:id/correct_category" do
    it "updates expense category successfully" do
      post correct_category_expense_path(expense),
           params: { category_id: new_category.id },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["expense"]["category"]["id"]).to eq(new_category.id)
      expect(json["color"]).to eq(new_category.color)

      expense.reload
      expect(expense.category_id).to eq(new_category.id)
    end

    it "returns error for invalid category" do
      post correct_category_expense_path(expense),
           params: { category_id: 999999 },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)

      json = JSON.parse(response.body)
      expect(json["success"]).to be false
      expect(json["error"]).to include("Invalid category")
    end

    it "returns error when category_id is missing" do
      post correct_category_expense_path(expense),
           params: {},
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)

      json = JSON.parse(response.body)
      expect(json["success"]).to be false
      expect(json["error"]).to include("Category ID required")
    end
  end

  describe "PATCH /expenses/:id/update_status" do
    it "toggles status from pending to processed" do
      patch update_status_expense_path(expense),
            params: { status: "processed" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["expense"]["status"]).to eq("processed")

      expense.reload
      expect(expense.status).to eq("processed")
    end

    it "toggles status from processed to pending" do
      expense.update!(status: "processed")

      patch update_status_expense_path(expense),
            params: { status: "pending" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["expense"]["status"]).to eq("pending")

      expense.reload
      expect(expense.status).to eq("pending")
    end

    it "returns error for invalid status" do
      patch update_status_expense_path(expense),
            params: { status: "invalid_status" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)

      json = JSON.parse(response.body)
      expect(json["success"]).to be false
      expect(json["error"]).to include("Invalid status")
    end
  end

  describe "POST /expenses/:id/duplicate" do
    it "creates a duplicate expense" do
      expect {
        post duplicate_expense_path(expense),
             headers: { "Accept" => "application/json" }
      }.to change(Expense, :count).by(1)

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["expense"]["merchant_name"]).to eq(expense.merchant_name)
      expect(json["expense"]["amount"]).to eq(expense.amount.to_f.to_s)

      # New expense should have pending status
      new_expense = Expense.find(json["expense"]["id"])
      expect(new_expense.status).to eq("pending")
      expect(new_expense.transaction_date).to eq(Date.current)
    end

    it "resets ML fields on duplicate" do
      expense.update!(
        ml_confidence: 0.95,
        ml_suggested_category_id: category.id,
        ml_confidence_explanation: "High confidence",
        ml_correction_count: 3
      )

      post duplicate_expense_path(expense),
           headers: { "Accept" => "application/json" }

      json = JSON.parse(response.body)
      new_expense = Expense.find(json["expense"]["id"])

      expect(new_expense.ml_confidence).to be_nil
      expect(new_expense.ml_suggested_category_id).to be_nil
      expect(new_expense.ml_confidence_explanation).to be_nil
      expect(new_expense.ml_correction_count).to eq(0)
    end
  end

  describe "DELETE /expenses/:id" do
    it "deletes expense successfully" do
      expect {
        delete expense_path(expense),
               headers: { "Accept" => "application/json" }
      }.to change(Expense, :count).by(-1)

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["message"]).to include("eliminado exitosamente")

      expect(Expense.find_by(id: expense.id)).to be_nil
    end

    it "returns 404 for non-existent expense" do
      delete expense_path(999999),
             headers: { "Accept" => "application/json" }

      expect(response).to redirect_to(expenses_path)
      follow_redirect!
      expect(response.body).to include("Gasto no encontrado")
    end
  end

  describe "Response format" do
    it "returns proper JSON structure for category correction" do
      post correct_category_expense_path(expense),
           params: { category_id: new_category.id },
           headers: { "Accept" => "application/json" }

      json = JSON.parse(response.body)

      expect(json).to have_key("success")
      expect(json).to have_key("expense")
      expect(json).to have_key("color")

      expect(json["expense"]).to have_key("id")
      expect(json["expense"]).to have_key("amount")
      expect(json["expense"]).to have_key("category")
      expect(json["expense"]).to have_key("ml_confidence")
    end

    it "returns proper JSON structure for status update" do
      patch update_status_expense_path(expense),
            params: { status: "processed" },
            headers: { "Accept" => "application/json" }

      json = JSON.parse(response.body)

      expect(json).to have_key("success")
      expect(json).to have_key("expense")
      expect(json["expense"]).to have_key("status")
    end
  end

  describe "Performance" do
    it "completes category update quickly" do
      start_time = Time.now

      post correct_category_expense_path(expense),
           params: { category_id: new_category.id },
           headers: { "Accept" => "application/json" }

      end_time = Time.now
      response_time = (end_time - start_time) * 1000

      # Should complete within 100ms
      expect(response_time).to be < 100
      expect(response).to have_http_status(:success)
    end

    it "completes status update quickly" do
      start_time = Time.now

      patch update_status_expense_path(expense),
            params: { status: "processed" },
            headers: { "Accept" => "application/json" }

      end_time = Time.now
      response_time = (end_time - start_time) * 1000

      # Should complete within 100ms
      expect(response_time).to be < 100
      expect(response).to have_http_status(:success)
    end
  end
end
