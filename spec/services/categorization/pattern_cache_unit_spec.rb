# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternCache, :unit do
  describe "#invalidate_all" do
    let(:mock_redis) { instance_double(Redis) }

    before do
      allow(mock_redis).to receive(:ping).and_return("PONG")
      allow(Redis).to receive(:new).and_return(mock_redis)
    end

    it "uses namespaced SCAN+DEL instead of flushdb" do
      cache = described_class.new
      cache.instance_variable_set(:@redis_available, true)

      expect(mock_redis).not_to receive(:flushdb)
      expect(mock_redis).to receive(:scan)
        .with("0", match: "cat:*", count: 100)
        .and_return([ "0", [ "cat:pattern:1:v1", "cat:composite:2:v1" ] ])
      expect(mock_redis).to receive(:del).with("cat:pattern:1:v1", "cat:composite:2:v1")

      cache.invalidate_all
    end

    it "deletes all namespaced keys and preserves non-namespaced keys" do
      cache = described_class.new
      cache.instance_variable_set(:@redis_available, true)

      allow(mock_redis).to receive(:scan)
        .with("0", match: "cat:*", count: 100)
        .and_return([ "0", [ "cat:pattern:5:v1", "cat:user_pref:starbucks:v1" ] ])
      allow(mock_redis).to receive(:del).with("cat:pattern:5:v1", "cat:user_pref:starbucks:v1")

      cache.invalidate_all

      expect(mock_redis).to have_received(:del).with("cat:pattern:5:v1", "cat:user_pref:starbucks:v1")
    end

    it "handles multiple SCAN iterations for large key sets" do
      cache = described_class.new
      cache.instance_variable_set(:@redis_available, true)

      allow(mock_redis).to receive(:scan)
        .with("0", match: "cat:*", count: 100)
        .and_return([ "42", [ "cat:pattern:1:v1", "cat:pattern:2:v1" ] ])

      allow(mock_redis).to receive(:scan)
        .with("42", match: "cat:*", count: 100)
        .and_return([ "0", [ "cat:pattern:3:v1" ] ])

      allow(mock_redis).to receive(:del)

      cache.invalidate_all

      expect(mock_redis).to have_received(:del).with("cat:pattern:1:v1", "cat:pattern:2:v1")
      expect(mock_redis).to have_received(:del).with("cat:pattern:3:v1")
    end

    it "handles empty SCAN result gracefully" do
      cache = described_class.new
      cache.instance_variable_set(:@redis_available, true)

      allow(mock_redis).to receive(:scan)
        .with("0", match: "cat:*", count: 100)
        .and_return([ "0", [] ])
      allow(mock_redis).to receive(:del)

      cache.invalidate_all

      expect(mock_redis).not_to have_received(:del)
    end
  end

  describe "#reset!" do
    let(:mock_redis) { instance_double(Redis) }

    before do
      allow(mock_redis).to receive(:ping).and_return("PONG")
      allow(Redis).to receive(:new).and_return(mock_redis)
    end

    it "uses namespaced SCAN+DEL instead of flushdb" do
      cache = described_class.new
      cache.instance_variable_set(:@redis_available, true)

      expect(mock_redis).not_to receive(:flushdb)

      allow(mock_redis).to receive(:scan)
        .with("0", match: "cat:*", count: 100)
        .and_return([ "0", [ "cat:pattern:1:v1" ] ])
      allow(mock_redis).to receive(:del).with("cat:pattern:1:v1")

      cache.reset!

      expect(mock_redis).to have_received(:scan).with("0", match: "cat:*", count: 100)
      expect(mock_redis).to have_received(:del).with("cat:pattern:1:v1")
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
end
