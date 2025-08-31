# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::EngineImprovements, type: :service, unit: true do
  # Create a test class that includes the concern for testing
  let(:test_class) do
    Class.new do
      include Categorization::EngineImprovements

      # Add a mock categorize method for testing batch processing
      def categorize(expense, options = {})
        { expense_id: expense.id, categorized: true, options: options }
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#initialize_thread_safe_counters" do
    let(:mock_atomic) { instance_double("Concurrent::AtomicFixnum") }

    before do
      allow(instance).to receive(:require).with("concurrent")
      allow(Concurrent::AtomicFixnum).to receive(:new).and_return(mock_atomic)
    end

    it "initializes atomic counters" do
      expect(Concurrent::AtomicFixnum).to receive(:new).with(0).twice
      instance.initialize_thread_safe_counters
    end

    it "sets the counters as instance variables" do
      instance.initialize_thread_safe_counters
      expect(instance.instance_variable_get(:@total_categorizations_counter)).to eq(mock_atomic)
      expect(instance.instance_variable_get(:@successful_categorizations_counter)).to eq(mock_atomic)
    end

    it "creates a mutex for thread safety" do
      instance.initialize_thread_safe_counters
      expect(instance.instance_variable_get(:@metrics_mutex)).to be_a(Mutex)
    end
  end

  describe "#increment_total_categorizations" do
    let(:mock_counter) { instance_double("Concurrent::AtomicFixnum") }

    before do
      instance.instance_variable_set(:@total_categorizations_counter, mock_counter)
    end

    it "increments the total categorizations counter" do
      expect(mock_counter).to receive(:increment)
      instance.increment_total_categorizations
    end
  end

  describe "#increment_successful_categorizations" do
    let(:mock_counter) { instance_double("Concurrent::AtomicFixnum") }

    before do
      instance.instance_variable_set(:@successful_categorizations_counter, mock_counter)
    end

    it "increments the successful categorizations counter" do
      expect(mock_counter).to receive(:increment)
      instance.increment_successful_categorizations
    end
  end

  describe "#categorize_async" do
    let(:expense) { build(:expense, id: 123) }
    let(:options) { { priority: "high", source: "manual" } }

    before do
      allow(Categorization::CategorizationJob).to receive(:perform_later)
    end

    it "enqueues a categorization job with expense id" do
      expect(Categorization::CategorizationJob).to receive(:perform_later)
        .with(expense_id: 123, options: options)

      instance.categorize_async(expense, options)
    end

    it "works with empty options" do
      expect(Categorization::CategorizationJob).to receive(:perform_later)
        .with(expense_id: 123, options: {})

      instance.categorize_async(expense)
    end
  end

  describe "#batch_categorize_parallel" do
    let(:expense1) { build(:expense, id: 1) }
    let(:expense2) { build(:expense, id: 2) }
    let(:expense3) { build(:expense, id: 3) }

    context "with empty expenses array" do
      it "returns empty array" do
        expect(instance.batch_categorize_parallel([])).to eq([])
      end

      it "returns empty array for nil" do
        expect(instance.batch_categorize_parallel(nil)).to eq([])
      end
    end

    context "with small batch (100 or fewer expenses)" do
      let(:expenses) { [ expense1, expense2, expense3 ] }

      it "processes expenses sequentially" do
        expect(instance).to receive(:categorize).with(expense1, {}).ordered
        expect(instance).to receive(:categorize).with(expense2, {}).ordered
        expect(instance).to receive(:categorize).with(expense3, {}).ordered

        instance.batch_categorize_parallel(expenses)
      end

      it "passes options to categorize method" do
        options = { priority: "low" }
        expect(instance).to receive(:categorize).with(expense1, options)
        expect(instance).to receive(:categorize).with(expense2, options)

        instance.batch_categorize_parallel([ expense1, expense2 ], options)
      end

      it "returns results array" do
        results = instance.batch_categorize_parallel(expenses)

        expect(results).to be_an(Array)
        expect(results.size).to eq(3)
        expect(results.first).to include(expense_id: 1, categorized: true)
      end
    end

    context "with large batch (more than 100 expenses)" do
      # Build expenses before mocking to avoid database connection issues
      let!(:expenses) { Array.new(101) { |i| build(:expense, id: i + 1) } }
      let(:mock_connection_pool) { double("ActiveRecord::ConnectionPool") }

      before do
        allow(instance).to receive(:require).with("parallel")
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(mock_connection_pool)
        allow(mock_connection_pool).to receive(:with_connection) do |&block|
          block.call
        end
        allow(mock_connection_pool).to receive(:schema_cache)
      end

      it "uses Parallel.map with 4 threads" do
        expect(Parallel).to receive(:map).with(expenses, in_threads: 4).and_return([])
        instance.batch_categorize_parallel(expenses)
      end

      it "wraps each categorization in connection pool" do
        allow(Parallel).to receive(:map).and_yield(expenses.first).and_return([])

        expect(mock_connection_pool).to receive(:with_connection)
        expect(instance).to receive(:categorize).with(expenses.first, {})

        instance.batch_categorize_parallel(expenses)
      end

      it "processes all expenses in parallel" do
        processed_count = 0

        allow(Parallel).to receive(:map) do |items, _options|
          items.map do |expense|
            processed_count += 1
            instance.categorize(expense, {})
          end
        end

        results = instance.batch_categorize_parallel(expenses)

        expect(processed_count).to eq(101)
        expect(results.size).to eq(101)
      end
    end
  end

  describe "#find_pattern_matches_optimized" do
    # Build expense and category before mocking anything
    let!(:expense) { build(:expense, merchant_name: "Starbucks Coffee", description: "Morning coffee and pastry") }
    let!(:category) { build(:category, name: "Dining") }

    let(:mock_connection_pool) { double("ActiveRecord::ConnectionPool") }
    let(:mock_pattern_relation) { double("ActiveRecord::Relation") }

    # Create a mock CategorizationPattern class
    let(:mock_pattern_class) do
      Class.new do
        def self.active
          nil
        end
      end
    end

    before do
      # Mock the connection pool with all necessary methods
      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(mock_connection_pool)
      # Use a block that takes no arguments instead of yielding
      allow(mock_connection_pool).to receive(:with_connection) do |&block|
        block.call
      end
      allow(mock_connection_pool).to receive(:schema_cache)

      # Stub CategorizationPattern with our mock class
      stub_const("CategorizationPattern", mock_pattern_class)
      allow(mock_pattern_class).to receive(:active).and_return(mock_pattern_relation)
      allow(mock_pattern_relation).to receive(:where).and_return(mock_pattern_relation)
      allow(mock_pattern_relation).to receive(:includes).and_return(mock_pattern_relation)
      allow(mock_pattern_relation).to receive(:limit).and_return(mock_pattern_relation)
    end

    context "with merchant name" do
      let(:merchant_pattern) do
        double("CategorizationPattern",
               pattern_type: "merchant",
               pattern_value: "starbucks",
               success_rate: 0.9,
               confidence_weight: 0.8,
               category: category)
      end

      it "queries for merchant patterns" do
        # Mock to return empty array instead of the mock relation (which doesn't implement map)
        allow(mock_pattern_relation).to receive(:limit).and_return([])

        expect(mock_pattern_relation).to receive(:where)
          .with(pattern_type: "merchant")
          .and_return(mock_pattern_relation)

        expect(mock_pattern_relation).to receive(:where)
          .with("LOWER(pattern_value) LIKE ?", "%starbucks coffee%")
          .and_return(mock_pattern_relation)

        expect(mock_pattern_relation).to receive(:limit).with(20).and_return([])

        # Allow description query to happen (if description exists)
        allow(mock_pattern_relation).to receive(:where)
          .with(pattern_type: [ "keyword", "description" ])
          .and_return(mock_pattern_relation)
        allow(mock_pattern_relation).to receive(:where)
          .with("? ILIKE '%' || pattern_value || '%'", anything)
          .and_return(mock_pattern_relation)

        instance.find_pattern_matches_optimized(expense, {})
      end

      it "processes matching merchant patterns" do
        allow(mock_pattern_relation).to receive(:limit).and_return([ merchant_pattern ])
        allow(instance).to receive(:process_patterns).and_return([ { pattern: merchant_pattern } ])

        matches = instance.find_pattern_matches_optimized(expense, {})

        expect(matches).to include({ pattern: merchant_pattern })
      end
    end

    context "with description" do
      let(:keyword_pattern) do
        double("CategorizationPattern",
               pattern_type: "keyword",
               pattern_value: "coffee",
               success_rate: 0.85,
               confidence_weight: 0.75,
               category: category)
      end

      it "queries for keyword and description patterns" do
        # Allow merchant query to happen first (if merchant_name exists)
        allow(mock_pattern_relation).to receive(:where)
          .with(pattern_type: "merchant")
          .and_return(mock_pattern_relation)
        allow(mock_pattern_relation).to receive(:where)
          .with("LOWER(pattern_value) LIKE ?", anything)
          .and_return(mock_pattern_relation)
        allow(mock_pattern_relation).to receive(:limit).and_return([])

        # Then expect description patterns query
        expect(mock_pattern_relation).to receive(:where)
          .with(pattern_type: [ "keyword", "description" ])
          .and_return(mock_pattern_relation)

        expect(mock_pattern_relation).to receive(:where)
          .with("? ILIKE '%' || pattern_value || '%'", "Morning coffee and pastry")
          .and_return(mock_pattern_relation)

        instance.find_pattern_matches_optimized(expense, {})
      end

      it "processes matching keyword patterns" do
        allow(mock_pattern_relation).to receive(:limit).and_return([ keyword_pattern ])
        allow(instance).to receive(:process_patterns).and_return([ { pattern: keyword_pattern } ])

        matches = instance.find_pattern_matches_optimized(expense, {})

        expect(matches).to include({ pattern: keyword_pattern })
      end
    end

    context "with both merchant and description" do
      it "concatenates results from both queries" do
        merchant_pattern = double("CategorizationPattern", pattern_type: "merchant")
        keyword_pattern = double("CategorizationPattern", pattern_type: "keyword")

        allow(mock_pattern_relation).to receive(:limit).and_return([ merchant_pattern ], [ keyword_pattern ])
        allow(instance).to receive(:process_patterns)
          .and_return([ { pattern: merchant_pattern } ], [ { pattern: keyword_pattern } ])

        matches = instance.find_pattern_matches_optimized(expense, {})

        expect(matches).to include({ pattern: merchant_pattern })
        expect(matches).to include({ pattern: keyword_pattern })
      end
    end

    context "with no merchant or description" do
      let!(:expense) { build(:expense, merchant_name: "", description: "") }

      it "returns empty array" do
        # When merchant_name and description are empty strings, the method should still enter the connection pool
        # but not make any queries since the conditionals will evaluate to false (blank strings are not present?)

        # Ensure merchant_name? and description? return false for empty strings
        allow(expense).to receive(:merchant_name?).and_return(false)
        allow(expense).to receive(:description?).and_return(false)

        # The with_connection block will be called
        expect(mock_connection_pool).to receive(:with_connection) do |&block|
          block.call
        end

        # But no pattern queries should be made
        expect(mock_pattern_class).not_to receive(:active)

        matches = instance.find_pattern_matches_optimized(expense, {})
        expect(matches).to eq([])
      end
    end
  end

  describe "#process_patterns (private)" do
    let(:expense) { build(:expense, merchant_name: "Target") }
    let(:category) { build(:category) }
    let(:pattern1) do
      double("CategorizationPattern",
             pattern_value: "target",
             success_rate: 0.9,
             confidence_weight: 0.8,
             pattern_type: "merchant",
             category: category)
    end
    let(:pattern2) do
      double("CategorizationPattern",
             pattern_value: "walmart",
             success_rate: 0.7,
             confidence_weight: 0.3,
             pattern_type: "merchant",
             category: category)
    end

    before do
      allow(instance).to receive(:calculate_pattern_score).and_return(0.8, 0.2)
    end

    it "maps patterns to match results" do
      results = instance.send(:process_patterns, [ pattern1, pattern2 ], expense)

      expect(results).to be_an(Array)
      expect(results.size).to eq(1) # Only pattern1 passes threshold
      expect(results.first).to include(
        pattern: pattern1,
        match_score: 0.8,
        match_type: "optimized_match"
      )
    end

    it "filters out patterns with score below 0.3" do
      allow(instance).to receive(:calculate_pattern_score).and_return(0.2, 0.1)

      results = instance.send(:process_patterns, [ pattern1, pattern2 ], expense)

      expect(results).to be_empty
    end

    it "handles empty pattern array" do
      results = instance.send(:process_patterns, [], expense)
      expect(results).to eq([])
    end
  end

  describe "#calculate_pattern_score (private)" do
    let(:category) { build(:category) }
    let(:pattern) do
      double("CategorizationPattern",
             pattern_type: "merchant",
             pattern_value: "starbucks",
             success_rate: 0.9,
             confidence_weight: 0.8,
             category: category)
    end

    context "with merchant pattern" do
      let(:expense) { build(:expense, merchant_name: "Starbucks Coffee") }

      it "calculates score with text similarity" do
        allow(instance).to receive(:text_similarity).with("starbucks", "Starbucks Coffee").and_return(0.7)

        score = instance.send(:calculate_pattern_score, pattern, expense)

        expect(score).to eq(0.9 * 0.8 * 0.7) # success_rate * confidence_weight * similarity
      end

      it "handles nil merchant name" do
        expense.merchant_name = nil

        # When merchant_name is nil, text_similarity returns 0.0
        # So the base_score is multiplied by 0, resulting in 0
        allow(instance).to receive(:text_similarity).and_return(0.0)

        score = instance.send(:calculate_pattern_score, pattern, expense)

        expect(score).to eq(0.0) # base_score * 0 = 0
      end
    end

    context "with keyword pattern" do
      let(:pattern) do
        double("CategorizationPattern",
               pattern_type: "keyword",
               pattern_value: "coffee",
               success_rate: 0.85,
               confidence_weight: 0.75,
               category: category)
      end
      let(:expense) { build(:expense, description: "Morning coffee and snack") }

      it "calculates score with text similarity for description" do
        allow(instance).to receive(:text_similarity).with("coffee", "Morning coffee and snack").and_return(0.5)

        score = instance.send(:calculate_pattern_score, pattern, expense)

        expect(score).to eq(0.85 * 0.75 * 0.5)
      end
    end

    context "with description pattern" do
      let(:pattern) do
        double("CategorizationPattern",
               pattern_type: "description",
               pattern_value: "grocery",
               success_rate: 0.8,
               confidence_weight: 0.7,
               category: category)
      end
      let(:expense) { build(:expense, description: "Weekly grocery shopping") }

      it "calculates score with text similarity" do
        allow(instance).to receive(:text_similarity).with("grocery", "Weekly grocery shopping").and_return(0.6)

        score = instance.send(:calculate_pattern_score, pattern, expense)

        expect(score).to eq(0.8 * 0.7 * 0.6)
      end
    end

    context "with other pattern type" do
      let(:pattern) do
        double("CategorizationPattern",
               pattern_type: "amount",
               pattern_value: "100",
               success_rate: 0.7,
               confidence_weight: 0.6,
               category: category)
      end
      let(:expense) { build(:expense) }

      it "returns base score only" do
        score = instance.send(:calculate_pattern_score, pattern, expense)

        expect(score).to eq(0.7 * 0.6)
      end
    end
  end

  describe "#text_similarity (private)" do
    it "returns 0.0 for blank text1" do
      similarity = instance.send(:text_similarity, "", "hello world")
      expect(similarity).to eq(0.0)
    end

    it "returns 0.0 for blank text2" do
      similarity = instance.send(:text_similarity, "hello world", nil)
      expect(similarity).to eq(0.0)
    end

    it "returns 1.0 for identical texts" do
      similarity = instance.send(:text_similarity, "Hello World", "hello world")
      expect(similarity).to eq(1.0)
    end

    it "calculates Jaccard similarity correctly" do
      # "hello world" and "world peace" share "world"
      # words1 = ["hello", "world"], words2 = ["world", "peace"]
      # intersection = ["world"] (size 1)
      # union = ["hello", "world", "peace"] (size 3)
      # similarity = 1/3 ≈ 0.333

      similarity = instance.send(:text_similarity, "hello world", "world peace")
      expect(similarity).to be_within(0.001).of(0.333)
    end

    it "handles punctuation and special characters" do
      similarity = instance.send(:text_similarity, "coffee & tea", "Coffee, Tea!")

      # Both normalize to ["coffee", "tea"]
      expect(similarity).to eq(1.0)
    end

    it "returns 0.0 for completely different texts" do
      similarity = instance.send(:text_similarity, "apple banana", "car truck")
      expect(similarity).to eq(0.0)
    end

    it "handles empty union gracefully" do
      # When both texts have no valid words (only punctuation),
      # they result in empty sets that are equal
      similarity = instance.send(:text_similarity, "!!!", "???")
      # Empty sets are equal, so similarity is 1.0
      expect(similarity).to eq(1.0)
    end
  end
