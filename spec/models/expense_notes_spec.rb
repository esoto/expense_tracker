# frozen_string_literal: true

require "rails_helper"

RSpec.describe Expense, type: :model, unit: true do
  describe "notes attribute (PER-182)" do
    let(:email_account) { create(:email_account) }

    it "accepts a notes value on create" do
      expense = Expense.new(
        amount: 500.0,
        currency: :crc,
        transaction_date: Date.current,
        status: :pending,
        user: email_account.user,
        email_account: email_account,
        notes: "Some note about this expense"
      )
      expect(expense).to be_valid
      expect(expense.notes).to eq("Some note about this expense")
    end

    it "persists notes to the database" do
      expense = create(:expense, email_account: email_account, notes: "Persisted note")
      reloaded = Expense.find(expense.id)
      expect(reloaded.notes).to eq("Persisted note")
    end

    it "allows notes to be nil" do
      expense = build(:expense, email_account: email_account, notes: nil)
      expect(expense).to be_valid
    end

    it "allows notes to be blank" do
      expense = build(:expense, email_account: email_account, notes: "")
      expect(expense).to be_valid
    end

    it "can update notes on an existing expense" do
      expense = create(:expense, email_account: email_account, notes: nil)
      expense.update!(notes: "Updated note")
      expect(expense.reload.notes).to eq("Updated note")
    end
  end
end
