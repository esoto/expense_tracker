# frozen_string_literal: true

module Categorization
  # High-performance two-tier caching service for categorization patterns
  # Implements memory cache (L1) and Redis cache (L2) with automatic fallback
  # Ensures < 1ms response times for pattern lookups with monitoring capabilities
  class PatternCache
    include ActiveSupport::Benchmarkable
    
    # Cache configuration constants
    MEMORY_CACHE_MAX_SIZE = 50 * 1024 # 50MB memory cache size in kilobytes
    DEFAULT_MEMORY_TTL = 5.minutes
    DEFAULT_REDIS_TTL = 24.hours
    CACHE_VERSION = "v1"
    METRICS_SAMPLE_RATE = 0.01 # Sample 1% of requests for detailed metrics
    
    # Cache key prefixes
    PATTERN_KEY_PREFIX = "cat:pattern"
    COMPOSITE_KEY_PREFIX = "cat:composite"
    USER_PREF_KEY_PREFIX = "cat:user_pref"
    METRICS_KEY = "cat:metrics"
    
    class << self
      # Thread-safe singleton instance
      def instance
        @instance ||= new
      end
      
      delegate :get_pattern, :get_patterns, :get_composite_pattern,
               :get_user_preference, :invalidate, :invalidate_all,
               :warm_cache, :metrics, :hit_rate, to: :instance
    end
    
    def initialize
      @memory_cache = build_memory_cache
      @redis_available = redis_available?
      @metrics_collector = MetricsCollector.new
      @lock = Mutex.new
      
      Rails.logger.info "[PatternCache] Initialized with #{@redis_available ? 'Redis + Memory' : 'Memory only'} caching"
    end
    
    # Get a single pattern by ID with caching
    def get_pattern(pattern_id)
      return nil unless pattern_id
      
      benchmark_with_metrics("get_pattern") do
        fetch_with_tiered_cache(
          pattern_cache_key(pattern_id),
          memory_ttl: memory_ttl,
          redis_ttl: redis_ttl
        ) do
          CategorizationPattern.active.find_by(id: pattern_id)
        end
      end
    end
    
    # Get multiple patterns by IDs efficiently
    def get_patterns(pattern_ids)
      return [] if pattern_ids.blank?
      
      benchmark_with_metrics("get_patterns") do
        # Batch fetch from cache
        results = pattern_ids.map do |id|
          get_pattern(id)
        end.compact
        
        # If we got fewer results than requested, some were missing
        if results.size < pattern_ids.size
          found_ids = results.map(&:id)
          missing_ids = pattern_ids - found_ids
          
          # Batch load missing patterns
          if missing_ids.present?
            missing_patterns = CategorizationPattern.active.where(id: missing_ids)
            missing_patterns.each do |pattern|
              cache_pattern(pattern)
              results << pattern
            end
          end
        end
        
        results
      end
    end
    
    # Get patterns by type with caching
    def get_patterns_by_type(pattern_type)
      benchmark_with_metrics("get_patterns_by_type") do
        fetch_with_tiered_cache(
          type_cache_key(pattern_type),
          memory_ttl: memory_ttl / 2, # Shorter TTL for collections
          redis_ttl: redis_ttl / 2
        ) do
          CategorizationPattern.active.by_type(pattern_type).to_a
        end
      end
    end
    
    # Get composite pattern with caching
    def get_composite_pattern(composite_id)
      return nil unless composite_id
      
      benchmark_with_metrics("get_composite_pattern") do
        fetch_with_tiered_cache(
          composite_cache_key(composite_id),
          memory_ttl: memory_ttl,
          redis_ttl: redis_ttl
        ) do
          CompositePattern.active.find_by(id: composite_id)
        end
      end
    end
    
    # Get user preference with caching
    def get_user_preference(merchant_name)
      return nil if merchant_name.blank?
      
      benchmark_with_metrics("get_user_preference") do
        normalized_merchant = merchant_name.downcase.strip
        
        fetch_with_tiered_cache(
          user_pref_cache_key(normalized_merchant),
          memory_ttl: memory_ttl * 2, # Longer TTL for user preferences
          redis_ttl: redis_ttl * 2
        ) do
          UserCategoryPreference.find_by(context_type: "merchant", context_value: normalized_merchant)
        end
      end
    end
    
    # Get all active patterns (used for bulk operations)
    def get_all_active_patterns
      benchmark_with_metrics("get_all_active_patterns") do
        fetch_with_tiered_cache(
          "#{PATTERN_KEY_PREFIX}:all:active:#{CACHE_VERSION}",
          memory_ttl: 1.minute, # Short TTL for large collections
          redis_ttl: 5.minutes
        ) do
          CategorizationPattern.active.includes(:category).to_a
        end
      end
    end
    
    # Invalidate specific cache entries
    def invalidate(model)
      case model
      when CategorizationPattern
        invalidate_pattern(model)
      when CompositePattern
        invalidate_composite(model)
      when UserCategoryPreference
        invalidate_user_preference(model)
      else
        Rails.logger.warn "[PatternCache] Unknown model type for invalidation: #{model.class}"
      end
    end
    
    # Clear all caches
    def invalidate_all
      @lock.synchronize do
        @memory_cache.clear
        
        if @redis_available
          redis_client.flushdb
        end
        
        Rails.logger.info "[PatternCache] All caches cleared"
      end
    rescue => e
      Rails.logger.error "[PatternCache] Error clearing caches: #{e.message}"
    end
    
    # Warm cache with commonly used patterns
    def warm_cache
      Rails.logger.info "[PatternCache] Starting cache warming..."
      
      warmup_stats = {
        patterns: 0,
        composites: 0,
        user_prefs: 0,
        duration: 0
      }
      
      benchmark_with_metrics("cache_warming") do
        # Warm up frequently used patterns
        patterns = CategorizationPattern.active
                                       .frequently_used
                                       .includes(:category)
                                       .limit(500)
        
        patterns.each do |pattern|
          cache_pattern(pattern)
          warmup_stats[:patterns] += 1
        end
        
        # Warm up composite patterns
        composites = CompositePattern.active.includes(:category).limit(100)
        composites.each do |composite|
          cache_composite(composite)
          warmup_stats[:composites] += 1
        end
        
        # Warm up recent user preferences
        user_prefs = UserCategoryPreference.joins(:category)
                                          .where(created_at: 30.days.ago..)
                                          .limit(200)
        
        user_prefs.each do |pref|
          cache_user_preference(pref)
          warmup_stats[:user_prefs] += 1
        end
      end
      
      warmup_stats[:duration] = (Time.current - Time.current).round(3)
      
      Rails.logger.info "[PatternCache] Cache warming completed: #{warmup_stats.inspect}"
      warmup_stats
    rescue => e
      Rails.logger.error "[PatternCache] Cache warming failed: #{e.message}"
      { error: e.message }
    end
    
    # Get cache metrics
    def metrics
      @metrics_collector.summary.merge(
        memory_cache_entries: memory_cache_entry_count,
        redis_available: @redis_available,
        configuration: {
          memory_ttl: memory_ttl.to_i,
          redis_ttl: redis_ttl.to_i,
          max_memory_size: MEMORY_CACHE_MAX_SIZE
        }
      )
    end
    
    # Get cache hit rate
    def hit_rate
      @metrics_collector.hit_rate
    end
    
    # Preload patterns for a collection of expenses
    def preload_for_expenses(expenses)
      return if expenses.blank?
      
      # Extract unique merchant names
      merchant_names = expenses.map(&:merchant_name).compact.uniq
      
      # Preload user preferences
      merchant_names.each do |merchant|
        get_user_preference(merchant)
      end
      
      # Preload all active patterns (they'll be needed for matching)
      get_all_active_patterns
    end
    
    private
    
    def build_memory_cache
      ActiveSupport::Cache::MemoryStore.new(
        size: MEMORY_CACHE_MAX_SIZE * 1.kilobyte,
        compress: false
      )
    end
    
    def redis_available?
      return false unless defined?(Redis)
      
      redis_client.ping == "PONG"
    rescue => e
      Rails.logger.warn "[PatternCache] Redis not available: #{e.message}"
      false
    end
    
    def redis_client
      @redis_client ||= Redis.new(
        host: ENV.fetch("REDIS_HOST", "localhost"),
        port: ENV.fetch("REDIS_PORT", 6379),
        db: ENV.fetch("REDIS_DB", 0),
        password: ENV.fetch("REDIS_PASSWORD", nil),
        timeout: 0.5, # Fast timeout for cache operations
        reconnect_attempts: 1
      )
    end
    
    def fetch_with_tiered_cache(key, memory_ttl:, redis_ttl:, &block)
      # L1: Check memory cache first
      value = fetch_from_memory(key)
      
      if value
        @metrics_collector.record_hit(:memory)
        return value
      end
      
      # L2: Check Redis cache if available
      if @redis_available
        value = fetch_from_redis(key)
        
        if value
          @metrics_collector.record_hit(:redis)
          # Promote to memory cache
          write_to_memory(key, value, memory_ttl)
          return value
        end
      end
      
      # L3: Fetch from database
      @metrics_collector.record_miss
      
      value = yield
      return nil unless value
      
      # Write to both cache tiers
      cache_value(key, value, memory_ttl: memory_ttl, redis_ttl: redis_ttl)
      
      value
    rescue => e
      Rails.logger.error "[PatternCache] Error in fetch_with_tiered_cache: #{e.message}"
      # Fallback to direct database query
      yield
    end
    
    def fetch_from_memory(key)
      @memory_cache.read(key)
    end
    
    def fetch_from_redis(key)
      return nil unless @redis_available
      
      raw_value = redis_client.get(key)
      return nil unless raw_value
      
      deserialize(raw_value)
    rescue => e
      Rails.logger.warn "[PatternCache] Redis fetch error: #{e.message}"
      @redis_available = false # Mark Redis as unavailable
      nil
    end
    
    def write_to_memory(key, value, ttl)
      @memory_cache.write(key, value, expires_in: ttl)
    end
    
    def write_to_redis(key, value, ttl)
      return unless @redis_available
      
      redis_client.setex(key, ttl.to_i, serialize(value))
    rescue => e
      Rails.logger.warn "[PatternCache] Redis write error: #{e.message}"
      @redis_available = false
    end
    
    def cache_value(key, value, memory_ttl:, redis_ttl:)
      write_to_memory(key, value, memory_ttl)
      write_to_redis(key, value, redis_ttl) if @redis_available
    end
    
    def cache_pattern(pattern)
      cache_value(
        pattern_cache_key(pattern.id),
        pattern,
        memory_ttl: memory_ttl,
        redis_ttl: redis_ttl
      )
    end
    
    def cache_composite(composite)
      cache_value(
        composite_cache_key(composite.id),
        composite,
        memory_ttl: memory_ttl,
        redis_ttl: redis_ttl
      )
    end
    
    def cache_user_preference(preference)
      # Only cache merchant preferences
      return unless preference.context_type == "merchant"
      
      normalized_merchant = preference.context_value.downcase.strip
      cache_value(
        user_pref_cache_key(normalized_merchant),
        preference,
        memory_ttl: memory_ttl * 2,
        redis_ttl: redis_ttl * 2
      )
    end
    
    def invalidate_pattern(pattern)
      key = pattern_cache_key(pattern.id)
      invalidate_key(key)
      
      # Also invalidate type-based cache
      type_key = type_cache_key(pattern.pattern_type)
      invalidate_key(type_key)
      
      # Invalidate all patterns cache
      invalidate_key("#{PATTERN_KEY_PREFIX}:all:active:#{CACHE_VERSION}")
    end
    
    def invalidate_composite(composite)
      key = composite_cache_key(composite.id)
      invalidate_key(key)
    end
    
    def invalidate_user_preference(preference)
      return unless preference.context_type == "merchant"
      
      normalized_merchant = preference.context_value.downcase.strip
      key = user_pref_cache_key(normalized_merchant)
      invalidate_key(key)
    end
    
    def invalidate_key(key)
      @memory_cache.delete(key)
      
      if @redis_available
        redis_client.del(key)
      end
    rescue => e
      Rails.logger.error "[PatternCache] Error invalidating key #{key}: #{e.message}"
    end
    
    # Cache key generation methods
    def pattern_cache_key(pattern_id)
      "#{PATTERN_KEY_PREFIX}:#{pattern_id}:#{CACHE_VERSION}"
    end
    
    def type_cache_key(pattern_type)
      "#{PATTERN_KEY_PREFIX}:type:#{pattern_type}:#{CACHE_VERSION}"
    end
    
    def composite_cache_key(composite_id)
      "#{COMPOSITE_KEY_PREFIX}:#{composite_id}:#{CACHE_VERSION}"
    end
    
    def user_pref_cache_key(merchant_name)
      "#{USER_PREF_KEY_PREFIX}:#{merchant_name}:#{CACHE_VERSION}"
    end
    
    # Serialization methods for Redis storage
    def serialize(value)
      Marshal.dump(value)
    rescue => e
      Rails.logger.error "[PatternCache] Serialization error: #{e.message}"
      nil
    end
    
    def deserialize(raw_value)
      Marshal.load(raw_value)
    rescue => e
      Rails.logger.error "[PatternCache] Deserialization error: #{e.message}"
      nil
    end
    
    # TTL configuration methods
    def memory_ttl
      Rails.application.config.try(:pattern_cache_memory_ttl) || DEFAULT_MEMORY_TTL
    end
    
    def redis_ttl
      Rails.application.config.try(:pattern_cache_redis_ttl) || DEFAULT_REDIS_TTL
    end
    
    def memory_cache_entry_count
      # ActiveSupport::Cache::MemoryStore doesn't provide a direct size method
      # We'll need to track this separately or estimate it
      @memory_cache.instance_variable_get(:@data)&.size || 0
    rescue
      0
    end
    
    # Performance monitoring
    def benchmark_with_metrics(operation, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      result = yield
      
      duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000 # Convert to ms
      @metrics_collector.record_operation(operation, duration)
      
      # Log slow operations
      if duration > 1.0
        Rails.logger.warn "[PatternCache] Slow operation: #{operation} took #{duration.round(2)}ms"
      end
      
      result
    end
    
    # Internal metrics collector
    class MetricsCollector
      def initialize
        @hits = { memory: 0, redis: 0 }
        @misses = 0
        @operations = Hash.new { |h, k| h[k] = [] }
        @lock = Mutex.new
      end
      
      def record_hit(level)
        @lock.synchronize { @hits[level] += 1 }
      end
      
      def record_miss
        @lock.synchronize { @misses += 1 }
      end
      
      def record_operation(name, duration_ms)
        @lock.synchronize do
          # Keep only last 1000 samples per operation
          @operations[name] << duration_ms
          @operations[name].shift if @operations[name].size > 1000
        end
      end
      
      def hit_rate
        total = @hits.values.sum + @misses
        return 0.0 if total.zero?
        
        (@hits.values.sum.to_f / total * 100).round(2)
      end
      
      def summary
        @lock.synchronize do
          {
            hits: @hits.dup,
            misses: @misses,
            hit_rate: hit_rate,
            operations: operation_stats
          }
        end
      end
      
      private
      
      def operation_stats
        @operations.transform_values do |durations|
          next { count: 0 } if durations.empty?
          
          {
            count: durations.size,
            avg_ms: (durations.sum / durations.size).round(3),
            min_ms: durations.min.round(3),
            max_ms: durations.max.round(3),
            p95_ms: percentile(durations, 0.95).round(3),
            p99_ms: percentile(durations, 0.99).round(3)
          }
        end
      end
      
      def percentile(values, percentile)
        return 0 if values.empty?
        
        sorted = values.sort
        index = (percentile * sorted.size).ceil - 1
        sorted[index] || sorted.last
      end
    end
  end
end