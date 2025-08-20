# frozen_string_literal: true

require "rails_helper"
require "concurrent"

RSpec.describe "Categorization::Orchestrator Thread Safety", type: :service, integration: true do
  describe "Concurrent operations", integration: true do
    let(:orchestrator) { Categorization::OrchestratorFactory.create_production }

    # Create test data
    before(:all) do
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.clean

      @email_account = EmailAccount.create!(
        email: "test@example.com",
        provider: "gmail",
        bank_name: "Test Bank",
        encrypted_settings: { oauth: { access_token: "test" } }.to_json
      )

      @category = Category.create!(name: "Test Category")
      @patterns = 5.times.map do |i|
        CategorizationPattern.create!(
          pattern_type: "merchant",
          pattern_value: "test_merchant_#{i}",
          category: @category,
          confidence_weight: 2.0
        )
      end

      @expenses = 20.times.map do |i|
        Expense.create!(
          merchant_name: "test_merchant_#{i % 5}",
          description: "Test purchase #{i}",
          amount: rand(10.0..100.0),
          email_account: @email_account,
          transaction_date: Date.current,
          status: "pending",
          currency: "usd"
        )
      end
    end

    after(:all) do
      DatabaseCleaner.clean
    end

    describe "Thread-safe initialization", integration: true do
      it "safely initializes services across threads" do
        orchestrators = Concurrent::Array.new
        errors = Concurrent::Array.new

        threads = 10.times.map do
          Thread.new do
            begin
              orch = Categorization::OrchestratorFactory.create_production
              orchestrators << orch

              # Verify services are properly initialized
              expect(orch.pattern_cache).to be_present
              expect(orch.matcher).to be_present
              expect(orch.confidence_calculator).to be_present
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(orchestrators.size).to eq(10)
      end
    end

    describe "Concurrent categorization", integration: true do
      it "handles multiple threads categorizing simultaneously" do
        results = Concurrent::Array.new
        errors = Concurrent::Array.new

        threads = 20.times.map do |i|
          Thread.new do
            begin
              expense = @expenses[i]
              result = orchestrator.categorize(expense)
              results << result
            rescue => e
              errors << { error: e, expense_id: @expenses[i]&.id }
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(results.size).to eq(20)
        expect(results).to all(be_a(Categorization::CategorizationResult))
      end

      it "maintains data integrity under concurrent access" do
        expense = @expenses.first
        results = Concurrent::Array.new

        # Multiple threads categorizing the same expense
        threads = 50.times.map do
          Thread.new do
            result = orchestrator.categorize(expense)
            results << result
          end
        end

        threads.each(&:join)

        # All results should be consistent
        expect(results.size).to eq(50)
        categories = results.map(&:category).compact.uniq
        confidences = results.map(&:confidence).compact.uniq

        # Should have consistent categorization
        expect(categories.size).to eq(1) # Same category for same expense
        expect(confidences.size).to be <= 2 # Allow minor floating point differences
      end
    end

    describe "Concurrent batch processing", integration: true do
      it "handles concurrent batch operations" do
        batches = @expenses.each_slice(5).to_a
        all_results = Concurrent::Array.new
        errors = Concurrent::Array.new

        threads = batches.map do |batch|
          Thread.new do
            begin
              results = orchestrator.batch_categorize(batch)
              all_results.concat(results)
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(all_results.size).to eq(@expenses.size)
      end

      it "handles mixed concurrent operations" do
        operations_completed = Concurrent::AtomicFixnum.new(0)
        errors = Concurrent::Array.new

        # Mix of single and batch operations
        threads = []

        # Single categorizations
        threads += 10.times.map do |i|
          Thread.new do
            begin
              expense = @expenses[i]
              orchestrator.categorize(expense)
              operations_completed.increment
            rescue => e
              errors << e
            end
          end
        end

        # Batch categorizations
        threads += 2.times.map do |i|
          Thread.new do
            begin
              batch = @expenses[i*5...(i+1)*5]
              orchestrator.batch_categorize(batch)
              operations_completed.increment
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(operations_completed.value).to eq(12)
      end
    end

    describe "State management thread safety", integration: true do
      it "safely handles configuration changes during concurrent operations" do
        errors = Concurrent::Array.new
        results = Concurrent::Array.new

        # Thread that changes configuration
        config_thread = Thread.new do
          5.times do
            orchestrator.configure(
              min_confidence: rand(0.4..0.6),
              auto_categorize_threshold: rand(0.6..0.8)
            )
            sleep 0.01
          end
        end

        # Threads performing categorization
        categorization_threads = 10.times.map do |i|
          Thread.new do
            begin
              5.times do
                expense = @expenses.sample
                result = orchestrator.categorize(expense)
                results << result
                sleep 0.005
              end
            rescue => e
              errors << e
            end
          end
        end

        config_thread.join
        categorization_threads.each(&:join)

        expect(errors).to be_empty
        expect(results).to all(be_a(Categorization::CategorizationResult))
      end

      it "safely handles reset operations" do
        errors = Concurrent::Array.new
        operations = Concurrent::AtomicFixnum.new(0)

        # Thread that periodically resets
        reset_thread = Thread.new do
          3.times do
            sleep 0.05
            orchestrator.reset!
          end
        end

        # Threads performing operations
        operation_threads = 10.times.map do
          Thread.new do
            begin
              10.times do
                expense = @expenses.sample
                orchestrator.categorize(expense)
                operations.increment
                sleep 0.01
              end
            rescue => e
              errors << e
            end
          end
        end

        reset_thread.join
        operation_threads.each(&:join)

        expect(errors).to be_empty
        expect(operations.value).to be > 0
      end
    end

    describe "Learning operation thread safety", integration: true do
      it "handles concurrent learning operations" do
        errors = Concurrent::Array.new
        results = Concurrent::Array.new

        threads = 10.times.map do |i|
          Thread.new do
            begin
              expense = @expenses[i]
              result = orchestrator.learn_from_correction(
                expense,
                @category,
                nil
              )
              results << result
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(results).to all(be_success)
      end

      it "handles learning during active categorization" do
        errors = Concurrent::Array.new

        # Thread performing learning
        learning_thread = Thread.new do
          begin
            5.times do |i|
              expense = @expenses[i]
              orchestrator.learn_from_correction(expense, @category)
              sleep 0.02
            end
          rescue => e
            errors << e
          end
        end

        # Threads performing categorization
        categorization_threads = 5.times.map do
          Thread.new do
            begin
              10.times do
                expense = @expenses.sample
                orchestrator.categorize(expense)
                sleep 0.01
              end
            rescue => e
              errors << e
            end
          end
        end

        learning_thread.join
        categorization_threads.each(&:join)

        expect(errors).to be_empty
      end
    end

    describe "Circuit breaker thread safety", integration: true do
      it "handles circuit breaker state changes safely" do
        # Create orchestrator with low circuit breaker threshold
        orch = Categorization::Orchestrator.new(
          circuit_breaker: Categorization::Orchestrator::CircuitBreaker.new(
            failure_threshold: 3,
            timeout: 1.second
          )
        )

        # Mock service to fail
        allow(orch.pattern_cache).to receive(:get_patterns_for_expense)
          .and_raise(StandardError, "Simulated failure")

        results = Concurrent::Array.new

        threads = 10.times.map do
          Thread.new do
            expense = @expenses.sample
            result = orch.categorize(expense)
            results << result
          end
        end

        threads.each(&:join)

        # Should handle failures gracefully
        expect(results).to all(be_a(Categorization::CategorizationResult))
        expect(results.map(&:failed?).count(true)).to be > 0
      end
    end

    describe "Resource contention", integration: true do
      it "handles high contention scenarios" do
        # Single expense that all threads will compete for
        expense = @expenses.first
        latch = Concurrent::CountDownLatch.new(1)
        results = Concurrent::Array.new

        # Create threads that will all start at the same time
        threads = 100.times.map do
          Thread.new do
            latch.wait # Wait for signal
            result = orchestrator.categorize(expense)
            results << result
          end
        end

        # Release all threads simultaneously
        latch.count_down

        threads.each(&:join)

        expect(results.size).to eq(100)
        expect(results).to all(be_a(Categorization::CategorizationResult))
      end

      it "maintains performance under contention" do
        expense = @expenses.first
        times = Concurrent::Array.new

        threads = 20.times.map do
          Thread.new do
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            orchestrator.categorize(expense)
            elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
            times << elapsed
          end
        end

        threads.each(&:join)

        average_time = times.sum / times.size.to_f
        max_time = times.max

        puts "\n  Concurrent Performance:"
        puts "    Average: #{average_time.round(2)}ms"
        puts "    Max: #{max_time.round(2)}ms"

        # Should maintain reasonable performance even under contention
        expect(average_time).to be < 50
        expect(max_time).to be < 200
      end
    end

    describe "Deadlock prevention", integration: true do
      it "avoids deadlocks in complex scenarios" do
        completed = Concurrent::AtomicBoolean.new(false)

        thread = Thread.new do
          # Complex operation that could potentially deadlock
          100.times do
            expense = @expenses.sample

            # Mix of operations
            orchestrator.categorize(expense)
            orchestrator.metrics
            orchestrator.healthy?
            orchestrator.configure(min_confidence: rand(0.4..0.6))

            if rand > 0.8
              orchestrator.learn_from_correction(expense, @category)
            end

            if rand > 0.9
              orchestrator.reset!
            end
          end

          completed.make_true
        end

        # Wait with timeout to detect deadlock
        thread.join(10) # 10 second timeout

        if thread.alive?
          thread.kill
          fail "Deadlock detected - thread did not complete within timeout"
        end

        expect(completed.value).to be true
      end
    end
  end
end
