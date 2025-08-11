# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'
require 'memory_profiler'

RSpec.describe "Categorization Load Testing", type: :performance do
  let(:engine) { Categorization::Engine.new }

  describe "high volume categorization" do
    before do
      # Create test categories
      @food_category = create(:category, name: "Food & Dining")
      @transport_category = create(:category, name: "Transportation")
      @shopping_category = create(:category, name: "Shopping")
      @utilities_category = create(:category, name: "Utilities")

      # Create patterns for better success rates
      create_test_patterns
    end

    it "handles 1,000 expenses under performance targets" do
      # Start with smaller load for CI
      expense_count = 1000
      expenses = create_diverse_expenses(expense_count)

      results = []
      memory_usage = []
      gc_stats_before = GC.stat

      report = MemoryProfiler.report do
        benchmark = Benchmark.realtime do
          expenses.each_with_index do |expense, index|
            result = engine.categorize(expense)
            results << result

            # Sample memory usage every 200 operations
            if index % 200 == 0
              memory_usage << current_memory_usage_mb
            end
          end
        end

        # Performance assertions
        avg_time_ms = (benchmark / expenses.size) * 1000
        expect(avg_time_ms).to be < 15, "Average time: #{avg_time_ms.round(2)}ms (target: <15ms)"

        # Success rate assertions - engine returns CategorizationResult objects
        successful_results = results.count { |r| r.present? && r.respond_to?(:successful?) && r.successful? }
        success_rate = successful_results / results.size.to_f

        expect(success_rate).to be > 0.6, "Success rate: #{(success_rate * 100).round}% (target: >60%)"

        # Memory usage assertions - adjust for test environment overhead
        max_memory_mb = memory_usage.max || current_memory_usage_mb
        expect(max_memory_mb).to be < 600, "Max memory: #{max_memory_mb.round}MB (target: <600MB for test)"

        puts "\n=== Load Test Results (#{expense_count} expenses) ==="
        puts "  Total time: #{benchmark.round(2)}s"
        puts "  Average time per expense: #{avg_time_ms.round(2)}ms"
        puts "  Success rate: #{(success_rate * 100).round}%"
        puts "  Max memory usage: #{max_memory_mb.round}MB"
        puts "  Categorized expenses: #{successful_results}"
      end

      # Memory leak detection - adjust for test environment overhead
      allocated_mb = report.total_allocated_memsize / (1024 * 1024)
      expect(allocated_mb).to be < 400, "Memory allocated: #{allocated_mb.round}MB (target: <400MB for 1k test)"

      puts "  Memory allocated during test: #{allocated_mb.round}MB"
    end

    it "handles 10,000 expenses under performance targets", :slow do
      # Full load test (skip in CI unless specifically requested)
      skip "Skipping large load test unless FULL_LOAD_TEST=true" unless ENV['FULL_LOAD_TEST'] == 'true'

      expense_count = 10_000
      expenses = create_diverse_expenses(expense_count)

      results = []
      memory_usage = []
      p99_times = []

      report = MemoryProfiler.report do
        total_benchmark = Benchmark.realtime do
          expenses.each_with_index do |expense, index|
            # Measure individual categorization time for P99 calculation
            individual_time = Benchmark.realtime do
              result = engine.categorize(expense)
              results << result
            end

            p99_times << (individual_time * 1000) # Convert to milliseconds

            # Sample memory usage every 1000 operations
            if index % 1000 == 0
              memory_usage << current_memory_usage_mb
              puts "  Processed #{index + 1} expenses..." if index > 0
            end
          end
        end

        # Calculate P99 latency
        sorted_times = p99_times.sort
        p99_index = (sorted_times.length * 0.99).ceil - 1
        p99_latency = sorted_times[p99_index]

        # Performance assertions
        avg_time_ms = (total_benchmark / expenses.size) * 1000
        expect(avg_time_ms).to be < 10, "Average time: #{avg_time_ms.round(2)}ms (target: <10ms)"
        expect(p99_latency).to be < 15, "P99 latency: #{p99_latency.round(2)}ms (target: <15ms)"

        # Success rate assertions - engine returns CategorizationResult objects
        successful_results = results.count { |r| r.present? && r.respond_to?(:successful?) && r.successful? }
        success_rate = successful_results / results.size.to_f
        expect(success_rate).to be > 0.7, "Success rate: #{(success_rate * 100).round}% (target: >70%)"

        # Memory usage assertions - adjust for large scale test
        max_memory_mb = memory_usage.max
        expect(max_memory_mb).to be < 1000, "Max memory: #{max_memory_mb.round}MB (target: <1GB for 10k test)"

        puts "\n=== Full Load Test Results (#{expense_count} expenses) ==="
        puts "  Total time: #{total_benchmark.round(2)}s"
        puts "  Average time per expense: #{avg_time_ms.round(2)}ms"
        puts "  P99 latency: #{p99_latency.round(2)}ms"
        puts "  Success rate: #{(success_rate * 100).round}%"
        puts "  Max memory usage: #{max_memory_mb.round}MB"
        puts "  Categorized expenses: #{successful_results}"
      end

      # Memory leak detection - adjust for large scale test
      allocated_mb = report.total_allocated_memsize / (1024 * 1024)
      expect(allocated_mb).to be < 2000, "Memory allocated: #{allocated_mb.round}MB (target: <2GB for 10k test)"

      puts "  Memory allocated during test: #{allocated_mb.round}MB"
    end
  end

  describe "concurrent categorization" do
    it "handles concurrent requests without performance degradation" do
      expenses = create_diverse_expenses(100)
      results = {}
      threads = []

      # Test with 5 concurrent threads
      5.times do |thread_id|
        threads << Thread.new do
          thread_results = []
          thread_expenses = expenses.sample(20) # Each thread processes 20 expenses

          benchmark = Benchmark.realtime do
            thread_expenses.each do |expense|
              result = engine.categorize(expense)
              thread_results << result
            end
          end

          results[thread_id] = {
            time: benchmark,
            results: thread_results,
            avg_time_ms: (benchmark / thread_expenses.size) * 1000
          }
        end
      end

      threads.each(&:join)

      # Verify all threads completed within performance targets
      results.each do |thread_id, data|
        expect(data[:avg_time_ms]).to be < 20,
               "Thread #{thread_id} avg time: #{data[:avg_time_ms].round(2)}ms (target: <20ms)"
      end

      total_avg_time = results.values.map { |d| d[:avg_time_ms] }.sum / results.size
      puts "\n=== Concurrent Test Results ==="
      puts "  Threads: #{threads.size}"
      puts "  Average time across threads: #{total_avg_time.round(2)}ms"
    end
  end

  private

  def create_test_patterns
    # High-performing merchant patterns
    [
      { value: "starbucks", category: @food_category },
      { value: "mcdonald", category: @food_category },
      { value: "subway", category: @food_category },
      { value: "uber", category: @transport_category },
      { value: "lyft", category: @transport_category },
      { value: "shell", category: @transport_category },
      { value: "amazon", category: @shopping_category },
      { value: "walmart", category: @shopping_category },
      { value: "target", category: @shopping_category },
      { value: "pgande", category: @utilities_category },
      { value: "comcast", category: @utilities_category }
    ].each do |pattern_data|
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: pattern_data[:value],
             category: pattern_data[:category],
             confidence_weight: 3.0,
             success_rate: 0.9,
             usage_count: 50,
             success_count: 45,
             active: true)
    end

    # Description patterns
    [
      { value: "coffee", category: @food_category },
      { value: "gas", category: @transport_category },
      { value: "grocery", category: @shopping_category },
      { value: "electric", category: @utilities_category }
    ].each do |pattern_data|
      create(:categorization_pattern,
             pattern_type: "description",
             pattern_value: pattern_data[:value],
             category: pattern_data[:category],
             confidence_weight: 2.0,
             success_rate: 0.8,
             usage_count: 30,
             success_count: 24,
             active: true)
    end
  end

  def create_diverse_expenses(count)
    test_data = test_expense_data

    # Create email account once for all expenses (skip if encryption keys not configured)
    email_account = begin
      create(:email_account)
    rescue ActiveRecord::Encryption::Errors::Configuration
      # If encryption is not configured in test, create a simple email account
      EmailAccount.find_or_create_by(email: "performance_test@example.com") do |ea|
        ea.provider = "gmail"
        ea.bank_name = "Test Bank"
        ea.active = true
      end
    end

    count.times.map do |index|
      data = test_data[index % test_data.size]

      create(:expense,
             merchant_name: data[:merchant],
             description: data[:description],
             amount: rand(data[:min_amount]..data[:max_amount]).round(2),
             transaction_date: rand(30.days.ago..Time.current),
             email_account: email_account)
    end
  end

  def test_expense_data
    [
      { merchant: "STARBUCKS COFFEE #1234", description: "Coffee and pastry", min_amount: 3.50, max_amount: 15.00 },
      { merchant: "MCDONALD'S #5678", description: "Fast food lunch", min_amount: 5.00, max_amount: 12.00 },
      { merchant: "SUBWAY #9012", description: "Sandwich meal", min_amount: 6.00, max_amount: 14.00 },
      { merchant: "UBER *TRIP", description: "Rideshare service", min_amount: 8.00, max_amount: 35.00 },
      { merchant: "LYFT *RIDE", description: "Transportation", min_amount: 7.00, max_amount: 30.00 },
      { merchant: "SHELL OIL 574496858", description: "Gas station", min_amount: 25.00, max_amount: 75.00 },
      { merchant: "AMAZON.COM*MK8T92QL0", description: "Online purchase", min_amount: 10.00, max_amount: 200.00 },
      { merchant: "WALMART SUPERCENTER", description: "Grocery shopping", min_amount: 15.00, max_amount: 150.00 },
      { merchant: "TARGET 00012345", description: "Department store", min_amount: 12.00, max_amount: 100.00 },
      { merchant: "PG&E PAYMENT", description: "Electric bill", min_amount: 80.00, max_amount: 200.00 },
      { merchant: "COMCAST CABLE", description: "Internet service", min_amount: 60.00, max_amount: 120.00 },
      { merchant: "WHOLE FOODS MKT", description: "Organic groceries", min_amount: 20.00, max_amount: 80.00 },
      { merchant: "CHEVRON STATION", description: "Gasoline", min_amount: 30.00, max_amount: 70.00 },
      { merchant: "COSTCO WHOLESALE", description: "Bulk shopping", min_amount: 40.00, max_amount: 300.00 },
      { merchant: "HOME DEPOT", description: "Home improvement", min_amount: 15.00, max_amount: 150.00 },
      { merchant: "SAFEWAY STORE", description: "Grocery store", min_amount: 25.00, max_amount: 120.00 },
      { merchant: "CVS PHARMACY", description: "Pharmacy", min_amount: 10.00, max_amount: 50.00 },
      { merchant: "APPLE STORE", description: "Electronics", min_amount: 50.00, max_amount: 500.00 },
      { merchant: "NETFLIX SUBSCRIPTION", description: "Streaming service", min_amount: 10.00, max_amount: 20.00 },
      { merchant: "SPOTIFY PREMIUM", description: "Music streaming", min_amount: 10.00, max_amount: 15.00 }
    ]
  end

  def current_memory_usage_mb
    # Get current memory usage in MB
    `ps -o pid,rss -p #{Process.pid}`.split.last.to_i / 1024.0
  rescue
    # Fallback using GC stats if ps command fails
    GC.stat[:heap_allocated_pages] * 65536 / (1024 * 1024)
  end
end
