# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternCache, :unit do
  describe "#invalidate_all" do
    it "increments the pattern cache version instead of scanning Redis keys" do
      cache = described_class.new
      version_before = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i

      cache.invalidate_all

      version_after = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i
      expect(version_after).to be > version_before
    end

    it "clears the memory cache" do
      cache = described_class.new
      memory_cache = cache.instance_variable_get(:@memory_cache)
      memory_cache.write("cat:test_key", "test_value")

      cache.invalidate_all

      expect(memory_cache.read("cat:test_key")).to be_nil
    end

    it "does not use Redis SCAN+DEL" do
      cache = described_class.new

      # Ensure no Redis client methods are called
      expect(cache).not_to respond_to(:redis_client)
      cache.invalidate_all
    end
  end

  describe "#reset!" do
    it "increments the pattern cache version instead of scanning Redis keys" do
      cache = described_class.new
      version_before = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i

      cache.reset!

      version_after = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i
      expect(version_after).to be > version_before
    end

    it "clears the memory cache" do
      cache = described_class.new
      memory_cache = cache.instance_variable_get(:@memory_cache)
      memory_cache.write("cat:test_key", "test_value")

      cache.reset!

      expect(memory_cache.read("cat:test_key")).to be_nil
    end

    it "resets the metrics collector" do
      cache = described_class.new
      old_collector = cache.instance_variable_get(:@metrics_collector)

      cache.reset!

      new_collector = cache.instance_variable_get(:@metrics_collector)
      expect(new_collector).not_to equal(old_collector)
    end
  end

  describe "CACHE_NAMESPACE constant" do
    it "defines a cache namespace for key prefixing" do
      expect(described_class::CACHE_NAMESPACE).to eq("cat:")
    end

    it "all key prefixes use the cache namespace" do
      expect(described_class::PATTERN_KEY_PREFIX).to start_with(described_class::CACHE_NAMESPACE)
      expect(described_class::COMPOSITE_KEY_PREFIX).to start_with(described_class::CACHE_NAMESPACE)
      expect(described_class::USER_PREF_KEY_PREFIX).to start_with(described_class::CACHE_NAMESPACE)
    end
  end

  describe "#invalidate_category" do
    it "increments the pattern cache version instead of using delete_matched" do
      cache = described_class.new
      version_before = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i

      cache.invalidate_category(42)

      version_after = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i
      expect(version_after).to be > version_before
    end

    it "does not call delete_matched" do
      cache = described_class.new
      memory_cache = cache.instance_variable_get(:@memory_cache)

      expect(memory_cache).not_to receive(:delete_matched)
      cache.invalidate_category(99)
    end
  end

  describe "version key embedding in cache keys" do
    it "embeds the current pattern version in pattern_cache_key" do
      cache = described_class.new
      key1 = cache.send(:pattern_cache_key, 1)

      cache.invalidate_category(1)

      key2 = cache.send(:pattern_cache_key, 1)
      expect(key2).not_to eq(key1), "cache key should change after version increment"
    end

    it "embeds the current pattern version in type_cache_key" do
      cache = described_class.new
      key1 = cache.send(:type_cache_key, "merchant")

      cache.invalidate_category(1)

      key2 = cache.send(:type_cache_key, "merchant")
      expect(key2).not_to eq(key1), "type cache key should change after version increment"
    end

    it "embeds the current pattern version in all_active_cache_key" do
      cache = described_class.new
      key1 = cache.send(:all_active_cache_key)

      cache.invalidate_category(1)

      key2 = cache.send(:all_active_cache_key)
      expect(key2).not_to eq(key1), "all-active cache key should change after version increment"
    end
  end

  describe "#increment_pattern_cache_version (atomic increment)" do
    it "is safe to call concurrently from multiple threads (MemoryStore)" do
      cache = described_class.new
      Rails.cache.write(described_class::PATTERN_VERSION_KEY, 0)

      threads = 10.times.map do
        Thread.new { cache.send(:increment_pattern_cache_version) }
      end
      threads.each(&:join)

      final_version = Rails.cache.read(described_class::PATTERN_VERSION_KEY).to_i
      expect(final_version).to eq(10), "all 10 increments must be reflected (no lost updates)"
    end
  end

  describe "L2 cache via Rails.cache" do
    it "uses Rails.cache.fetch for L2 tier reads and writes" do
      cache = described_class.new

      expect(Rails.cache).to receive(:fetch).and_call_original
      # Trigger a cache miss to exercise L2
      cache.send(:fetch_with_tiered_cache, "test:key", memory_ttl: 1.minute, l2_ttl: 5.minutes) do
        "test_value"
      end
    end

    it "promotes L2 hits to memory cache (L1)" do
      cache = described_class.new
      test_key = "test:l2_promote"

      # Write directly to Rails.cache (L2) bypassing L1
      Rails.cache.write(test_key, "l2_value", expires_in: 1.hour)

      # Clear L1 so the value is only in L2
      cache.instance_variable_get(:@memory_cache).clear

      result = cache.send(:fetch_with_tiered_cache, test_key, memory_ttl: 1.minute, l2_ttl: 5.minutes) do
        "db_fallback_value"
      end

      expect(result).to eq("l2_value")
      # Verify it was promoted to L1
      expect(cache.instance_variable_get(:@memory_cache).read(test_key)).to eq("l2_value")
    end
  end

  describe "#metrics" do
    it "includes l2_cache_available instead of redis_available" do
      cache = described_class.new
      metrics = cache.metrics

      expect(metrics).to have_key(:l2_cache_available)
      expect(metrics).not_to have_key(:redis_available)
      expect(metrics[:l2_cache_available]).to be true
    end

    it "includes l2_ttl in configuration instead of redis_ttl" do
      cache = described_class.new
      metrics = cache.metrics

      expect(metrics[:configuration]).to have_key(:l2_ttl)
      expect(metrics[:configuration]).not_to have_key(:redis_ttl)
    end
  end

  describe "TTL constants" do
    it "has DEFAULT_MEMORY_TTL of 15 minutes" do
      expect(described_class::DEFAULT_MEMORY_TTL).to eq(15.minutes)
    end

    it "has DEFAULT_L2_TTL of 1 hour" do
      expect(described_class::DEFAULT_L2_TTL).to eq(1.hour)
    end

    it "does not define DEFAULT_REDIS_TTL" do
      expect(described_class.const_defined?(:DEFAULT_REDIS_TTL)).to be false
    end
  end

  describe "no Redis dependency" do
    it "does not have a redis_client method" do
      cache = described_class.new
      expect(cache.respond_to?(:redis_client, true)).to be false
    end

    it "does not have a redis_available? method" do
      cache = described_class.new
      expect(cache.respond_to?(:redis_available?, true)).to be false
    end

    it "does not have a @redis_available instance variable" do
      cache = described_class.new
      expect(cache.instance_variable_defined?(:@redis_available)).to be false
    end

    it "does not have fetch_from_redis method" do
      cache = described_class.new
      expect(cache.respond_to?(:fetch_from_redis, true)).to be false
    end

    it "does not have write_to_redis method" do
      cache = described_class.new
      expect(cache.respond_to?(:write_to_redis, true)).to be false
    end

    it "does not have delete_namespaced_keys method" do
      cache = described_class.new
      expect(cache.respond_to?(:delete_namespaced_keys, true)).to be false
    end
  end
end
