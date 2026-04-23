# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Budgets::BucketSummary, type: :service, unit: true do
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

  it "returns empty array when no bucketed budgets exist" do
    create(:budget, email_account: email_account, salary_bucket: nil)
    expect(described_class.new(email_account).call).to eq([])
  end

  it "aggregates budgeted + spent per bucket" do
    fixed_b = create(:budget, email_account: email_account, name: "Rent", amount: 300_000, salary_bucket: :fixed)
    fixed_b.categories << rent
    gf_b = create(:budget, email_account: email_account, name: "Fun", amount: 80_000, salary_bucket: :guilt_free)
    gf_b.categories << food

    create(:expense, in_period(category: rent, amount: 250_000))
    create(:expense, in_period(category: food, amount: 40_000))

    buckets = described_class.new(email_account).call.index_by(&:key)
    expect(buckets["fixed"].budgeted).to  eq(300_000.0)
    expect(buckets["fixed"].spent).to     eq(250_000.0)
    expect(buckets["fixed"].remaining).to eq(50_000.0)
    expect(buckets["guilt_free"].spent).to eq(40_000.0)
  end

  it "dedupes expenses shared across overlapping budgets in the same bucket" do
    a = create(:budget, email_account: email_account, name: "A", amount: 100_000, salary_bucket: :fixed)
    b = create(:budget, email_account: email_account, name: "B", amount: 100_000, salary_bucket: :fixed)
    a.categories << food
    b.categories << food
    create(:expense, in_period(category: food, amount: 15_000))

    fixed = described_class.new(email_account).call.find { |x| x.key == "fixed" }
    expect(fixed.spent).to eq(15_000.0)
  end
end
