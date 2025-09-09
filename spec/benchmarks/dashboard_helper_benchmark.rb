# frozen_string_literal: true

require "rails_helper"
require "benchmark/ips"

RSpec.describe "DashboardHelper Performance Benchmark", type: :benchmark do
  before(:all) do
    # Create test data
    ActiveRecord::Base.transaction do
      # Create categories
      5.times { |i| Category.create!(name: "Category #{i}", icon: "icon#{i}") }

      # Create expenses
      1000.times do |i|
        Expense.create!(
          description: "Expense #{i}",
          amount: rand(100..10000),
          currency: [ "crc", "usd", "eur" ].sample,
          transaction_date: rand(30.days.ago..Time.current),
          category_id: [ nil, *Category.pluck(:id) ].sample,
          merchant_name: "Merchant #{i % 50}",
          created_at: rand(30.days.ago..Time.current),
          updated_at: rand(1.hour.ago..Time.current)
        )
      end

      # Create patterns
      100.times do |i|
        CategorizationPattern.create!(
          pattern_type: [ "merchant", "category", "amount" ].sample,
          pattern_value: "pattern_#{i}",
          category_id: Category.pluck(:id).sample,
          confidence: rand(0.5..1.0),
          active: [ true, false ].sample,
          created_at: rand(48.hours.ago..Time.current),
          updated_at: rand(24.hours.ago..Time.current)
        )
      end
    end
  end

  after(:all) do
    # Clean up test data
    ActiveRecord::Base.transaction do
      CategorizationPattern.delete_all
      Expense.delete_all
      Category.delete_all
    end
  end

  describe "Query Performance Comparison" do
    it "benchmarks categorization_metrics" do
      puts "\n=== Categorization Metrics Performance ==="

      Benchmark.ips do |x|
        x.report("Original implementation") do
          Categorization::Monitoring::DashboardHelper.categorization_metrics
        end

        x.report("Optimized implementation") do
          Categorization::Monitoring::DashboardHelperOptimized.categorization_metrics_optimized
        end

        x.compare!
      end
    end

    it "benchmarks pattern_metrics" do
      puts "\n=== Pattern Metrics Performance ==="

      Benchmark.ips do |x|
        x.report("Original implementation") do
          Categorization::Monitoring::DashboardHelper.pattern_metrics
        end

        x.report("Optimized implementation") do
          Categorization::Monitoring::DashboardHelperOptimized.pattern_metrics_optimized
        end

        x.compare!
      end
    end

    it "benchmarks learning_metrics" do
      puts "\n=== Learning Metrics Performance ==="

      Benchmark.ips do |x|
        x.report("Original implementation") do
          Categorization::Monitoring::DashboardHelper.learning_metrics
        end

        x.report("Optimized implementation") do
          Categorization::Monitoring::DashboardHelperOptimized.learning_metrics_optimized
        end

        x.compare!
      end
    end

    it "measures query counts" do
      puts "\n=== Query Count Analysis ==="

      # Measure original implementation
      original_queries = []
      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        original_queries << event.payload[:sql] unless event.payload[:sql].match?(/SCHEMA|TRANSACTION/)
      end

      Categorization::Monitoring::DashboardHelper.categorization_metrics
      Categorization::Monitoring::DashboardHelper.pattern_metrics

      original_count = original_queries.size
      ActiveSupport::Notifications.unsubscribe("sql.active_record")

      # Measure optimized implementation
      optimized_queries = []
      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        optimized_queries << event.payload[:sql] unless event.payload[:sql].match?(/SCHEMA|TRANSACTION/)
      end

      Rails.cache.clear # Clear cache to ensure fair comparison
      Categorization::Monitoring::DashboardHelperOptimized.categorization_metrics_optimized
      Categorization::Monitoring::DashboardHelperOptimized.pattern_metrics_optimized

      optimized_count = optimized_queries.size
      ActiveSupport::Notifications.unsubscribe("sql.active_record")

      puts "Original implementation: #{original_count} queries"
      puts "Optimized implementation: #{optimized_count} queries"
      puts "Reduction: #{((1 - optimized_count.to_f / original_count) * 100).round(2)}%"

      expect(optimized_count).to be < original_count
    end
  end

  describe "Concurrent Access Performance" do
    it "benchmarks thread safety" do
      puts "\n=== Concurrent Access Performance ==="

      thread_count = 10
      iterations = 100

      # Test original implementation
      original_errors = []
      original_time = Benchmark.realtime do
        threads = thread_count.times.map do
          Thread.new do
            iterations.times do
              begin
                Categorization::Monitoring::DashboardHelper.system_metrics
              rescue => e
                original_errors << e
              end
            end
          end
        end
        threads.each(&:join)
      end

      # Test optimized implementation
      optimized_errors = []
      optimized_time = Benchmark.realtime do
        threads = thread_count.times.map do
          Thread.new do
            iterations.times do
              begin
                Categorization::Monitoring::DashboardHelperOptimized.system_metrics_safe
              rescue => e
                optimized_errors << e
              end
            end
          end
        end
        threads.each(&:join)
      end

      puts "Original: #{original_time.round(3)}s with #{original_errors.size} errors"
      puts "Optimized: #{optimized_time.round(3)}s with #{optimized_errors.size} errors"
      puts "Speed improvement: #{((original_time / optimized_time - 1) * 100).round(2)}%"

      expect(optimized_errors.size).to eq(0)
      expect(optimized_time).to be < original_time
    end
  end

  describe "Cache Effectiveness" do
    it "measures cache hit rate impact" do
      puts "\n=== Cache Effectiveness ==="

      # Clear cache
      Rails.cache.clear

      # First call (cache miss)
      miss_time = Benchmark.realtime do
        Categorization::Monitoring::DashboardHelperOptimized.metrics_summary
      end

      # Subsequent calls (cache hits)
      hit_times = []
      5.times do
        hit_times << Benchmark.realtime do
          Categorization::Monitoring::DashboardHelperOptimized.metrics_summary
        end
      end

      avg_hit_time = hit_times.sum / hit_times.size

      puts "Cache miss time: #{(miss_time * 1000).round(2)}ms"
      puts "Average cache hit time: #{(avg_hit_time * 1000).round(2)}ms"
      puts "Speed improvement with cache: #{((miss_time / avg_hit_time - 1) * 100).round(2)}%"

      expect(avg_hit_time).to be < (miss_time * 0.1) # Should be at least 10x faster
    end
  end
end
