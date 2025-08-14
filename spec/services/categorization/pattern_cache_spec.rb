# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternCache do
  let(:cache) { described_class.new }
  let(:category) { create(:category, name: "Food & Dining") }
  let(:pattern) do
    create(:categorization_pattern,
           category: category,
           pattern_type: "merchant",
           pattern_value: "Starbucks",
           confidence_weight: 3.0,
           success_rate: 0.95,
           usage_count: 100)
  end
  let(:composite) do
    create(:composite_pattern,
           category: category,
           name: "Coffee shops",
           operator: "OR",
           pattern_ids: [ pattern.id ])
  end
  let(:user_preference) do
    create(:user_category_preference,
           category: category,
           context_type: "merchant",
           context_value: "starbucks coffee")
  end

  before do
    # Clear cache before each test
    cache.invalidate_all
    # Reset singleton for test isolation
    Categorization::PatternCache.instance_variable_set(:@instance, nil)
  end

  describe "#initialize" do
    it "initializes with memory cache" do
      expect(cache.instance_variable_get(:@memory_cache)).to be_present
    end

    it "detects Redis availability" do
      skip "Redis not available in test" unless defined?(Redis)

      allow_any_instance_of(Redis).to receive(:ping).and_return("PONG")
      new_cache = described_class.new
      expect(new_cache.instance_variable_get(:@redis_available)).to be true
    end

    it "handles Redis unavailability gracefully" do
      skip "Redis not available in test" unless defined?(Redis)

      allow_any_instance_of(Redis).to receive(:ping).and_raise(StandardError, "Connection failed")
      new_cache = described_class.new
      expect(new_cache.instance_variable_get(:@redis_available)).to be false
    end
  end

  describe "#get_pattern" do
    context "with no cached data" do
      it "fetches from database and caches result" do
        expect(CategorizationPattern).to receive(:active).and_call_original

        result = cache.get_pattern(pattern.id)

        expect(result).to eq(pattern)
        expect(cache.metrics[:misses]).to eq(1)
      end

      it "returns nil for non-existent pattern" do
        result = cache.get_pattern(999999)
        expect(result).to be_nil
      end
    end

    context "with cached data" do
      before { cache.get_pattern(pattern.id) }

      it "returns from memory cache on second call" do
        expect(CategorizationPattern).not_to receive(:active)

        result = cache.get_pattern(pattern.id)

        expect(result.id).to eq(pattern.id)
        expect(cache.metrics[:hits][:memory]).to be >= 1
      end

      it "measures performance under 1ms for cache hits" do
        # Warm up cache
        cache.get_pattern(pattern.id)

        # Measure cache hit performance
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        10.times { cache.get_pattern(pattern.id) }
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        avg_time_ms = duration_ms / 10
        expect(avg_time_ms).to be < 1.0
      end
    end
  end

  describe "#get_patterns" do
    let(:patterns) do
      3.times.map do |i|
        create(:categorization_pattern,
               category: category,
               pattern_type: "keyword",
               pattern_value: "test_#{i}")
      end
    end

    it "batch fetches multiple patterns efficiently" do
      pattern_ids = patterns.map(&:id)

      result = cache.get_patterns(pattern_ids)

      expect(result.map(&:id)).to match_array(pattern_ids)
    end

    it "handles mixed cached and uncached patterns" do
      # Cache first pattern
      cache.get_pattern(patterns.first.id)

      # Fetch all patterns
      result = cache.get_patterns(patterns.map(&:id))

      expect(result.size).to eq(3)
      expect(cache.metrics[:hits][:memory]).to be >= 1
    end

    it "returns empty array for nil or empty input" do
      expect(cache.get_patterns(nil)).to eq([])
      expect(cache.get_patterns([])).to eq([])
    end
  end

  describe "#get_patterns_by_type" do
    let!(:merchant_patterns) do
      2.times.map do |i|
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "merchant_#{i}",
               category: category)
      end
    end

    let!(:keyword_patterns) do
      create(:categorization_pattern,
             pattern_type: "keyword",
             pattern_value: "food",
             category: category)
    end

    it "fetches and caches patterns by type" do
      result = cache.get_patterns_by_type("merchant")

      expect(result.size).to eq(2)
      expect(result.map(&:pattern_type).uniq).to eq([ "merchant" ])
    end

    it "uses cache on subsequent calls" do
      cache.get_patterns_by_type("merchant")

      expect(CategorizationPattern).not_to receive(:active)
      result = cache.get_patterns_by_type("merchant")

      expect(result.size).to eq(2)
    end
  end

  describe "#get_composite_pattern" do
    it "fetches and caches composite pattern" do
      result = cache.get_composite_pattern(composite.id)

      expect(result).to eq(composite)
      expect(cache.metrics[:misses]).to eq(1)
    end

    it "returns from cache on subsequent calls" do
      cache.get_composite_pattern(composite.id)

      expect(CompositePattern).not_to receive(:active)
      result = cache.get_composite_pattern(composite.id)

      expect(result.id).to eq(composite.id)
      expect(cache.metrics[:hits][:memory]).to be >= 1
    end
  end

  describe "#get_user_preference" do
    it "fetches and caches user preference by merchant name" do
      # Ensure user_preference is created
      user_preference

      result = cache.get_user_preference("starbucks coffee")

      expect(result).to eq(user_preference)
    end

    it "normalizes merchant name for lookup" do
      # Ensure user_preference is created
      user_preference

      cache.get_user_preference("STARBUCKS COFFEE")

      result = cache.get_user_preference("  starbucks coffee  ")
      expect(cache.metrics[:hits][:memory]).to be >= 1
    end

    it "returns nil for blank merchant name" do
      expect(cache.get_user_preference("")).to be_nil
      expect(cache.get_user_preference(nil)).to be_nil
    end
  end

  describe "#get_all_active_patterns" do
    let!(:active_patterns) do
      3.times.map { create(:categorization_pattern, active: true, category: category) }
    end

    let!(:inactive_pattern) do
      create(:categorization_pattern, active: false, category: category)
    end

    it "fetches only active patterns" do
      result = cache.get_all_active_patterns

      expect(result.size).to eq(active_patterns.size)
      expect(result.map(&:active).uniq).to eq([ true ])
    end

    it "includes category association" do
      result = cache.get_all_active_patterns

      # Check that categories are loaded
      expect(result.first.association(:category).loaded?).to be true
    end
  end

  describe "#invalidate" do
    context "with CategorizationPattern" do
      before { cache.get_pattern(pattern.id) }

      it "invalidates pattern cache entry" do
        expect(cache.metrics[:hits][:memory]).to eq(0)
        cache.get_pattern(pattern.id) # Should hit cache
        expect(cache.metrics[:hits][:memory]).to eq(1)

        cache.invalidate(pattern)

        # Next fetch should miss cache
        cache.get_pattern(pattern.id)
        expect(cache.metrics[:misses]).to be >= 2
      end

      it "invalidates related type cache" do
        cache.get_patterns_by_type("merchant")
        cache.invalidate(pattern)

        # Should refetch from database
        expect(CategorizationPattern).to receive(:active).and_call_original
        cache.get_patterns_by_type("merchant")
      end
    end

    context "with CompositePattern" do
      before { cache.get_composite_pattern(composite.id) }

      it "invalidates composite cache entry" do
        cache.invalidate(composite)

        # Next fetch should miss cache
        expect(CompositePattern).to receive(:active).and_call_original
        cache.get_composite_pattern(composite.id)
      end
    end

    context "with UserCategoryPreference" do
      before { cache.get_user_preference("starbucks coffee") }

      it "invalidates user preference cache entry" do
        cache.invalidate(user_preference)

        # Next fetch should miss cache
        expect(UserCategoryPreference).to receive(:find_by).and_call_original
        cache.get_user_preference("starbucks coffee")
      end
    end
  end

  describe "#invalidate_all" do
    before do
      cache.get_pattern(pattern.id)
      cache.get_composite_pattern(composite.id)
      cache.get_user_preference("starbucks coffee")
    end

    it "clears all cache entries" do
      initial_hits = cache.metrics[:hits][:memory]
      expect(initial_hits).to eq(0)

      # Verify cache is populated
      cache.get_pattern(pattern.id)
      expect(cache.metrics[:hits][:memory]).to be > initial_hits

      cache.invalidate_all

      # All subsequent calls should miss
      cache.get_pattern(pattern.id)
      cache.get_composite_pattern(composite.id)
      cache.get_user_preference("starbucks coffee")

      expect(cache.metrics[:misses]).to be >= 3
    end
  end

  describe "#warm_cache" do
    let!(:frequently_used_patterns) do
      3.times.map do |i|
        create(:categorization_pattern,
               category: category,
               usage_count: 100 + i,
               success_count: 90 + i)
      end
    end

    let!(:composite_patterns) do
      2.times.map { create(:composite_pattern, category: category) }
    end

    it "preloads frequently used patterns" do
      # Ensure patterns exist
      frequently_used_patterns
      composite_patterns

      result = cache.warm_cache

      expect(result[:patterns]).to be > 0
      expect(result[:composites]).to be > 0

      # Verify patterns are cached
      frequently_used_patterns.each do |pattern|
        cache.get_pattern(pattern.id)
      end

      expect(cache.metrics[:hits][:memory]).to be >= frequently_used_patterns.size
    end

    it "handles errors gracefully" do
      allow(CategorizationPattern).to receive(:active).and_raise(StandardError, "DB Error")

      result = cache.warm_cache

      expect(result[:error]).to include("DB Error")
    end
  end

  describe "#metrics" do
    before do
      cache.get_pattern(pattern.id)
      cache.get_pattern(pattern.id) # Hit
      cache.get_pattern(999999) # Miss
    end

    it "returns comprehensive metrics" do
      metrics = cache.metrics

      expect(metrics).to include(
        :hits,
        :misses,
        :hit_rate,
        :operations,
        :memory_cache_entries,
        :redis_available,
        :configuration
      )
    end

    it "calculates hit rate correctly" do
      expect(cache.hit_rate).to be_between(0, 100)
    end

    it "tracks operation performance" do
      metrics = cache.metrics

      expect(metrics[:operations]).to have_key("get_pattern")
      expect(metrics[:operations]["get_pattern"]).to include(
        :count,
        :avg_ms,
        :min_ms,
        :max_ms
      )
    end
  end

  describe "#preload_for_expenses" do
    let(:expenses) do
      [
        build(:expense, merchant_name: "Starbucks"),
        build(:expense, merchant_name: "McDonald's"),
        build(:expense, merchant_name: "Starbucks") # Duplicate
      ]
    end

    it "preloads unique merchant preferences" do
      expect(cache).to receive(:get_user_preference).with("Starbucks").once
      expect(cache).to receive(:get_user_preference).with("McDonald's").once
      expect(cache).to receive(:get_all_active_patterns).once

      cache.preload_for_expenses(expenses)
    end

    it "handles empty expense list" do
      expect { cache.preload_for_expenses([]) }.not_to raise_error
      expect { cache.preload_for_expenses(nil) }.not_to raise_error
    end
  end

  describe "Performance benchmarks" do
    let(:patterns) do
      50.times.map do |i|
        create(:categorization_pattern,
               category: category,
               pattern_type: [ "merchant", "keyword", "description" ].sample,
               pattern_value: "test_pattern_#{i}")
      end
    end

    it "achieves < 1ms response time for cached lookups" do
      # Warm up cache
      patterns.each { |p| cache.get_pattern(p.id) }

      # Measure performance
      timings = []
      patterns.sample(10).each do |pattern|
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        cache.get_pattern(pattern.id)
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        timings << duration_ms
      end

      avg_time = timings.sum / timings.size
      max_time = timings.max

      expect(avg_time).to be < 1.0, "Average lookup time #{avg_time.round(3)}ms exceeds 1ms target"
      expect(max_time).to be < 2.0, "Max lookup time #{max_time.round(3)}ms exceeds 2ms threshold"
    end

    it "handles high concurrency" do
      threads = 10.times.map do
        Thread.new do
          5.times do
            cache.get_pattern(patterns.sample.id)
            cache.get_patterns(patterns.sample(3).map(&:id))
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "Redis fallback behavior" do
    context "when Redis becomes unavailable" do
      before do
        skip "Redis not available in test" unless defined?(Redis)

        allow_any_instance_of(Redis).to receive(:ping).and_return("PONG")
        @cache_with_redis = described_class.new
      end

      it "falls back to memory-only cache when Redis fails" do
        skip "Redis not available in test" unless defined?(Redis)

        # Simulate Redis failure
        allow_any_instance_of(Redis).to receive(:get).and_raise(StandardError, "Connection error")

        # Should still work with memory cache
        result = @cache_with_redis.get_pattern(pattern.id)
        expect(result).to eq(pattern)

        # Redis should be marked as unavailable
        expect(@cache_with_redis.instance_variable_get(:@redis_available)).to be false
      end
    end
  end

  describe "TTL configuration" do
    it "respects configured TTL values" do
      allow(Rails.application.config).to receive(:pattern_cache_memory_ttl).and_return(10.seconds)
      allow(Rails.application.config).to receive(:pattern_cache_redis_ttl).and_return(1.hour)

      expect(cache.send(:memory_ttl)).to eq(10.seconds)
      expect(cache.send(:redis_ttl)).to eq(1.hour)
    end

    it "uses default TTL values when not configured" do
      expect(cache.send(:memory_ttl)).to eq(Categorization::PatternCache::DEFAULT_MEMORY_TTL)
      expect(cache.send(:redis_ttl)).to eq(Categorization::PatternCache::DEFAULT_REDIS_TTL)
    end
  end
end
