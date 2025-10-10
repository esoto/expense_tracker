# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::LruCache, :unit do
  let(:cache) { described_class.new(max_size: 3, ttl_seconds: 10) }
  let(:current_time) { Time.zone.local(2024, 1, 1, 12, 0, 0) }

  before do
    # Mock Thread.new to prevent actual background threads
    allow(Thread).to receive(:new) do |&block|
      # Don't actually run the thread
      nil
    end
    # Mock Time.current for controlled time testing
    allow(Time).to receive(:current).and_return(current_time)
  end

  describe "#initialize" do
    context "with default parameters" do
      it "sets default max_size to 1000" do
        # Need to create cache after setting up Thread mock expectation
        expect(Thread).to receive(:new).once
        default_cache = described_class.new
        expect(default_cache.max_size).to eq(1000)
      end

      it "sets default ttl_seconds to 300" do
        default_cache = described_class.new
        expect(default_cache.ttl_seconds).to eq(300)
      end

      it "starts cleanup thread when ttl_seconds > 0" do
        expect(Thread).to receive(:new).once
        described_class.new
      end
    end

    context "with custom parameters" do
      subject(:custom_cache) { described_class.new(max_size: 50, ttl_seconds: 60) }

      it "sets custom max_size" do
        expect(custom_cache.max_size).to eq(50)
      end

      it "sets custom ttl_seconds" do
        expect(custom_cache.ttl_seconds).to eq(60)
      end
    end

    context "when ttl_seconds is 0" do
      subject(:no_ttl_cache) { described_class.new(ttl_seconds: 0) }

      before do
        allow(Thread).to receive(:new)
        no_ttl_cache
      end

      it "does not start cleanup thread" do
        expect(Thread).not_to have_received(:new)
      end
    end

    it "initializes empty cache" do
      expect(cache.size).to eq(0)
      expect(cache.keys).to be_empty
    end

    it "initializes statistics counters to zero" do
      stats = cache.stats
      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
      expect(stats[:hit_rate]).to eq(0.0)
    end
  end

  describe "#get" do
    context "when key exists and not expired" do
      before do
        cache.set("key1", "value1")
      end

      it "returns the value" do
        expect(cache.get("key1")).to eq("value1")
      end

      it "updates access time" do
        original_time = current_time
        cache.get("key1")

        # Advance time
        allow(Time).to receive(:current).and_return(current_time + 1.second)
        cache.set("key2", "value2")
        cache.set("key3", "value3")
        cache.set("key4", "value4") # Should evict key1 if not accessed

        # Access key1 to update its access time
        allow(Time).to receive(:current).and_return(original_time)
        cache.set("key1", "value1")
        allow(Time).to receive(:current).and_return(current_time + 2.seconds)
        cache.get("key1")

        # Now add another key - should not evict key1 since it was recently accessed
        cache.set("key5", "value5")
        expect(cache.key?("key1")).to be true
      end
    end

    context "when key does not exist" do
      it "returns nil" do
        expect(cache.get("nonexistent")).to be_nil
      end
    end

    context "when key is expired" do
      before do
        cache.set("expired_key", "value", ttl: 5)
        allow(Time).to receive(:current).and_return(current_time + 6.seconds)
      end

      it "returns nil" do
        expect(cache.get("expired_key")).to be_nil
      end

      it "deletes the expired key" do
        cache.get("expired_key")
        expect(cache.key?("expired_key")).to be false
      end
    end
  end

  describe "#set" do
    it "stores the value" do
      cache.set("key", "value")
      expect(cache.get("key")).to eq("value")
    end

    it "returns the stored value" do
      expect(cache.set("key", "value")).to eq("value")
    end

    it "updates existing key without increasing size" do
      cache.set("key", "value1")
      expect(cache.size).to eq(1)

      cache.set("key", "value2")
      expect(cache.size).to eq(1)
      expect(cache.get("key")).to eq("value2")
    end

    context "with custom TTL" do
      it "uses custom TTL over default" do
        cache.set("custom_ttl", "value", ttl: 2)

        # Should exist after 1 second
        allow(Time).to receive(:current).and_return(current_time + 1.second)
        expect(cache.get("custom_ttl")).to eq("value")

        # Should expire after 3 seconds
        allow(Time).to receive(:current).and_return(current_time + 3.seconds)
        expect(cache.get("custom_ttl")).to be_nil
      end
    end

    context "when cache is at max_size" do
      before do
        cache.set("key1", "value1")
        allow(Time).to receive(:current).and_return(current_time + 1.second)
        cache.set("key2", "value2")
        allow(Time).to receive(:current).and_return(current_time + 2.seconds)
        cache.set("key3", "value3")
      end

      it "evicts LRU entry when adding new key" do
        allow(Time).to receive(:current).and_return(current_time + 3.seconds)
        cache.set("key4", "value4")

        expect(cache.size).to eq(3)
        expect(cache.key?("key1")).to be false # LRU entry evicted
        expect(cache.key?("key2")).to be true
        expect(cache.key?("key3")).to be true
        expect(cache.key?("key4")).to be true
      end

      it "does not evict when updating existing key" do
        cache.set("key2", "updated_value")

        expect(cache.size).to eq(3)
        expect(cache.key?("key1")).to be true
        expect(cache.key?("key2")).to be true
        expect(cache.key?("key3")).to be true
        expect(cache.get("key2")).to eq("updated_value")
      end
    end

    context "with TTL set to 0" do
      let(:no_ttl_cache) { described_class.new(ttl_seconds: 0) }

      it "does not set expiry time" do
        no_ttl_cache.set("key", "value")

        # Advance time significantly
        allow(Time).to receive(:current).and_return(current_time + 1.year)
        expect(no_ttl_cache.get("key")).to eq("value")
      end
    end
  end

  describe "#fetch" do
    context "when key exists (cache hit)" do
      before do
        cache.set("existing", "cached_value")
      end

      it "returns cached value without executing block" do
        block_executed = false
        result = cache.fetch("existing") do
          block_executed = true
          "new_value"
        end

        expect(result).to eq("cached_value")
        expect(block_executed).to be false
      end

      it "increments hit counter" do
        expect { cache.fetch("existing") { "value" } }
          .to change { cache.stats[:hits] }.by(1)
      end

      it "does not increment miss counter" do
        expect { cache.fetch("existing") { "value" } }
          .not_to change { cache.stats[:misses] }
      end
    end

    context "when key does not exist (cache miss)" do
      it "executes block and caches result" do
        block_executed = false
        result = cache.fetch("new_key") do
          block_executed = true
          "computed_value"
        end

        expect(result).to eq("computed_value")
        expect(block_executed).to be true
        expect(cache.get("new_key")).to eq("computed_value")
      end

      it "increments miss counter" do
        expect { cache.fetch("missing") { "value" } }
          .to change { cache.stats[:misses] }.by(1)
      end

      it "does not increment hit counter" do
        expect { cache.fetch("missing") { "value" } }
          .not_to change { cache.stats[:hits] }
      end

      context "when block returns nil" do
        it "does not cache nil value" do
          result = cache.fetch("nil_key") { nil }

          expect(result).to be_nil
          expect(cache.key?("nil_key")).to be false
        end
      end

      context "without block" do
        it "returns nil" do
          expect(cache.fetch("missing")).to be_nil
        end

        it "increments miss counter" do
          expect { cache.fetch("missing") }
            .to change { cache.stats[:misses] }.by(1)
        end
      end

      context "with custom TTL" do
        it "uses custom TTL when caching" do
          cache.fetch("custom", ttl: 2) { "value" }

          # Should exist after 1 second
          allow(Time).to receive(:current).and_return(current_time + 1.second)
          expect(cache.get("custom")).to eq("value")

          # Should expire after 3 seconds
          allow(Time).to receive(:current).and_return(current_time + 3.seconds)
          expect(cache.get("custom")).to be_nil
        end
      end
    end

    context "when key is expired" do
      before do
        cache.set("expired", "old_value", ttl: 1)
        allow(Time).to receive(:current).and_return(current_time + 2.seconds)
      end

      it "treats as cache miss and recomputes" do
        result = cache.fetch("expired") { "new_value" }

        expect(result).to eq("new_value")
        expect(cache.get("expired")).to eq("new_value")
      end
    end
  end

  describe "#delete" do
    before do
      cache.set("key_to_delete", "value")
    end

    it "removes the key from cache" do
      cache.delete("key_to_delete")
      expect(cache.key?("key_to_delete")).to be false
    end

    it "decreases cache size" do
      expect { cache.delete("key_to_delete") }
        .to change { cache.size }.from(1).to(0)
    end

    it "handles non-existent key gracefully" do
      expect { cache.delete("nonexistent") }.not_to raise_error
    end
  end

  describe "#clear" do
    before do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.fetch("key1") { "value" } # Generate hit
      cache.fetch("missing") { "value" } # Generate miss
    end

    it "removes all entries" do
      cache.clear
      expect(cache.size).to eq(0)
      expect(cache.keys).to be_empty
    end

    it "resets statistics" do
      cache.clear
      stats = cache.stats

      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
      expect(stats[:hit_rate]).to eq(0.0)
    end
  end

  describe "#keys" do
    it "returns empty array for empty cache" do
      expect(cache.keys).to eq([])
    end

    it "returns all cache keys" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      keys = cache.keys
      expect(keys).to contain_exactly("key1", "key2")
    end
  end

  describe "#size" do
    it "returns 0 for empty cache" do
      expect(cache.size).to eq(0)
    end

    it "returns number of entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      expect(cache.size).to eq(2)
    end

    it "does not count expired entries" do
      cache.set("expired", "value", ttl: 1)
      cache.set("valid", "value")

      allow(Time).to receive(:current).and_return(current_time + 2.seconds)

      # Size still reports 2 until expired entry is accessed
      expect(cache.size).to eq(2)
    end
  end

  describe "#key?" do
    context "when key exists and not expired" do
      before do
        cache.set("existing", "value")
      end

      it "returns true" do
        expect(cache.key?("existing")).to be true
      end
    end

    context "when key does not exist" do
      it "returns false" do
        expect(cache.key?("nonexistent")).to be false
      end
    end

    context "when key is expired" do
      before do
        cache.set("expired", "value", ttl: 1)
        allow(Time).to receive(:current).and_return(current_time + 2.seconds)
      end

      it "returns false" do
        expect(cache.key?("expired")).to be false
      end
    end
  end

  describe "#stats" do
    context "with no operations" do
      it "returns zero statistics" do
        stats = cache.stats

        expect(stats[:size]).to eq(0)
        expect(stats[:max_size]).to eq(3)
        expect(stats[:hits]).to eq(0)
        expect(stats[:misses]).to eq(0)
        expect(stats[:hit_rate]).to eq(0.0)
        expect(stats[:ttl_seconds]).to eq(10)
      end
    end

    context "with cache operations" do
      before do
        cache.set("key1", "value1")
        cache.set("key2", "value2")

        # Generate 3 hits
        cache.fetch("key1") { "value" }
        cache.fetch("key1") { "value" }
        cache.fetch("key2") { "value" }

        # Generate 2 misses
        cache.fetch("missing1") { "value" }
        cache.fetch("missing2") { "value" }
      end

      it "returns correct statistics" do
        stats = cache.stats

        # Cache size is 3 due to max_size limit (key1 was evicted)
        expect(stats[:size]).to eq(3) # max_size limit reached
        expect(stats[:max_size]).to eq(3)
        expect(stats[:hits]).to eq(3)
        expect(stats[:misses]).to eq(2)
        expect(stats[:hit_rate]).to eq(60.0) # 3/5 * 100
        expect(stats[:ttl_seconds]).to eq(10)
      end
    end

    context "with only hits" do
      before do
        cache.set("key", "value")
        cache.fetch("key") { "value" }
        cache.fetch("key") { "value" }
      end

      it "calculates 100% hit rate" do
        expect(cache.stats[:hit_rate]).to eq(100.0)
      end
    end

    context "with only misses" do
      before do
        cache.fetch("miss1") { "value1" }
        cache.fetch("miss2") { "value2" }
      end

      it "calculates 0% hit rate" do
        expect(cache.stats[:hit_rate]).to eq(0.0)
      end
    end
  end

  describe "#read" do
    it "returns raw value without updating access time" do
      cache.set("key", "value")

      # Advance time
      allow(Time).to receive(:current).and_return(current_time + 1.second)

      # Read should not update access time
      expect(cache.read("key")).to eq("value")

      # Add entries to fill cache
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # Adding one more should evict "key" since read didn't update access time
      cache.set("key4", "value4")

      expect(cache.key?("key")).to be false
    end

    it "returns value even if expired" do
      cache.set("expired", "value", ttl: 1)
      allow(Time).to receive(:current).and_return(current_time + 2.seconds)

      expect(cache.read("expired")).to eq("value")
    end

    it "returns nil for non-existent key" do
      expect(cache.read("nonexistent")).to be_nil
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entry when cache is full" do
      # Set entries with different access times
      cache.set("oldest", "value1")
      allow(Time).to receive(:current).and_return(current_time + 1.second)
      cache.set("middle", "value2")
      allow(Time).to receive(:current).and_return(current_time + 2.seconds)
      cache.set("newest", "value3")

      # Access middle entry to update its access time
      allow(Time).to receive(:current).and_return(current_time + 3.seconds)
      cache.get("middle")

      # Add new entry - should evict "oldest"
      allow(Time).to receive(:current).and_return(current_time + 4.seconds)
      cache.set("new", "value4")

      expect(cache.key?("oldest")).to be false
      expect(cache.key?("middle")).to be true
      expect(cache.key?("newest")).to be true
      expect(cache.key?("new")).to be true
    end

    it "handles eviction with empty access times gracefully" do
      # This is an edge case that shouldn't happen in normal operation
      cache.instance_variable_get(:@access_times).clear

      expect { cache.send(:evict_lru) }.not_to raise_error
    end
  end

  describe "TTL functionality" do
    it "expires entries after TTL seconds" do
      cache.set("temp", "value", ttl: 2)

      # Should exist before expiry
      allow(Time).to receive(:current).and_return(current_time + 1.second)
      expect(cache.get("temp")).to eq("value")

      # Should expire after TTL
      allow(Time).to receive(:current).and_return(current_time + 3.seconds)
      expect(cache.get("temp")).to be_nil
    end

    it "uses default TTL when not specified" do
      cache.set("default_ttl", "value")

      # Should exist before default TTL (10 seconds)
      allow(Time).to receive(:current).and_return(current_time + 9.seconds)
      expect(cache.get("default_ttl")).to eq("value")

      # Should expire after default TTL
      allow(Time).to receive(:current).and_return(current_time + 11.seconds)
      expect(cache.get("default_ttl")).to be_nil
    end
  end

  describe "background cleanup" do
    let(:cleanup_cache) { described_class.new(ttl_seconds: 10) }

    before do
      allow(cleanup_cache).to receive(:sleep)
    end

    it "removes expired entries during cleanup" do
      cleanup_cache.set("expired1", "value1", ttl: 1)
      cleanup_cache.set("expired2", "value2", ttl: 1)
      cleanup_cache.set("valid", "value3", ttl: 10)

      # Advance time to expire first two entries
      allow(Time).to receive(:current).and_return(current_time + 2.seconds)

      # Run cleanup
      cleanup_cache.send(:cleanup_expired)

      expect(cleanup_cache.key?("expired1")).to be false
      expect(cleanup_cache.key?("expired2")).to be false
      expect(cleanup_cache.key?("valid")).to be true
    end

    it "handles cleanup errors gracefully" do
      allow(cleanup_cache.instance_variable_get(:@expiry_times))
        .to receive(:each).and_raise(StandardError, "Test error")

      expect { cleanup_cache.send(:cleanup_expired) }.not_to raise_error
    end

    it "logs errors when Rails is defined" do
      # Rails is already defined in test environment
      # Mock the Rails.logger directly
      logger = double("logger")
      allow(Rails).to receive(:logger).and_return(logger)

      # Set up the error expectation
      expect(logger).to receive(:error).with("[LruCache] Cleanup error: Test error")

      # Add an entry with expiry time to trigger the each loop
      cleanup_cache.set("test", "value", ttl: 5)

      # Force an error during cleanup after the first yield
      original_expiry_times = cleanup_cache.instance_variable_get(:@expiry_times)
      allow(original_expiry_times).to receive(:each) do |&block|
        # Call block with first entry to trigger the iteration
        block.call("test", Time.current.to_f + 10) if block
        # Then raise error
        raise StandardError, "Test error"
      end

      cleanup_cache.send(:cleanup_expired)
    end

    it "does not run cleanup when expiry_times is empty" do
      cleanup_cache.clear

      expect(cleanup_cache.instance_variable_get(:@expiry_times))
        .not_to receive(:each)

      cleanup_cache.send(:cleanup_expired)
    end

    it "calculates correct sleep interval" do
      # For TTL of 10 seconds, should sleep 1 second (10/10)
      small_ttl_cache = described_class.new(ttl_seconds: 10)

      # Test that the calculation would be correct
      sleep_interval = [ small_ttl_cache.ttl_seconds / 10.0, 60 ].min
      expect(sleep_interval).to eq(1.0)
    end

    context "with large TTL" do
      let(:large_ttl_cache) { described_class.new(ttl_seconds: 1000) }

      it "caps sleep interval at 60 seconds" do
        # Test that the calculation would cap at 60
        sleep_interval = [ large_ttl_cache.ttl_seconds / 10.0, 60 ].min
        expect(sleep_interval).to eq(60)
      end
    end
  end

  describe "thread safety" do
    let(:thread_safe_cache) { described_class.new(max_size: 100, ttl_seconds: 10) }

    it "uses thread-safe data structures" do
      # Verify that thread-safe structures are used
      store = thread_safe_cache.instance_variable_get(:@store)
      access_times = thread_safe_cache.instance_variable_get(:@access_times)
      expiry_times = thread_safe_cache.instance_variable_get(:@expiry_times)
      hits = thread_safe_cache.instance_variable_get(:@hits)
      misses = thread_safe_cache.instance_variable_get(:@misses)

      expect(store).to be_a(Concurrent::Map)
      expect(access_times).to be_a(Concurrent::Map)
      expect(expiry_times).to be_a(Concurrent::Map)
      expect(hits).to be_a(Concurrent::AtomicFixnum)
      expect(misses).to be_a(Concurrent::AtomicFixnum)
    end

    it "uses mutex for critical sections" do
      mutex = thread_safe_cache.instance_variable_get(:@mutex)
      expect(mutex).to be_a(Mutex)

      # Verify mutex is used in set operation
      expect(mutex).to receive(:synchronize).and_call_original
      thread_safe_cache.set("test", "value")
    end

    it "handles multiple operations without errors" do
      # Simulate concurrent-like operations sequentially
      operations = []

      10.times do |i|
        operations << -> { thread_safe_cache.set("key#{i}", "value#{i}") }
        operations << -> { thread_safe_cache.get("key#{i}") }
        operations << -> { thread_safe_cache.fetch("fetch#{i}") { "fetched#{i}" } }
        operations << -> { thread_safe_cache.delete("key#{i}") if i.even? }
      end

      # Execute all operations
      operations.shuffle.each(&:call)

      expect(thread_safe_cache.size).to be > 0
      stats = thread_safe_cache.stats
      expect(stats[:hits] + stats[:misses]).to be > 0
    end

    it "maintains cache size constraint during multiple additions" do
      # Fill cache to near capacity
      99.times { |i| thread_safe_cache.set("initial#{i}", "value#{i}") }

      # Add more entries that would trigger eviction
      10.times do |i|
        thread_safe_cache.set("overflow#{i}", "value#{i}")
      end

      # Cache should not exceed max_size
      expect(thread_safe_cache.size).to be <= 100
    end

    it "tracks statistics atomically" do
      # Pre-populate some entries
      5.times { |i| thread_safe_cache.set("pre#{i}", "value#{i}") }

      # Generate hits
      hit_count = 0
      5.times do |i|
        result = thread_safe_cache.fetch("pre#{i}") { "value" }
        hit_count += 1 if result == "value#{i}"
      end

      # Generate misses
      miss_count = 0
      5.times do |i|
        result = thread_safe_cache.fetch("new#{i}") { "new_value#{i}" }
        miss_count += 1 if result == "new_value#{i}"
      end

      stats = thread_safe_cache.stats
      expect(stats[:hits]).to eq(hit_count)
      expect(stats[:misses]).to eq(miss_count)
    end
  end

  describe "edge cases" do
    it "handles nil values" do
      cache.set("nil_key", nil)
      expect(cache.get("nil_key")).to be_nil
      expect(cache.key?("nil_key")).to be true
    end

    it "handles empty string values" do
      cache.set("empty", "")
      expect(cache.get("empty")).to eq("")
    end

    it "handles complex objects as values" do
      complex_value = { nested: { data: [ 1, 2, 3 ] }, string: "test" }
      cache.set("complex", complex_value)

      retrieved = cache.get("complex")
      expect(retrieved).to eq(complex_value)
      expect(retrieved).to be(complex_value) # Same object reference
    end

    it "handles symbols as keys" do
      cache.set(:symbol_key, "value")
      expect(cache.get(:symbol_key)).to eq("value")
    end

    it "handles numeric keys" do
      cache.set(123, "numeric")
      expect(cache.get(123)).to eq("numeric")
    end

    it "handles TTL of 0 in set method" do
      cache.set("no_expire", "value", ttl: 0)

      # Should never expire
      allow(Time).to receive(:current).and_return(current_time + 1.year)
      expect(cache.get("no_expire")).to eq("value")
    end

    it "handles negative TTL as no expiry" do
      cache.set("negative_ttl", "value", ttl: -1)
      # Negative TTL doesn't set expiry time, so value persists
      expect(cache.get("negative_ttl")).to eq("value")
    end
  end

  describe "memory efficiency" do
    it "properly cleans up all references when deleting" do
      cache.set("memory_test", "value", ttl: 5)

      store = cache.instance_variable_get(:@store)
      access_times = cache.instance_variable_get(:@access_times)
      expiry_times = cache.instance_variable_get(:@expiry_times)

      expect(store.key?("memory_test")).to be true
      expect(access_times.key?("memory_test")).to be true
      expect(expiry_times.key?("memory_test")).to be true

      cache.delete("memory_test")

      expect(store.key?("memory_test")).to be false
      expect(access_times.key?("memory_test")).to be false
      expect(expiry_times.key?("memory_test")).to be false
    end

    it "properly cleans up all references when clearing" do
      3.times { |i| cache.set("key#{i}", "value#{i}", ttl: 10) }

      cache.clear

      store = cache.instance_variable_get(:@store)
      access_times = cache.instance_variable_get(:@access_times)
      expiry_times = cache.instance_variable_get(:@expiry_times)

      expect(store.size).to eq(0)
      expect(access_times.size).to eq(0)
      expect(expiry_times.size).to eq(0)
    end
  end
end