end

RSpec.describe Categorization::CategorizationJob, type: :job, unit: true do
  let(:expense) { build(:expense, id: 123) }
  let(:category) { build(:category, name: "Food") }
  let(:engine) { instance_double("Categorization::Engine") }
  let(:result) do
    instance_double("Categorization::CategorizationResult",
                    successful?: true,
                    high_confidence?: true,
                    category: category,
                    confidence: 0.95,
                    method: "pattern_matching")
  end

  describe "#perform" do
    before do
      allow(Expense).to receive(:find).with(123).and_return(expense)
      allow(Categorization::Engine).to receive(:new).and_return(engine)
      allow(engine).to receive(:categorize).and_return(result)
    end

    context "with successful high-confidence categorization" do
      it "finds the expense" do
        expect(Expense).to receive(:find).with(123)

        described_class.new.perform(expense_id: 123)
      end

      it "creates a new engine instance" do
        expect(Categorization::Engine).to receive(:new)

        described_class.new.perform(expense_id: 123)
      end

      it "categorizes the expense with options" do
        options = { priority: "high", source: "manual" }

        expect(engine).to receive(:categorize).with(expense, options)

        described_class.new.perform(expense_id: 123, options: options)
      end

      it "updates the expense with categorization results" do
        expect(expense).to receive(:update!).with(
          category: category,
          auto_categorized: true,
          categorization_confidence: 0.95,
          categorization_method: "pattern_matching"
        )

        described_class.new.perform(expense_id: 123)
      end

      it "returns the categorization result" do
        result_value = described_class.new.perform(expense_id: 123)

        expect(result_value).to eq(result)
      end
    end

    context "with successful low-confidence categorization" do
      let(:result) do
        instance_double("Categorization::CategorizationResult",
                        successful?: true,
                        high_confidence?: false,
                        category: category,
                        confidence: 0.45)
      end

      it "does not update the expense" do
        expect(expense).not_to receive(:update!)

        described_class.new.perform(expense_id: 123)
      end

      it "still returns the result" do
        result_value = described_class.new.perform(expense_id: 123)

        expect(result_value).to eq(result)
      end
    end

    context "with unsuccessful categorization" do
      let(:result) do
        instance_double("Categorization::CategorizationResult",
                        successful?: false,
                        high_confidence?: false)
      end

      it "does not update the expense" do
        expect(expense).not_to receive(:update!)

        described_class.new.perform(expense_id: 123)
      end

      it "returns the result" do
        result_value = described_class.new.perform(expense_id: 123)

        expect(result_value).to eq(result)
      end
    end

    context "when expense is not found" do
      before do
        allow(Expense).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)
        allow(Rails.logger).to receive(:error)
      end

      it "logs an error message" do
        expect(Rails.logger).to receive(:error).with("[CategorizationJob] Expense 999 not found")

        described_class.new.perform(expense_id: 999)
      end

      it "does not raise the exception" do
        expect {
          described_class.new.perform(expense_id: 999)
        }.not_to raise_error
      end

      it "returns nil" do
        result = described_class.new.perform(expense_id: 999)

        expect(result).to be_nil
      end
    end

    context "when engine raises an error" do
      before do
        allow(engine).to receive(:categorize).and_raise(StandardError, "Engine error")
      end

      it "propagates the exception" do
        expect {
          described_class.new.perform(expense_id: 123)
        }.to raise_error(StandardError, "Engine error")
      end
    end
  end
