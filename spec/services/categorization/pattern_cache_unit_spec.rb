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
end
