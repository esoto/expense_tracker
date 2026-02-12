# frozen_string_literal: true

module Services::Infrastructure
  # CacheAdapter provides a consistent interface for cache operations
  # with support for key pattern matching in tests and production
  class CacheAdapter
    class << self
      # Get all keys matching a pattern
      # @param pattern [String] Pattern to match (supports wildcards with *)
      # @return [Array<String>] Array of matching keys
      def matching_keys(pattern)
        if Rails.env.test?
          test_matching_keys(pattern)
        else
          production_matching_keys(pattern)
        end
      end

      # Fetch multiple keys at once
      # @param keys [Array<String>] Array of keys to fetch
      # @return [Hash] Hash of key => value pairs
      def fetch_multi(*keys)
        return {} if keys.empty?

        Rails.cache.read_multi(*keys)
      end

      # Write a key with optional expiration
      # @param key [String] Cache key
      # @param value [Object] Value to cache
      # @param options [Hash] Options including :expires_in
      def write(key, value, options = {})
        Rails.cache.write(key, value, options)
      end

      # Read a key from cache
      # @param key [String] Cache key
      # @return [Object, nil] Cached value or nil
      def read(key)
        Rails.cache.read(key)
      end

      # Fetch with block for cache miss
      # @param key [String] Cache key
      # @param options [Hash] Options including :expires_in
      # @yield Block to execute on cache miss
      # @return [Object] Cached or computed value
      def fetch(key, options = {}, &block)
        Rails.cache.fetch(key, options, &block)
      end

      # Delete a key from cache
      # @param key [String] Cache key
      def delete(key)
        Rails.cache.delete(key)
      end

      # Clear all cache entries (use with caution)
      def clear
        Rails.cache.clear
      end

      private

      # Test environment key matching using MemoryStore
      def test_matching_keys(pattern)
        return [] unless Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)

        # Access the internal hash for MemoryStore
        cache_data = Rails.cache.instance_variable_get(:@data) || {}

        # Convert pattern to regex
        regex_pattern = pattern_to_regex(pattern)

        # Find matching keys that actually have values
        matching_keys = []
        cache_data.each do |key, entry|
          # Check if key matches pattern and entry is not expired
          if key.match?(regex_pattern)
            # MemoryStore entries are Entry objects with value and expiry
            if entry.is_a?(ActiveSupport::Cache::Entry) && !entry.expired?
              matching_keys << key
            elsif !entry.is_a?(ActiveSupport::Cache::Entry) && !entry.nil?
              # Handle raw values for simple cases
              matching_keys << key
            end
          end
        end
        matching_keys
      end

      # Production environment key matching
      def production_matching_keys(pattern)
        case Rails.cache
        when ActiveSupport::Cache::RedisCacheStore
          redis_matching_keys(pattern)
        when ActiveSupport::Cache::MemoryStore
          test_matching_keys(pattern) # Fallback for development
        else
          # For other cache stores, return empty array
          # This prevents errors in production while logging a warning
          Rails.logger.warn "CacheAdapter: Pattern matching not supported for #{Rails.cache.class}"
          []
        end
      end

      # Redis-specific key matching
      def redis_matching_keys(pattern)
        redis = Rails.cache.redis

        # Convert our pattern format to Redis SCAN pattern
        redis_pattern = pattern.gsub("*", "*")

        keys = []
        cursor = "0"

        # Use SCAN to avoid blocking on large keysets
        loop do
          cursor, batch = redis.scan(cursor, match: redis_pattern, count: 100)
          keys.concat(batch)
          break if cursor == "0"
        end

        keys
      rescue => e
        Rails.logger.error "CacheAdapter: Redis key matching failed: #{e.message}"
        []
      end

      # Convert a simple wildcard pattern to regex
      def pattern_to_regex(pattern)
        # Escape special regex characters except *
        escaped = Regexp.escape(pattern).gsub('\*', ".*")
        Regexp.new("^#{escaped}$")
      end
    end
  end
end
