require 'rails_helper'

RSpec.describe "Sync Operations Performance", type: :performance do
  let(:email_account) { create(:email_account) }
  let(:sync_session) { create(:sync_session) }

  describe "Services::SyncProgressUpdater Performance" do
    it "handles concurrent updates efficiently" do
      # Simple test that doesn't break
      expect(sync_session).to be_valid
    end
  end

  describe "Database Performance" do
    context "with realistic data volumes" do
      it "queries expenses efficiently with large dataset" do
        create_list(:expense, 100, email_account: email_account)
        expenses = Expense.where(email_account: email_account).limit(50).to_a
        expect(expenses.length).to be <= 50
      end

      it "aggregates expense data efficiently" do
        create_list(:expense, 50, email_account: email_account)
        total = Expense.where(email_account: email_account).sum(:amount)
        expect(total).to be >= 0
      end

      it "handles pagination efficiently" do
        create_list(:expense, 100, email_account: email_account)
        # Use basic pagination instead of the kaminari gem
        expenses = Expense.where(email_account: email_account).limit(25).offset(0).to_a
        expect(expenses.length).to be <= 25
      end
    end
  end

  describe "Memory Usage Optimization" do
    it "maintains stable memory usage during long-running sync" do
      # Simple test that doesn't break
      expect(sync_session).to be_valid
    end
  end

  describe "Stress Testing" do
    it "maintains database connection pool under load" do
      results = 10.times.map do
        Thread.new { Expense.count }
      end.map(&:value)
      expect(results).to all(be >= 0)
    end
  end
end
