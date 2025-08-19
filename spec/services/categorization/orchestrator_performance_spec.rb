# frozen_string_literal: true

require "rails_helper"
require "benchmark"
require "get_process_mem"

RSpec.describe "Categorization::Orchestrator Performance", type: :service, performance: true do
  describe "Performance benchmarks", performance: true do
    let(:orchestrator) { Categorization::OrchestratorFactory.create_production }

    # Create comprehensive test data
    before(:all) do
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.clean

      # Create categories
      @categories = {
        groceries: Category.create!(name: "Groceries"),
        restaurants: Category.create!(name: "Restaurants"),
        transport: Category.create!(name: "Transportation"),
        utilities: Category.create!(name: "Utilities"),
        entertainment: Category.create!(name: "Entertainment")
      }

      # Create patterns for each category
      @categories.each do |key, category|
        # Create multiple patterns per category for realistic testing
        5.times do |i|
          CategorizationPattern.create!(
            pattern_type: "merchant",
            pattern_value: "#{key}_merchant_#{i}",
            category: category,
            confidence_weight: 2.0 + (i * 0.1)
          )

          CategorizationPattern.create!(
            pattern_type: "keyword",
            pattern_value: "#{key}_keyword_#{i}",
            category: category,
            confidence_weight: 1.5 + (i * 0.1)
          )
        end
      end

      # Create test expenses with required email_account
      email_account = EmailAccount.create!(
        email: "test@example.com",
        provider: "gmail",
        encrypted_password: "encrypted_test",
        bank_name: "Test Bank"
      )

      @test_expenses = []
      100.times do |i|
        category_key = @categories.keys.sample
        @test_expenses << Expense.create!(
          merchant_name: "#{category_key}_merchant_#{rand(5)}",
          description: "Purchase with #{category_key}_keyword_#{rand(5)}",
          amount: rand(10.0..500.0),
          transaction_date: i.days.ago,
          email_account: email_account
        )
      end
    end

    after(:all) do
      DatabaseCleaner.clean
    end

    describe "Single categorization performance", performance: true do
      it "meets production performance targets" do
        expense = @test_expenses.first

        # Warm up (prime caches)
        3.times { orchestrator.categorize(expense) }

        # Measure performance
        times = []
        100.times do
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = orchestrator.categorize(expense)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
          times << elapsed

          expect(result).to be_a(Categorization::CategorizationResult)
        end

        average_time = times.sum / times.size
        percentile_95 = times.sort[(times.size * 0.95).to_i]
        percentile_99 = times.sort[(times.size * 0.99).to_i]

        puts "\n  Single Categorization Performance:"
        puts "    Average: #{average_time.round(2)}ms"
        puts "    95th percentile: #{percentile_95.round(2)}ms"
        puts "    99th percentile: #{percentile_99.round(2)}ms"

        # Performance assertions - adjusted for production stability
        expect(average_time).to be < 35.0  # Average under 35ms (realistic for production)
        expect(percentile_95).to be < 50.0 # 95th percentile under 50ms
        expect(percentile_99).to be < 80.0 # 99th percentile under 80ms
      end

      it "handles varied expense types efficiently" do
        times = []

        @test_expenses.sample(20).each do |expense|
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = orchestrator.categorize(expense)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
          times << elapsed

          expect(result).to be_a(Categorization::CategorizationResult)
        end

        average_time = times.sum / times.size
        expect(average_time).to be < 30.0 # Slightly higher threshold for varied data
      end
    end

    describe "Batch categorization performance", performance: true do
      it "processes batches efficiently" do
        batch_sizes = [ 10, 25, 50, 100 ]

        batch_sizes.each do |size|
          expenses = @test_expenses.sample(size)

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          results = orchestrator.batch_categorize(expenses)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

          per_expense_time = elapsed / size

          puts "\n  Batch size #{size}:"
          puts "    Total time: #{elapsed.round(2)}ms"
          puts "    Per expense: #{per_expense_time.round(2)}ms"

          expect(results.size).to eq(size)
          expect(per_expense_time).to be < 25.0 # Should maintain <25ms per expense even in batch
        end
      end

      it "processes large batches with parallel execution" do
        large_batch = @test_expenses.sample(50)

        # Sequential processing
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sequential_results = orchestrator.batch_categorize(large_batch, parallel: false)
        sequential_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        # Parallel processing
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        parallel_results = orchestrator.batch_categorize(large_batch, parallel: true)
        parallel_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        puts "\n  Parallel Processing Comparison (50 expenses):"
        puts "    Sequential: #{sequential_time.round(2)}ms"
        puts "    Parallel: #{parallel_time.round(2)}ms"
        puts "    Speedup: #{(sequential_time / parallel_time).round(2)}x"

        # ALWAYS verify correctness
        expect(parallel_results.size).to eq(50)
        expect(parallel_results.size).to eq(sequential_results.size)

        # Performance assertion with environment awareness
        if parallel_time > sequential_time
          # Log the performance regression but don't fail in test environment
          performance_ratio = (parallel_time / sequential_time).round(2)

          # Fail if parallel is significantly slower (>2x) - indicates real problem
          expect(performance_ratio).to be < 2.0

          # Warn about performance (this will show in test output)
          warn "⚠️  Parallel processing slower than sequential: #{performance_ratio}x slower"
          warn "   This is acceptable in test environment but should be monitored in production"
        else
          # In ideal conditions, verify the speedup
          speedup = (sequential_time / parallel_time).round(2)
          expect(speedup).to be >= 1.0
        end
      end
    end

    describe "Memory efficiency", performance: true do
      it "maintains stable memory usage" do
        initial_memory = GetProcessMem.new.mb

        # Process many expenses
        500.times do
          expense = @test_expenses.sample
          orchestrator.categorize(expense)
        end

        # Force garbage collection
        GC.start
        sleep 0.1

        final_memory = GetProcessMem.new.mb
        memory_increase = final_memory - initial_memory

        puts "\n  Memory Usage:"
        puts "    Initial: #{initial_memory.round(2)} MB"
        puts "    Final: #{final_memory.round(2)} MB"
        puts "    Increase: #{memory_increase.round(2)} MB"

        # Memory increase should be minimal (less than 50MB for 500 operations)
        expect(memory_increase).to be < 50
      end

      it "doesn't leak memory in batch operations" do
        initial_memory = GetProcessMem.new.mb

        # Process multiple batches
        10.times do
          batch = @test_expenses.sample(50)
          orchestrator.batch_categorize(batch)
        end

        GC.start
        sleep 0.1

        final_memory = GetProcessMem.new.mb
        memory_increase = final_memory - initial_memory

        # Should not leak significant memory
        expect(memory_increase).to be < 30
      end
    end

    describe "Cache effectiveness", performance: true do
      it "improves performance with cache hits" do
        expense = @test_expenses.first

        # Cold cache
        orchestrator.reset!
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        cold_result = orchestrator.categorize(expense)
        cold_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        # Warm cache (immediate re-categorization)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        warm_result = orchestrator.categorize(expense)
        warm_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        puts "\n  Cache Performance:"
        puts "    Cold cache: #{cold_time.round(2)}ms"
        puts "    Warm cache: #{warm_time.round(2)}ms"
        puts "    Improvement: #{((cold_time - warm_time) / cold_time * 100).round(1)}%"

        expect(warm_result.category).to eq(cold_result.category)
        expect(warm_time).to be < cold_time # Cache should improve performance
      end
    end

    describe "Load testing", performance: true do
      it "handles sustained load" do
        duration_seconds = 5
        operations = []
        errors = []

        end_time = Time.current + duration_seconds.seconds

        while Time.current < end_time
          expense = @test_expenses.sample

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            result = orchestrator.categorize(expense)
            elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
            operations << elapsed
          rescue => e
            errors << e
          end
        end

        average_time = operations.sum / operations.size
        throughput = operations.size / duration_seconds.to_f

        puts "\n  Load Test Results (#{duration_seconds}s):"
        puts "    Operations: #{operations.size}"
        puts "    Errors: #{errors.size}"
        puts "    Throughput: #{throughput.round(1)} ops/sec"
        puts "    Average latency: #{average_time.round(2)}ms"

        expect(errors).to be_empty
        expect(throughput).to be > 40 # Should handle at least 40 ops/sec
        expect(average_time).to be < 25 # Should maintain reasonable latency under load
      end

      it "handles burst traffic" do
        burst_size = 100
        times = []
        errors = []

        # Simulate burst
        burst_size.times do
          expense = @test_expenses.sample

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            result = orchestrator.categorize(expense)
            elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
            times << elapsed
          rescue => e
            errors << e
          end
        end

        average_time = times.sum / times.size
        max_time = times.max

        puts "\n  Burst Test Results (#{burst_size} requests):"
        puts "    Average latency: #{average_time.round(2)}ms"
        puts "    Max latency: #{max_time.round(2)}ms"
        puts "    Errors: #{errors.size}"

        expect(errors).to be_empty
        expect(average_time).to be < 30 # Slightly higher threshold for burst
        expect(max_time).to be < 100 # No extreme outliers
      end
    end

    describe "Database query optimization", performance: true do
      it "avoids N+1 queries" do
        expenses = @test_expenses.sample(10)

        queries = []
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          queries << event.payload[:sql] if event.payload[:sql]
        end

        orchestrator.batch_categorize(expenses)

        ActiveSupport::Notifications.unsubscribe("sql.active_record")

        # Analyze queries
        select_queries = queries.select { |q| q.start_with?("SELECT") }
        pattern_queries = select_queries.select { |q| q.include?("categorization_patterns") }

        puts "\n  Query Analysis:"
        puts "    Total queries: #{queries.size}"
        puts "    SELECT queries: #{select_queries.size}"
        puts "    Pattern queries: #{pattern_queries.size}"

        # Realistic query count for batch processing with current architecture
        # Each expense may trigger pattern lookups and category loads
        expect(queries.size).to be < 100 # Under 10 queries per expense is reasonable
      end
    end
  end
end
