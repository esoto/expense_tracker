# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Budgets::DedupSpend, type: :service, unit: true do
  let(:email_account) { create(:email_account) }
  let(:food)          { create(:category, name: "Food") }
  let(:rent)          { create(:category, name: "Rent") }

  def in_period(extra = {})
    {
      email_account: email_account,
      transaction_date: Date.current.beginning_of_month + 3.days,
      currency: :crc,
      amount: 10_000,
      status: :processed
    }.merge(extra)
  end

  it "returns 0.0 when given no budgets" do
    expect(described_class.call([])).to eq(0.0)
  end

  it "sums spend for a single budget's claimed category" do
    budget = create(:budget, email_account: email_account, amount: 100_000)
    budget.categories << food
    create(:expense, in_period(category: food, amount: 20_000))

    expect(described_class.call([ budget ])).to eq(20_000.0)
  end

  it "counts an override expense (expenses.budget_id set) even outside claimed categories" do
    budget = create(:budget, email_account: email_account, amount: 100_000)
    other_category = create(:category, name: "Other")
    create(:expense, in_period(category: other_category, amount: 12_000, budget: budget))

    expect(described_class.call([ budget ])).to eq(12_000.0)
  end

  it "does not double count an expense claimed by two overlapping budgets" do
    a = create(:budget, email_account: email_account, name: "A", amount: 100_000)
    b = create(:budget, email_account: email_account, name: "B", amount: 100_000)
    a.categories << food
    b.categories << food
    create(:expense, in_period(category: food, amount: 15_000))

    expect(described_class.call([ a, b ])).to eq(15_000.0)
  end

  it "sums distinct claimed-category expenses across non-overlapping budgets" do
    fixed_b = create(:budget, email_account: email_account, amount: 300_000)
    fixed_b.categories << rent
    gf_b = create(:budget, email_account: email_account, amount: 80_000)
    gf_b.categories << food

    create(:expense, in_period(category: rent, amount: 250_000))
    create(:expense, in_period(category: food, amount: 40_000))

    expect(described_class.call([ fixed_b, gf_b ])).to eq(290_000.0)
  end

  it "excludes expenses outside a budget's period range" do
    budget = create(:budget, email_account: email_account, amount: 100_000, period: "monthly")
    budget.categories << food
    create(:expense, in_period(category: food, amount: 20_000, transaction_date: 2.months.ago))

    expect(described_class.call([ budget ])).to eq(0.0)
  end

  it "excludes expenses in a different currency than the budget" do
    budget = create(:budget, email_account: email_account, amount: 100_000, currency: "CRC")
    budget.categories << food
    create(:expense, in_period(category: food, amount: 20_000, currency: :usd))

    expect(described_class.call([ budget ])).to eq(0.0)
  end

  it "unions spend across budgets belonging to different email_accounts" do
    other_account = create(:email_account)
    budget_a = create(:budget, email_account: email_account, amount: 100_000)
    budget_a.categories << food
    budget_b = create(:budget, email_account: other_account, amount: 100_000)
    budget_b.categories << food

    create(:expense, in_period(category: food, amount: 20_000))
    create(:expense, email_account: other_account, transaction_date: Date.current.beginning_of_month + 3.days,
                      currency: :crc, amount: 30_000, status: :processed, category: food)

    expect(described_class.call([ budget_a, budget_b ])).to eq(50_000.0)
  end
end
