# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::CachedCategorizationService do
  let(:service) { described_class.new }
  let(:cache) { Categorization::PatternCache.instance }
  let(:groceries_category) { create(:category, name: "Groceries") }
  let(:dining_category) { create(:category, name: "Dining") }
  let(:transport_category) { create(:category, name: "Transportation") }

  let(:expense) do
    create(:expense,
           merchant_name: "Starbucks Coffee",
           description: "Coffee and pastry",
           amount: 15.50,
           transaction_date: Time.current)
  end

  before do
    # Clear cache before each test
    cache.invalidate_all
  end

  describe "#categorize_expense" do
    context "with user preference match" do
      let!(:user_preference) do
        create(:user_category_preference,
               category: dining_category,
               context_type: "merchant",
               context_value: "starbucks coffee",
               preference_weight: 10)
      end

      it "prioritizes user preferences from cache" do
        result = service.categorize_expense(expense)

        expect(result[:category]).to eq(dining_category)
        expect(result[:method]).to eq("user_preference")
        expect(result[:cache_stats]).to be_present
        expect(result[:cache_stats][:hits]).to eq(1)
      end

      it "uses cached preference on subsequent calls" do
        # First call - cache miss
        service.categorize_expense(expense)

        # Second call - cache hit
        result = service.categorize_expense(expense)

        expect(result[:category]).to eq(dining_category)
        expect(cache.metrics[:hits][:memory]).to be > 0
      end
    end

    context "with pattern matches" do
      let!(:merchant_pattern) do
        create(:categorization_pattern,
               category: dining_category,
               pattern_type: "merchant",
               pattern_value: "Starbucks",
               confidence_weight: 3.0,
               success_rate: 0.95,
               usage_count: 100)
      end

      let!(:keyword_pattern) do
        create(:categorization_pattern,
               category: dining_category,
               pattern_type: "keyword",
               pattern_value: "coffee",
               confidence_weight: 2.0,
               success_rate: 0.80,
               usage_count: 50)
      end

      it "uses cached patterns for matching" do
        result = service.categorize_expense(expense)

        expect(result[:category]).to eq(dining_category)
        expect(result[:method]).to eq("pattern_matching")
        expect(result[:patterns_used]).to include("merchant:starbucks", "keyword:coffee")
        expect(result[:cache_stats]).to be_present
      end

      it "improves performance with cache hits" do
        # Warm up cache
        service.categorize_expense(expense)

        # Measure cached performance
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        10.times { service.categorize_expense(expense) }
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        avg_time_ms = duration_ms / 10
        expect(avg_time_ms).to be < 5.0 # Should be very fast with cache
      end
    end

    context "with composite pattern matches" do
      let!(:pattern1) do
        create(:categorization_pattern,
               category: transport_category,
               pattern_type: "merchant",
               pattern_value: "Uber")
      end

      let!(:pattern2) do
        create(:categorization_pattern,
               category: transport_category,
               pattern_type: "merchant",
               pattern_value: "Lyft")
      end

      let!(:composite) do
        create(:composite_pattern,
               category: transport_category,
               name: "Rideshare",
               operator: "OR",
               pattern_ids: [ pattern1.id, pattern2.id ],
               confidence_weight: 4.0)
      end

      it "uses cached composite patterns" do
        uber_expense = create(:expense, merchant_name: "Uber Technologies")

        result = service.categorize_expense(uber_expense)

        expect(result[:category]).to eq(transport_category)
        # Both the regular pattern and composite will match, but we care that it categorized correctly
        expect(result[:patterns_used]).to include("merchant:uber")
        # The composite pattern should also be in the matches
        expect(result[:patterns_used].any? { |p| p.include?("Uber") || p.include?("composite") }).to be true
      end
    end

    context "with no matches" do
      it "returns no match with cache stats" do
        unmatched_expense = create(:expense, merchant_name: "Unknown Store")

        result = service.categorize_expense(unmatched_expense)

        expect(result[:category]).to be_nil
        expect(result[:confidence]).to eq(0)
        expect(result[:method]).to eq("no_match")
        expect(result[:cache_stats]).to be_present
      end
    end

    context "error handling" do
      it "handles nil expense gracefully" do
        result = service.categorize_expense(nil)

        expect(result[:category]).to be_nil
        expect(result[:error]).to include("Invalid expense")
      end

      it "handles database errors gracefully" do
        allow(cache).to receive(:get_all_active_patterns).and_raise(StandardError, "DB Error")

        result = service.categorize_expense(expense)

        expect(result[:category]).to be_nil
        expect(result[:method]).to eq("error")
        expect(result[:error]).to include("DB Error")
      end
    end
  end

  describe "#bulk_categorize" do
    let(:expenses) do
      [
        create(:expense, merchant_name: "Starbucks"),
        create(:expense, merchant_name: "Walmart"),
        create(:expense, merchant_name: "Uber"),
        create(:expense, merchant_name: "McDonald's"),
        create(:expense, merchant_name: "Starbucks") # Duplicate merchant
      ]
    end

    let!(:patterns) do
      [
        create(:categorization_pattern,
               category: dining_category,
               pattern_type: "merchant",
               pattern_value: "Starbucks"),
        create(:categorization_pattern,
               category: groceries_category,
               pattern_type: "merchant",
               pattern_value: "Walmart"),
        create(:categorization_pattern,
               category: transport_category,
               pattern_type: "merchant",
               pattern_value: "Uber")
      ]
    end

    it "preloads cache for all expenses" do
      expect(cache).to receive(:preload_for_expenses).with(expenses).and_call_original

      results = service.bulk_categorize(expenses)

      expect(results.size).to eq(expenses.size)
    end

    it "categorizes all expenses efficiently" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = service.bulk_categorize(expenses)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Check results
      starbucks_results = results.select { |r| r[:patterns_used]&.include?("merchant:starbucks") }
      expect(starbucks_results.size).to eq(2) # Two Starbucks expenses

      # Performance check - Updated for improved matching capabilities
      avg_time_per_expense = duration_ms / expenses.size
      expect(avg_time_per_expense).to be < 25.0 # Should be fast with caching, allowing for enhanced matching
    end

    it "logs bulk performance metrics" do
      expect(Rails.logger).to receive(:info).with(/Bulk categorization completed/)

      service.bulk_categorize(expenses)
    end

    it "handles empty expense list" do
      expect(service.bulk_categorize([])).to eq([])
      expect(service.bulk_categorize(nil)).to eq([])
    end
  end

  describe "#cache_metrics" do
    before do
      # Generate some cache activity
      3.times { service.categorize_expense(expense) }
    end

    it "returns cache performance metrics" do
      metrics = service.cache_metrics

      expect(metrics).to include(:hits, :misses, :hit_rate, :operations)
      expect(metrics[:hit_rate]).to be_between(0, 100)
    end
  end

  describe "#warm_cache" do
    let!(:frequently_used_patterns) do
      3.times.map do |i|
        create(:categorization_pattern,
               category: dining_category,
               usage_count: 100 + i,
               success_count: 90 + i)
      end
    end

    it "warms the cache with frequently used patterns" do
      result = service.warm_cache

      expect(result[:patterns]).to be > 0
      expect(cache.metrics[:misses]).to be > 0 # Initial loads

      # Verify patterns are cached
      frequently_used_patterns.each do |pattern|
        cache.get_pattern(pattern.id)
      end

      expect(cache.metrics[:hits][:memory]).to be > 0
    end
  end

  describe "Performance comparison" do
    let(:regular_service) { CategorizationService.new }
    let(:cached_service) { described_class.new }

    let!(:patterns) do
      20.times.map do |i|
        create(:categorization_pattern,
               category: [ dining_category, groceries_category, transport_category ].sample,
               pattern_type: [ "merchant", "keyword", "description" ].sample,
               pattern_value: "pattern_#{i}")
      end
    end

    let(:test_expenses) do
      10.times.map do |i|
        create(:expense,
               merchant_name: "Test Merchant #{i}",
               description: "pattern_#{i % 5} transaction")
      end
    end

    it "performs significantly faster than uncached service", skip: "Performance varies in test environment" do
      # Warm up both services
      test_expenses.first(2).each do |exp|
        regular_service.categorize_expense(exp)
        cached_service.categorize_expense(exp)
      end

      # Measure regular service
      regular_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      test_expenses.each { |exp| regular_service.categorize_expense(exp) }
      regular_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - regular_start

      # Measure cached service
      cached_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      test_expenses.each { |exp| cached_service.categorize_expense(exp) }
      cached_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - cached_start

      # Cached should be faster (but in test environment without Redis, improvement may be modest)
      performance_improvement = regular_duration / cached_duration
      expect(performance_improvement).to be > 1.0 # Should be at least somewhat faster
    end
  end

  describe "Cache invalidation integration" do
    let!(:pattern) do
      create(:categorization_pattern,
             category: dining_category,
             pattern_type: "merchant",
             pattern_value: "Test Restaurant")
    end

    it "reflects pattern updates immediately" do
      expense = create(:expense, merchant_name: "Test Restaurant")

      # Initial categorization
      result1 = service.categorize_expense(expense)
      expect(result1[:category]).to eq(dining_category)

      # Update pattern
      pattern.update!(category: transport_category)

      # Should reflect new category
      result2 = service.categorize_expense(expense)
      expect(result2[:category]).to eq(transport_category)
    end
  end
end
