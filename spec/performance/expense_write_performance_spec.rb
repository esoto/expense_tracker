# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Expense Write Performance", type: :model, performance: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

  describe "INSERT performance", performance: true do
    it "completes single inserts within 100ms" do
      durations = []

      5.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        create(:expense,
               email_account: email_account,
               category: category,
               amount: rand(1..1000),
               transaction_date: rand(30.days.ago..Date.today))

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        durations << duration * 1000 # Convert to milliseconds
      end

      average_duration = durations.sum / durations.size
      max_duration = durations.max

      expect(max_duration).to be < 100, "Maximum INSERT time was #{max_duration.round(2)}ms"
      expect(average_duration).to be < 50, "Average INSERT time was #{average_duration.round(2)}ms"
    end

    it "handles bulk inserts efficiently" do
      expenses_data = 100.times.map do |i|
        {
          email_account_id: email_account.id,
          category_id: category.id,
          amount: rand(1..1000),
          description: "Test expense #{i}",
          transaction_date: rand(30.days.ago..Date.today),
          merchant_name: "Merchant #{i}",
          status: "pending",
          currency: 0,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Expense.insert_all(expenses_data)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 500, "Bulk INSERT of 100 records took #{duration_ms.round(2)}ms"
      expect(duration_ms / 100).to be < 5, "Average per-record time was #{(duration_ms / 100).round(2)}ms"
    end
  end

  describe "UPDATE performance", performance: true do
    let!(:expenses) { create_list(:expense, 50, email_account: email_account) }

    it "completes single updates within 100ms" do
      expense = expenses.sample
      durations = []

      5.times do |i|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expense.update!(
          amount: rand(1..1000),
          description: "Updated description #{i}",
          category_id: category.id
        )

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        durations << duration * 1000
      end

      average_duration = durations.sum / durations.size
      max_duration = durations.max

      expect(max_duration).to be < 100, "Maximum UPDATE time was #{max_duration.round(2)}ms"
      expect(average_duration).to be < 50, "Average UPDATE time was #{average_duration.round(2)}ms"
    end

    it "handles bulk updates efficiently" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Expense.where(id: expenses.pluck(:id))
             .update_all(category_id: category.id, updated_at: Time.current)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 200, "Bulk UPDATE of 50 records took #{duration_ms.round(2)}ms"
    end

    it "maintains performance with optimistic locking" do
      expense = expenses.first

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expense.with_lock do
        expense.update!(amount: 999.99)
      end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 100, "UPDATE with locking took #{duration_ms.round(2)}ms"
    end
  end

  describe "DELETE performance", performance: true do
    let!(:expenses) { create_list(:expense, 50, email_account: email_account) }

    it "completes soft deletes within 100ms" do
      expense = expenses.sample

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expense.soft_delete!

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 100, "Soft DELETE took #{duration_ms.round(2)}ms"
      expect(expense.deleted_at).to be_present
    end

    it "handles bulk soft deletes efficiently" do
      ids_to_delete = expenses.sample(25).map(&:id)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Expense.where(id: ids_to_delete)
             .update_all(deleted_at: Time.current, lock_version: 1)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 200, "Bulk soft DELETE of 25 records took #{duration_ms.round(2)}ms"
    end
  end

  describe "Index impact on write operations", performance: true do
    it "maintains acceptable performance with all indexes" do
      # Test that indexes don't significantly impact write performance
      insert_times = []
      update_times = []

      10.times do
        # Test INSERT
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expense = create(:expense, email_account: email_account)
        insert_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

        # Test UPDATE
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expense.update!(amount: rand(1..1000), category_id: category.id)
        update_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      avg_insert = insert_times.sum / insert_times.size
      avg_update = update_times.sum / update_times.size

      expect(avg_insert).to be < 75, "Average INSERT with indexes: #{avg_insert.round(2)}ms"
      expect(avg_update).to be < 75, "Average UPDATE with indexes: #{avg_update.round(2)}ms"
    end
  end

  describe "Concurrent write performance", performance: true do
    it "handles concurrent inserts without significant degradation" do
      threads = []
      durations = Concurrent::Array.new

      5.times do |i|
        threads << Thread.new do
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          ActiveRecord::Base.connection_pool.with_connection do
            create(:expense,
                   email_account: email_account,
                   description: "Concurrent expense #{i}",
                   amount: rand(1..1000))
          end

          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          durations << duration * 1000
        end
      end

      threads.each(&:join)

      average_duration = durations.sum / durations.size
      max_duration = durations.max

      expect(max_duration).to be < 200, "Max concurrent INSERT: #{max_duration.round(2)}ms"
      expect(average_duration).to be < 100, "Avg concurrent INSERT: #{average_duration.round(2)}ms"
    end
  end

  describe "Transaction performance", performance: true do
    it "completes complex transactions within acceptable time" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ActiveRecord::Base.transaction do
        # Create multiple related records
        expense = create(:expense, email_account: email_account)

        # Update with categorization
        expense.update!(
          category_id: category.id,
          auto_categorized: true,
          categorization_confidence: 0.95,
          categorization_method: "pattern_matching",
          categorized_at: Time.current
        )

        # Create feedback record (simulated)
        expense.update!(ml_correction_count: 1, ml_last_corrected_at: Time.current)
      end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      duration_ms = duration * 1000

      expect(duration_ms).to be < 150, "Complex transaction took #{duration_ms.round(2)}ms"
    end
  end
end
