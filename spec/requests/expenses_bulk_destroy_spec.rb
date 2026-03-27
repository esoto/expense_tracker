# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Expenses Bulk Destroy", :unit, type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }
  let!(:expense1) do
    create(:expense, email_account: email_account, merchant_name: "Merchant A", amount: 1000)
  end
  let!(:expense2) do
    create(:expense, email_account: email_account, merchant_name: "Merchant B", amount: 2000)
  end

  before { sign_in_admin(admin_user) }

  describe "DELETE /expenses/bulk_destroy" do
    context "when expense_ids is empty array" do
      it "returns 422 with user-friendly error message instead of 500", :unit do
        delete bulk_destroy_expenses_path,
               params: { expense_ids: [] },
               headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("Debes seleccionar al menos un gasto para eliminar.")
      end
    end

    context "when expense_ids param is missing (nil)" do
      it "returns 422 with user-friendly error message instead of 500", :unit do
        delete bulk_destroy_expenses_path,
               headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("Debes seleccionar al menos un gasto para eliminar.")
      end
    end

    context "with valid expense_ids" do
      it "deletes the given expenses and returns success", :unit do
        delete bulk_destroy_expenses_path,
               params: { expense_ids: [ expense1.id, expense2.id ] },
               headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["affected_count"]).to eq(2)
        expect(json["message"]).to be_present
      end

      it "does not return a 500 error", :unit do
        delete bulk_destroy_expenses_path,
               params: { expense_ids: [ expense1.id ] },
               headers: { "Accept" => "application/json" }

        expect(response).not_to have_http_status(:internal_server_error)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
