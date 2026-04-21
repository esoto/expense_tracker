# frozen_string_literal: true

require "rails_helper"

# PER-277: Unique partial index on expenses for duplicate detection.
# Verifies that the unique constraint on
# (email_account_id, amount, transaction_date, merchant_name)
# WHERE deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NOT NULL
# correctly prevents duplicate active expenses while allowing:
# - soft-deleted records
# - NULL merchant_name (manual expenses without merchant)
# - different amounts or merchants
#
# PER-498 (B8): companion partial unique index idx_expenses_manual_duplicate_check
# now also dedupes manual expenses (email_account_id IS NULL).
#
# Tagged :unit so the pre-commit hook includes it.

RSpec.describe "PER-277 Duplicate expense unique constraint", :unit do
  let(:connection) { ActiveRecord::Base.connection }
  let(:email_account) { create(:email_account) }
  let(:transaction_date) { Time.zone.parse("2026-03-15 10:00:00") }
  let(:amount) { 50.00 }
  let(:merchant) { "Walmart" }

  def insert_expense(attrs = {})
    defaults = {
      user_id: email_account.user_id,
      email_account_id: email_account.id,
      amount: amount,
      transaction_date: transaction_date,
      merchant_name: merchant,
      merchant_normalized: merchant,
      description: "Test expense",
      currency: 0,
      status: 0,
      bank_name: "BAC",
      created_at: Time.current,
      updated_at: Time.current
    }
    merged = defaults.merge(attrs)
    columns = merged.keys.join(", ")
    values = merged.values.map { |v| connection.quote(v) }.join(", ")
    connection.execute("INSERT INTO expenses (#{columns}) VALUES (#{values})")
  end

  describe "index properties" do
    it "has a unique partial index named idx_expenses_duplicate_check" do
      idx = connection.indexes(:expenses).find { |i| i.name == "idx_expenses_duplicate_check" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be true
      expect(idx.columns).to eq(%w[email_account_id amount transaction_date merchant_name])
      expect(idx.where).to include("deleted_at IS NULL")
      expect(idx.where).to include("merchant_name IS NOT NULL")
      expect(idx.where).to include("email_account_id IS NOT NULL")
    end
  end

  describe "constraint enforcement" do
    it "prevents inserting two active expenses with same key columns" do
      insert_expense
      expect {
        insert_expense
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows inserting when existing record is soft-deleted" do
      insert_expense(deleted_at: Time.current)
      expect {
        insert_expense
      }.not_to raise_error
    end

    it "allows inserting when merchant_name is NULL (excluded from index)" do
      insert_expense(merchant_name: nil, merchant_normalized: nil)
      expect {
        insert_expense(merchant_name: nil, merchant_normalized: nil)
      }.not_to raise_error
    end

    it "allows different amounts for same account/date/merchant" do
      insert_expense(amount: 50.00)
      expect {
        insert_expense(amount: 75.00)
      }.not_to raise_error
    end

    it "allows different merchants for same account/date/amount" do
      insert_expense(merchant_name: "Walmart", merchant_normalized: "Walmart")
      expect {
        insert_expense(merchant_name: "Target", merchant_normalized: "Target")
      }.not_to raise_error
    end
  end

  # PER-498 (B8): manual-expense duplicate check — email_account_id IS NULL
  describe "manual-expense partial index (PER-498)" do
    it "has a unique partial index named idx_expenses_manual_duplicate_check" do
      idx = connection.indexes(:expenses).find { |i| i.name == "idx_expenses_manual_duplicate_check" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be true
      expect(idx.columns).to eq(%w[amount transaction_date merchant_name])
      expect(idx.where).to include("deleted_at IS NULL")
      expect(idx.where).to include("merchant_name IS NOT NULL")
      expect(idx.where).to include("email_account_id IS NULL")
    end

    it "prevents inserting duplicate manual expenses (email_account_id IS NULL)" do
      insert_expense(email_account_id: nil)
      expect {
        insert_expense(email_account_id: nil)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows two manual rows with the same key if one is soft-deleted" do
      insert_expense(email_account_id: nil, deleted_at: Time.current)
      expect {
        insert_expense(email_account_id: nil)
      }.not_to raise_error
    end

    it "allows two manual rows when merchant_name is NULL (excluded from index)" do
      insert_expense(email_account_id: nil, merchant_name: nil, merchant_normalized: nil)
      expect {
        insert_expense(email_account_id: nil, merchant_name: nil, merchant_normalized: nil)
      }.not_to raise_error
    end

    it "allows a manual row to coexist with an email-account row at the same tuple" do
      # Manual (email_account_id IS NULL) and email-linked (email_account_id = N)
      # rows are disjoint in each partial index, so the same (amount, date,
      # merchant) can exist in both.
      insert_expense
      expect {
        insert_expense(email_account_id: nil)
      }.not_to raise_error
    end

    it "allows different amounts for manual rows" do
      insert_expense(email_account_id: nil, amount: 50.00)
      expect {
        insert_expense(email_account_id: nil, amount: 75.00)
      }.not_to raise_error
    end
  end
end
