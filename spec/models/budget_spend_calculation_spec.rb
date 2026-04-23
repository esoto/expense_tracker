# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, "#calculate_current_spend! — new rules", type: :model, unit: true do
  let(:email_account) { create(:email_account) }
  let(:food)          { create(:category, name: "Food") }
  let(:transport)     { create(:category, name: "Transport") }

  def make_expense(**overrides)
    defaults = {
      email_account: email_account,
      transaction_date: Date.current.beginning_of_month + 3.days,
      currency: :crc,
      amount: 10_000,
      status: :processed
    }
    create(:expense, **defaults.merge(overrides))
  end

  it "returns 0 for inactive budget" do
    b = create(:budget, email_account: email_account, active: false)
    expect(b.calculate_current_spend!).to eq(0.0)
  end

  context "default category routing (expenses.budget_id IS NULL)" do
    it "counts expenses whose category is claimed" do
      b = create(:budget, email_account: email_account)
      b.categories << food
      make_expense(category: food, amount: 25_000)

      expect(b.calculate_current_spend!).to eq(25_000.0)
    end

    it "ignores expenses whose category is not claimed" do
      b = create(:budget, email_account: email_account)
      b.categories << food
      make_expense(category: transport, amount: 7_000)

      expect(b.calculate_current_spend!).to eq(0.0)
    end
  end

  context "per-expense override" do
    it "counts expenses assigned directly regardless of category" do
      b = create(:budget, email_account: email_account)
      make_expense(category: transport, amount: 9_000, budget: b)

      expect(b.calculate_current_spend!).to eq(9_000.0)
    end

    it "excludes expenses assigned to a different budget even if category matches" do
      ours  = create(:budget, email_account: email_account, name: "ours")
      ours.categories << food
      other = create(:budget, email_account: email_account, name: "other")
      make_expense(category: food, amount: 25_000, budget: other)

      expect(ours.calculate_current_spend!).to eq(0.0)
    end
  end

  context "overlapping categories across budgets" do
    it "counts the same expense in each overlapping budget (by design)" do
      a = create(:budget, email_account: email_account, name: "A")
      b = create(:budget, email_account: email_account, name: "B")
      a.categories << food
      b.categories << food
      make_expense(category: food, amount: 12_000)

      expect(a.calculate_current_spend!).to eq(12_000.0)
      expect(b.calculate_current_spend!).to eq(12_000.0)
    end
  end

  context "empty budget (no categories, no overrides)" do
    it "returns 0" do
      b = create(:budget, email_account: email_account)
      expect(b.calculate_current_spend!).to eq(0.0)
    end
  end
end
