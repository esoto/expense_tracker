# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Expenses notes (PER-182)", type: :request, unit: true do
  let(:admin_user) do
    AdminUser.create!(
      name: "Notes Test Admin",
      email: "notes-admin-#{SecureRandom.hex(4)}@test.com",
      password: "AdminPassword123!",
      role: "admin"
    )
  end
  let(:category) { create(:category) }

  before { sign_in_admin(admin_user) }

  describe "POST /expenses with notes field" do
    let(:valid_params) do
      {
        expense: {
          amount: "1500.00",
          currency: "crc",
          transaction_date: Date.current.to_s,
          merchant_name: "Super Mas",
          description: "Weekly groceries",
          notes: "Bought fruits and vegetables"
        }
      }
    end

    it "creates expense successfully when notes param is included" do
      expect {
        post expenses_path, params: valid_params
      }.to change(Expense, :count).by(1)
    end

    it "returns a redirect (not 500) when notes is submitted" do
      post expenses_path, params: valid_params
      expect(response).not_to have_http_status(:internal_server_error)
      expect(response).to have_http_status(:redirect)
    end

    it "persists the notes value" do
      post expenses_path, params: valid_params
      expense = Expense.last
      expect(expense.notes).to eq("Bought fruits and vegetables")
    end

    it "creates expense without notes (notes is optional)" do
      params_without_notes = valid_params.deep_dup
      params_without_notes[:expense].delete(:notes)

      expect {
        post expenses_path, params: params_without_notes
      }.to change(Expense, :count).by(1)

      expect(Expense.last.notes).to be_nil
    end
  end
end
