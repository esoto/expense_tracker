# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Expenses Bulk Destroy", :unit, type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }
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

      # PER-208: undo_id must not be null in bulk_destroy JSON response
      it "returns a non-null undo_id in the JSON response", :unit do
        delete bulk_destroy_expenses_path,
               params: { expense_ids: [ expense1.id, expense2.id ] },
               headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["undo_id"]).not_to be_nil,
          "Expected undo_id to be present but got nil — PER-208 regression"
      end

      it "returns an undo_id that matches the created UndoHistory record", :unit do
        expect {
          delete bulk_destroy_expenses_path,
                 params: { expense_ids: [ expense1.id, expense2.id ] },
                 headers: { "Accept" => "application/json" }
        }.to change(UndoHistory, :count).by(1)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        undo_record = UndoHistory.last
        expect(json["undo_id"]).to eq(undo_record.id),
          "Expected undo_id #{json['undo_id'].inspect} to match UndoHistory##{undo_record.id}"
      end
    end
  end
end
