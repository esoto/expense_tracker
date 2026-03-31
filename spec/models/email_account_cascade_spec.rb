# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailAccount, "cascade behavior on destroy", :unit, type: :model do
  let(:email_account) { create(:email_account) }

  describe "expense preservation" do
    it "nullifies expense email_account_id instead of destroying expenses" do
      expense = create(:expense, email_account: email_account, amount: 100, transaction_date: Time.current)
      expense_id = expense.id

      email_account.destroy!

      # Expense should still exist with nil email_account_id
      preserved = Expense.find_by(id: expense_id)
      expect(preserved).to be_present
      expect(preserved.email_account_id).to be_nil
    end

    it "preserves all expenses when account is deleted" do
      create_list(:expense, 3, email_account: email_account, transaction_date: Time.current)

      expect { email_account.destroy! }.not_to change(Expense, :count)
    end

    it "allows orphaned expenses to be updated without errors" do
      expense = create(:expense, email_account: email_account, amount: 100, transaction_date: Time.current)
      email_account.destroy!
      expense.reload

      expect { expense.update!(amount: 200) }.not_to raise_error
      expect(expense.reload.amount).to eq(200)
    end
  end
end
