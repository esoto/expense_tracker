# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Categorization::Orchestrator, type: :service, integration: true do
  describe 'Performance and Safety Improvements', integration: true do
    let(:orchestrator) { Categorization::OrchestratorFactory.create_test }
    let(:expense) do
      create(:expense,
        merchant_name: 'Amazon',
        description: 'Electronics purchase',
        amount: 150.00
      )
    end

    describe 'N+1 Query Prevention', integration: true do
      it 'preloads categories efficiently in batch processing' do
        expenses = create_list(:expense, 10, merchant_name: 'Test Merchant')
        categories = create_list(:category, 5)

        # Create patterns for different categories
        categories.each do |category|
          create(:categorization_pattern,
            category: category,
            pattern_type: 'merchant',
            pattern_value: 'Test Merchant'
          )
        end

        # Should not have N+1 queries when calculating confidence scores
        # Allow reasonable number of queries for batch processing (preloading + categorization)
        expect {
          orchestrator.batch_categorize(expenses)
        }.to make_database_queries(count: 1..30) # Reasonable range for batch of 10 with preloading
      end
    end

    describe 'Thread Safety', integration: true do
      it 'handles concurrent categorization requests safely' do
        expenses = create_list(:expense, 20)
        results = Concurrent::Array.new

        threads = 4.times.map do
          Thread.new do
            5.times do |i|
              result = orchestrator.categorize(expenses[i])
              results << result
            end
          end
        end

        threads.each(&:join)

        expect(results.size).to eq(20)
        expect(results.all? { |r| r.is_a?(Categorization::CategorizationResult) }).to be true
      end

      it 'synchronizes reset operations safely' do
        threads = 10.times.map do
          Thread.new { orchestrator.reset! }
        end

        expect { threads.each(&:join) }.not_to raise_error
      end
    end

    describe 'Elapsed Time Tracking', integration: true do
      it 'accurately tracks processing time' do
        result = orchestrator.categorize(expense)

        expect(result.processing_time_ms).to be_a(Float)
        expect(result.processing_time_ms).to be > 0
        expect(result.processing_time_ms).to be < 1000 # Should be under 1 second
      end

      it 'includes processing time in error results' do
        invalid_expense = build(:expense, merchant_name: nil, description: nil)
        result = orchestrator.categorize(invalid_expense)

        expect(result.error?).to be true
        expect(result.processing_time_ms).to be_a(Float)
        expect(result.processing_time_ms).to be >= 0
      end
    end

    describe 'Error Differentiation', integration: true do
      it 'handles database errors specifically' do
        allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::StatementInvalid.new("Database error"))

        result = orchestrator.categorize(expense)

        expect(result.error?).to be true
        expect(result.error).to include("Database connection error")
      end

      it 'handles record not found errors' do
        allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::RecordNotFound.new("Not found"))

        result = orchestrator.categorize(expense)

        expect(result.error?).to be true
        expect(result.error).to include("Required data not found")
      end

      it 'includes correlation ID in error logs' do
        allow(Rails.logger).to receive(:error)
        allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::StatementInvalid.new("Database error"))

        orchestrator.categorize(expense, correlation_id: 'test-123')

        expect(Rails.logger).to have_received(:error).with(
          a_string_matching(/correlation_id: test-123/)
        ).at_least(:once)
      end
    end

    describe 'Circuit Breaker Integration', integration: true do
      let(:circuit_breaker) { Categorization::Orchestrator::CircuitBreaker.new(failure_threshold: 3) }
      let(:orchestrator_with_breaker) do
        Categorization::OrchestratorFactory.create_custom(
          circuit_breaker: circuit_breaker
        )
      end

      it 'opens circuit after threshold failures' do
        # Simulate failures
        3.times do
          allow_any_instance_of(Categorization::PatternCache).to receive(:get_patterns_for_expense)
            .and_raise(StandardError.new("Service error"))

          result = orchestrator_with_breaker.categorize(expense)
          expect(result.error?).to be true
        end

        # Circuit should be open now
        expect(circuit_breaker.state).to eq(:open)

        # Next request should fail fast
        result = orchestrator_with_breaker.categorize(expense)
        expect(result.error?).to be true
        expect(result.error).to include("Service temporarily unavailable")
      end

      it 'resets to closed state after timeout' do
        circuit_breaker.instance_variable_set(:@state, :open)
        circuit_breaker.instance_variable_set(:@last_failure_time, 31.seconds.ago)

        # Should transition to half-open and then closed on success
        expect {
          circuit_breaker.call { "success" }
        }.to change { circuit_breaker.state }.from(:open).to(:closed)
      end
    end

    describe 'Monitoring Integration', integration: true do
      it 'tracks performance metrics' do
        # Stub the module if it's defined
        if defined?(Infrastructure::MonitoringService::PerformanceTracker)
          # Create a pattern so categorization has work to do
          category = create(:category, name: 'Shopping')
          create(:categorization_pattern,
            category: category,
            pattern_type: 'merchant',
            pattern_value: 'Amazon'
          )

          allow(Infrastructure::MonitoringService::PerformanceTracker).to receive(:track).and_call_original

          # Use a longer timeout to ensure the operation completes
          orchestrator.categorize(expense, timeout: 0.100)

          expect(Infrastructure::MonitoringService::PerformanceTracker).to have_received(:track).with(
            "categorization",
            "categorize_expense",
            anything,
            hash_including(:expense_id, :correlation_id)
          )
        else
          # Skip test if monitoring service is not available
          pending "MonitoringService::PerformanceTracker not available"
        end
      end

      it 'reports errors to monitoring service' do
        # Stub the module if it's defined
        if defined?(Infrastructure::MonitoringService::ErrorTracker)
          allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
          allow(CategorizationPattern).to receive(:active)
            .and_raise(StandardError.new("Test error"))

          orchestrator.categorize(expense)

          expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report).with(
            an_instance_of(StandardError),
            hash_including(:service, :expense_id, :correlation_id)
          )
        else
          # Skip test if monitoring service is not available
          pending "MonitoringService::ErrorTracker not available"
        end
      end
    end

    describe 'Batch Processing Optimization', integration: true do
      it 'supports parallel processing for large batches' do
        expenses = create_list(:expense, 20)

        results = orchestrator.batch_categorize(expenses, parallel: true, max_threads: 4)

        expect(results.size).to eq(20)
        expect(results.all? { |r| r.is_a?(Categorization::CategorizationResult) }).to be true
      end

      it 'preloads categories to avoid N+1 queries' do
        expenses = create_list(:expense, 10)

        expect(Category).to receive(:active).once.and_call_original

        orchestrator.batch_categorize(expenses)
      end

      it 'uses sequential processing for small batches' do
        expenses = create_list(:expense, 5)

        expect(orchestrator).not_to receive(:process_batch_parallel)

        orchestrator.batch_categorize(expenses, parallel: true)
      end
    end

    describe 'Performance Alerting', integration: true do
      it 'logs warning when operation exceeds threshold' do
        # Create a pattern so we have something to match
        category = create(:category, name: 'Electronics')
        create(:categorization_pattern,
          category: category,
          pattern_type: 'merchant',
          pattern_value: 'Amazon'
        )

        allow(Rails.logger).to receive(:warn)

        # Simulate slow pattern matching - this method is always called
        allow(orchestrator).to receive(:find_pattern_matches).and_wrap_original do |original, *args|
          # Use time mocking instead of real sleep for faster tests
          new_time = Time.current + 0.030.seconds
          allow(Time).to receive(:current).and_return(new_time)
          original.call(*args)
        end

        # Use longer timeout to allow the operation to complete
        orchestrator.categorize(expense, timeout: 0.100) # 100ms timeout

        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/\[PERFORMANCE\].*took \d+\.\d+ms/)
        )
      end
    end
  end
end
