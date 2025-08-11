# frozen_string_literal: true

require "concurrent"

module Categorization
  # Thread-safe LRU (Least Recently Used) cache with TTL support
  # Provides bounded memory usage and automatic eviction of stale entries
  class LruCache
    attr_reader :max_size, :ttl_seconds

    def initialize(max_size: 1000, ttl_seconds: 300)
      @max_size = max_size
      @ttl_seconds = ttl_seconds

      # Thread-safe data structures
      @store = Concurrent::Map.new
      @access_times = Concurrent::Map.new
      @expiry_times = Concurrent::Map.new
      @mutex = Mutex.new

      # Statistics
      @hits = Concurrent::AtomicFixnum.new(0)
      @misses = Concurrent::AtomicFixnum.new(0)

      # Start background cleanup thread if TTL is enabled
      start_cleanup_thread if ttl_seconds > 0
    end

    # Fetch value from cache or compute it using block
    def fetch(key, ttl: nil, &block)
      # Check for existing value
      if (value = get(key))
        @hits.increment
        return value
      end

      @misses.increment

      # Compute value if block given
      return nil unless block_given?

      value = yield
      set(key, value, ttl: ttl) if value
      value
    end

    # Get value from cache
    def get(key)
      # Check if key exists and not expired
      return nil unless @store.key?(key)

      if expired?(key)
        delete(key)
        return nil
      end

      # Update access time
      @access_times[key] = Time.current.to_f
      @store[key]
    end

    # Set value in cache with optional TTL
    def set(key, value, ttl: nil)
      @mutex.synchronize do
        # Evict if at capacity
        evict_lru if @store.size >= @max_size && !@store.key?(key)

        # Store value
        @store[key] = value
        @access_times[key] = Time.current.to_f

        # Set expiry time
        effective_ttl = ttl || @ttl_seconds
        if effective_ttl > 0
          @expiry_times[key] = Time.current.to_f + effective_ttl
        end
      end

      value
    end

    # Delete key from cache
    def delete(key)
      @mutex.synchronize do
        @store.delete(key)
        @access_times.delete(key)
        @expiry_times.delete(key)
      end
    end

    # Clear all cache entries
    def clear
      @mutex.synchronize do
        @store.clear
        @access_times.clear
        @expiry_times.clear
        @hits.value = 0
        @misses.value = 0
      end
    end

    # Get all keys in cache
    def keys
      @store.keys
    end

    # Get cache size
    def size
      @store.size
    end

    # Check if key exists and not expired
    def key?(key)
      @store.key?(key) && !expired?(key)
    end

    # Get cache statistics
    def stats
      total = @hits.value + @misses.value
      hit_rate = total > 0 ? (@hits.value.to_f / total * 100).round(2) : 0.0

      {
        size: @store.size,
        max_size: @max_size,
        hits: @hits.value,
        misses: @misses.value,
        hit_rate: hit_rate,
        ttl_seconds: @ttl_seconds
      }
    end

    # Read value directly (for debugging)
    def read(key)
      @store[key]
    end

    private

    # Check if key has expired
    def expired?(key)
      return false unless @expiry_times.key?(key)

      Time.current.to_f > @expiry_times[key]
    end

    # Evict least recently used entry
    def evict_lru
      return if @access_times.empty?

      # Find LRU key
      lru_key = nil
      oldest_time = Float::INFINITY

      @access_times.each do |key, time|
        if time < oldest_time
          oldest_time = time
          lru_key = key
        end
      end

      # Remove LRU entry
      if lru_key
        @store.delete(lru_key)
        @access_times.delete(lru_key)
        @expiry_times.delete(lru_key)
      end
    end

    # Start background thread for TTL cleanup
    def start_cleanup_thread
      Thread.new do
        loop do
          sleep([ ttl_seconds / 10.0, 60 ].min)
          cleanup_expired
        end
      end
    end

    # Remove expired entries
    def cleanup_expired
      return if @expiry_times.empty?

      current_time = Time.current.to_f
      expired_keys = []

      @expiry_times.each do |key, expiry|
        expired_keys << key if current_time > expiry
      end

      expired_keys.each { |key| delete(key) }
    rescue => e
      # Silently handle cleanup errors to avoid thread death
      Rails.logger.error "[LruCache] Cleanup error: #{e.message}" if defined?(Rails)
    end
  end
end
