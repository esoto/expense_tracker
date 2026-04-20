# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Concurrent duplicate expense prevention (PER-277)", type: :model, unit: true do
  # Use let! (eager) so email_account is created before threads start.
  # Creating it lazily inside a Thread.new closure (via with_connection) can
  # cause the factory's user+email_account INSERTs to interleave with the
  # thread's connection checkout, leading to PG::InFailedSqlTransaction errors
  # on the main connection in some random orderings (PR 4 factory now creates
  # a User in addition to the EmailAccount, adding a SAVEPOINT to the sequence).
  let!(:email_account) { create(:email_account) }
  let(:transaction_date) { Time.zone.parse("2026-03-15 12:00:00") }

  it "creates exactly one expense when two threads attempt the same insert" do
    results = []
    errors = []

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          expense = Expense.new(
            email_account: email_account,
            amount: 25.50,
            transaction_date: transaction_date,
            merchant_name: "Uber",
            description: "Ride to airport",
            status: :pending
          )
          expense.save!
          results << expense
        rescue ActiveRecord::RecordNotUnique
          errors << "duplicate"
        end
      end
    end

    threads.each(&:join)

    expect(results.size + errors.size).to eq(2)
    expect(results.size).to eq(1), "Expected exactly 1 successful insert, got #{results.size}"
    expect(errors.size).to eq(1), "Expected exactly 1 RecordNotUnique error, got #{errors.size}"

    persisted_count = Expense.where(
      email_account: email_account,
      amount: 25.50,
      transaction_date: transaction_date,
      merchant_name: "Uber"
    ).count
    expect(persisted_count).to eq(1)
  end

  it "allows creating after soft-deleting the original" do
    original = create(:expense,
      email_account: email_account,
      amount: 25.50,
      transaction_date: transaction_date,
      merchant_name: "Uber"
    )
    original.update_columns(deleted_at: 1.hour.ago)

    replacement = Expense.create!(
      email_account: email_account,
      amount: 25.50,
      transaction_date: transaction_date,
      merchant_name: "Uber",
      description: "Re-imported",
      status: :pending
    )

    expect(replacement).to be_persisted
    expect(Expense.where(email_account: email_account, merchant_name: "Uber", deleted_at: nil).count).to eq(1)
  end
end