end

RSpec.describe Categorization::CircuitBreaker, type: :service, unit: true do
  let(:circuit_breaker) { described_class.new }

  describe "#initialize" do
    it "starts with closed state" do
      expect(circuit_breaker.state).to eq(:closed)
    end

    it "starts with zero failure count" do
      expect(circuit_breaker.failure_count).to eq(0)
    end

    it "starts with nil last failure time" do
      expect(circuit_breaker.last_failure_time).to be_nil
    end

    it "sets failure threshold constant" do
      expect(described_class::FAILURE_THRESHOLD).to eq(5)
    end

    it "sets timeout duration constant" do
      expect(described_class::TIMEOUT_DURATION).to eq(30.seconds)
    end
  end

  describe "#call" do
    context "when circuit is closed" do
      it "executes the block successfully" do
        result = circuit_breaker.call { "success" }

        expect(result).to eq("success")
        expect(circuit_breaker.state).to eq(:closed)
        expect(circuit_breaker.failure_count).to eq(0)
      end

      it "increments failure count on exception" do
        expect {
          circuit_breaker.call { raise StandardError, "test error" }
        }.to raise_error(StandardError, "test error")

        expect(circuit_breaker.failure_count).to eq(1)
        expect(circuit_breaker.state).to eq(:closed)
      end

      it "opens circuit after reaching failure threshold" do
        allow(Rails.logger).to receive(:error)

        5.times do
          expect {
            circuit_breaker.call { raise StandardError, "test error" }
          }.to raise_error(StandardError)
        end

        expect(circuit_breaker.state).to eq(:open)
        expect(circuit_breaker.failure_count).to eq(5)
      end

      it "logs when opening circuit" do
        expect(Rails.logger).to receive(:error).with("[CircuitBreaker] Opening circuit after 5 failures")

        5.times do
          begin
            circuit_breaker.call { raise StandardError }
          rescue StandardError
            # Ignore
          end
        end
      end

      it "records last failure time" do
        frozen_time = Time.current
        allow(Time).to receive(:current).and_return(frozen_time)

        expect {
          circuit_breaker.call { raise StandardError }
        }.to raise_error(StandardError)

        expect(circuit_breaker.last_failure_time).to eq(frozen_time)
      end
    end

    context "when circuit is open" do
      before do
        circuit_breaker.instance_variable_set(:@state, :open)
        circuit_breaker.instance_variable_set(:@last_failure_time, 1.minute.ago)
      end

      context "when timeout has not expired" do
        before do
          allow(Time).to receive(:current).and_return(circuit_breaker.last_failure_time + 10.seconds)
        end

        it "raises CircuitOpenError without executing block" do
          block_executed = false

          expect {
            circuit_breaker.call { block_executed = true }
          }.to raise_error(Categorization::CircuitOpenError, "Circuit breaker is open")

          expect(block_executed).to be false
        end
      end

      context "when timeout has expired" do
        before do
          allow(Time).to receive(:current).and_return(circuit_breaker.last_failure_time + 31.seconds)
        end

        it "transitions to half-open state" do
          circuit_breaker.call { "success" }

          expect(circuit_breaker.state).to eq(:closed)
        end

        it "resets failure count when transitioning to half-open" do
          circuit_breaker.instance_variable_set(:@failure_count, 5)

          circuit_breaker.call { "success" }

          expect(circuit_breaker.failure_count).to eq(0)
        end

        it "executes the block in half-open state" do
          result = circuit_breaker.call { "half-open success" }

          expect(result).to eq("half-open success")
        end
      end
    end

    context "when circuit is half-open" do
      before do
        circuit_breaker.instance_variable_set(:@state, :half_open)
      end

      it "transitions to closed on successful execution" do
        circuit_breaker.call { "success" }

        expect(circuit_breaker.state).to eq(:closed)
        expect(circuit_breaker.failure_count).to eq(0)
      end

      it "increments failure count on exception" do
        expect {
          circuit_breaker.call { raise StandardError }
        }.to raise_error(StandardError)

        expect(circuit_breaker.failure_count).to eq(1)
      end

      it "can reopen if failures continue" do
        allow(Rails.logger).to receive(:error)

        5.times do
          circuit_breaker.instance_variable_set(:@state, :half_open)

          expect {
            circuit_breaker.call { raise StandardError }
          }.to raise_error(StandardError)
        end

        expect(circuit_breaker.state).to eq(:open)
      end
    end

    context "thread safety" do
      it "uses mutex for state changes" do
        mutex = circuit_breaker.instance_variable_get(:@mutex)

        expect(mutex).to receive(:synchronize).at_least(:twice)

        circuit_breaker.call { "success" }
      end

      it "synchronizes failure count increments" do
        mutex = circuit_breaker.instance_variable_get(:@mutex)

        expect(mutex).to receive(:synchronize).at_least(:once)

        expect {
          circuit_breaker.call { raise StandardError }
        }.to raise_error(StandardError)
      end
    end
  end

  describe "#reset!" do
    before do
      # Set up a circuit in open state with failures
      circuit_breaker.instance_variable_set(:@state, :open)
      circuit_breaker.instance_variable_set(:@failure_count, 5)
      circuit_breaker.instance_variable_set(:@last_failure_time, Time.current)
    end

    it "resets state to closed" do
      circuit_breaker.reset!

      expect(circuit_breaker.state).to eq(:closed)
    end

    it "resets failure count to zero" do
      circuit_breaker.reset!

      expect(circuit_breaker.failure_count).to eq(0)
    end

    it "resets last failure time to nil" do
      circuit_breaker.reset!

      expect(circuit_breaker.last_failure_time).to be_nil
    end

    it "uses mutex for thread safety" do
      mutex = circuit_breaker.instance_variable_get(:@mutex)

      expect(mutex).to receive(:synchronize).and_yield

      circuit_breaker.reset!
    end
  end
end

RSpec.describe Categorization::CircuitOpenError, type: :error, unit: true do
  it "is a StandardError subclass" do
    expect(described_class.superclass).to eq(StandardError)
  end

  it "can be raised with a message" do
    expect {
      raise described_class, "Circuit is open"
    }.to raise_error(described_class, "Circuit is open")
  end

  it "can be rescued as StandardError" do
    raised = false

    begin
      raise described_class, "Test"
    rescue StandardError
      raised = true
    end

    expect(raised).to be true
  end
end
