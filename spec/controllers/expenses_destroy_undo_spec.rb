# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpensesController, "#destroy undo integration", type: :controller, unit: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:expense) do
    create(:expense,
      email_account: email_account,
      category: category,
      merchant_name: "Supermercado Nacional",
      amount: 15_000,
      currency: :crc)
  end

  before do
    # Stub authentication and authorization
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:authorize_expense!).and_return(true)
    allow(controller).to receive(:current_user).and_return(nil)
    allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))
    allow(controller).to receive(:can_modify_expense?).and_return(true)
  end

  describe "soft delete behavior", unit: true do
    it "soft deletes the expense (sets deleted_at instead of removing)" do
      delete :destroy, params: { id: expense.id }

      # The expense should still exist in the database but be soft-deleted
      expect(Expense.with_deleted.find(expense.id).deleted_at).to be_present
    end

    it "does not permanently delete the expense record" do
      delete :destroy, params: { id: expense.id }

      # Record still exists when querying without default scope
      expect(Expense.with_deleted.where(id: expense.id).count).to eq(1)
    end

    it "excludes the expense from default scope after deletion" do
      delete :destroy, params: { id: expense.id }

      # Default scope should exclude the soft-deleted record
      expect(Expense.where(id: expense.id).count).to eq(0)
    end
  end

  describe "undo history creation", unit: true do
    it "creates an UndoHistory record for the deleted expense" do
      expect {
        delete :destroy, params: { id: expense.id }
      }.to change(UndoHistory, :count).by(1)
    end

    it "creates undo history with correct attributes" do
      delete :destroy, params: { id: expense.id }

      undo_entry = UndoHistory.last
      expect(undo_entry.undoable_type).to eq("Expense")
      expect(undo_entry.undoable_id).to eq(expense.id)
      expect(undo_entry.action_type).to eq("soft_delete")
      expect(undo_entry.record_data).to be_present
      expect(undo_entry.description).to include("Supermercado Nacional")
    end

    it "stores the expense attributes in record_data for restoration" do
      delete :destroy, params: { id: expense.id }

      undo_entry = UndoHistory.last
      expect(undo_entry.record_data["amount"].to_f).to eq(15_000.0)
      expect(undo_entry.record_data["currency"]).to eq("crc")
      expect(undo_entry.record_data["email_account_id"]).to eq(email_account.id)
    end

    it "sets an expiration time on the undo entry" do
      delete :destroy, params: { id: expense.id }

      undo_entry = UndoHistory.last
      expect(undo_entry.expires_at).to be_present
      expect(undo_entry.expires_at).to be > Time.current
    end

    it "marks the undo entry as pending (not undone)" do
      delete :destroy, params: { id: expense.id }

      undo_entry = UndoHistory.last
      expect(undo_entry.undone_at).to be_nil
      expect(undo_entry.expired_at).to be_nil
      expect(undo_entry).to be_undoable
    end
  end

  describe "HTML format response", unit: true do
    it "redirects to expenses index" do
      delete :destroy, params: { id: expense.id }

      expect(response).to redirect_to(expenses_url)
    end

    it "sets flash notice with undo message" do
      delete :destroy, params: { id: expense.id }

      expect(flash[:notice]).to eq("Gasto eliminado. Puedes deshacer esta acción.")
    end

    it "includes undo_id in flash for the view layer" do
      delete :destroy, params: { id: expense.id }

      expect(flash[:undo_id]).to be_present
      expect(flash[:undo_id]).to eq(UndoHistory.last.id)
    end

    it "includes undo_time_remaining in flash" do
      delete :destroy, params: { id: expense.id }

      expect(flash[:undo_time_remaining]).to be_a(Integer)
      expect(flash[:undo_time_remaining]).to be > 0
    end
  end

  describe "turbo_stream format response", unit: true do
    it "returns turbo_stream response with remove action" do
      delete :destroy, params: { id: expense.id }, format: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include("expense_row_#{expense.id}")
    end

    it "includes undo notification toast in turbo_stream response" do
      delete :destroy, params: { id: expense.id }, format: :turbo_stream

      expect(response.body).to include("toast-container")
      expect(response.body).to include("Gasto eliminado. Puedes deshacer esta acción.")
    end

    it "includes undo_id data attribute in toast element" do
      delete :destroy, params: { id: expense.id }, format: :turbo_stream

      undo_entry = UndoHistory.last
      expect(response.body).to include("data-undo-id='#{undo_entry.id}'")
    end
  end

  describe "JSON format response", unit: true do
    it "returns success with undo information" do
      delete :destroy, params: { id: expense.id }, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to eq(true)
      expect(json["message"]).to eq("Gasto eliminado. Puedes deshacer esta acción.")
    end

    it "includes undo_id in JSON response" do
      delete :destroy, params: { id: expense.id }, format: :json

      json = JSON.parse(response.body)
      expect(json["undo_id"]).to eq(UndoHistory.last.id)
    end

    it "includes undo_time_remaining in JSON response" do
      delete :destroy, params: { id: expense.id }, format: :json

      json = JSON.parse(response.body)
      expect(json["undo_time_remaining"]).to be_a(Integer)
      expect(json["undo_time_remaining"]).to be > 0
    end
  end

  describe "undo round-trip", unit: true do
    it "can restore a soft-deleted expense via UndoHistory#undo!" do
      delete :destroy, params: { id: expense.id }

      # Expense is soft-deleted
      expect(Expense.where(id: expense.id).count).to eq(0)

      # Undo the deletion
      undo_entry = UndoHistory.last
      result = undo_entry.undo!
      expect(result).to eq(true)

      # Expense is restored
      restored_expense = Expense.find(expense.id)
      expect(restored_expense).to be_present
      expect(restored_expense.deleted_at).to be_nil
      expect(restored_expense.amount.to_f).to eq(15_000.0)
    end

    it "marks the undo entry as undone after restoration" do
      delete :destroy, params: { id: expense.id }

      undo_entry = UndoHistory.last
      undo_entry.undo!

      undo_entry.reload
      expect(undo_entry.undone_at).to be_present
      expect(undo_entry).not_to be_undoable
    end
  end

  describe "edge cases", unit: true do
    context "when expense has no merchant_name" do
      let(:expense_no_merchant) do
        create(:expense,
          email_account: email_account,
          merchant_name: nil,
          description: "Unknown transaction")
      end

      it "creates undo history without error" do
        expect {
          delete :destroy, params: { id: expense_no_merchant.id }
        }.to change(UndoHistory, :count).by(1)
      end

      it "uses expense ID in undo description when merchant_name is nil" do
        delete :destroy, params: { id: expense_no_merchant.id }

        undo_entry = UndoHistory.last
        expect(undo_entry.description).to be_present
      end
    end

    context "when expense has no category" do
      let(:expense_no_category) do
        create(:expense, email_account: email_account, category: nil)
      end

      it "soft deletes and creates undo history successfully" do
        expect {
          delete :destroy, params: { id: expense_no_category.id }
        }.to change(UndoHistory, :count).by(1)

        expect(response).to redirect_to(expenses_url)
      end
    end

    context "when multiple expenses are deleted sequentially" do
      let(:expense2) do
        create(:expense,
          email_account: email_account,
          merchant_name: "Cafe Britt",
          amount: 5_000)
      end

      it "creates separate undo entries for each deletion" do
        delete :destroy, params: { id: expense.id }
        delete :destroy, params: { id: expense2.id }

        expect(UndoHistory.count).to eq(2)
        expect(UndoHistory.pending.count).to eq(2)
      end
    end
  end
end
