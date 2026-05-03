# frozen_string_literal: true

module Services::Categorization
  # High-performance two-tier caching service for categorization patterns
  # Implements memory cache (L1) and Rails.cache (L2, backed by Solid Cache) with automatic fallback
  # Ensures < 1ms response times for pattern lookups with monitoring capabilities
  class PatternCache
    include ActiveSupport::Benchmarkable
    include CacheVersioning

    # Cache configuration constants (use centralized config if available)
    MEMORY_CACHE_MAX_SIZE = if defined?(Services::Infrastructure::PerformanceConfig)
                              Services::Infrastructure::PerformanceConfig::CACHE_CONFIG[:memory_cache_max_size_mb] * 1024
    else
                              50 * 1024 # 50MB memory cache size in kilobytes
    end
    DEFAULT_MEMORY_TTL = if defined?(Services::Infrastructure::PerformanceConfig)
                          Services::Infrastructure::PerformanceConfig::CACHE_CONFIG[:memory_cache_ttl]
    else
                          15.minutes
    end
    DEFAULT_L2_TTL = if defined?(Services::Infrastructure::PerformanceConfig)
                       Services::Infrastructure::PerformanceConfig::CACHE_CONFIG[:l2_cache_ttl]
    else
                       1.hour
    end
    CACHE_VERSION = if defined?(Services::Infrastructure::PerformanceConfig)
                     Services::Infrastructure::PerformanceConfig.cache_version
    else
                     "v1"
    end
    METRICS_SAMPLE_RATE = if defined?(Services::Infrastructure::PerformanceConfig)
                           Services::Infrastructure::PerformanceConfig::MONITORING_CONFIG[:metrics_sample_rate]
    else
                           0.01 # Sample 1% of requests for detailed metrics
    end

    # Cache key namespace and prefixes
    CACHE_NAMESPACE = "cat:"
    PATTERN_KEY_PREFIX = "#{CACHE_NAMESPACE}pattern"
    COMPOSITE_KEY_PREFIX = "#{CACHE_NAMESPACE}composite"
    USER_PREF_KEY_PREFIX = "#{CACHE_NAMESPACE}user_pref"
    METRICS_KEY = "#{CACHE_NAMESPACE}metrics"

    # Version key stored in Rails.cache for atomic cross-process increment
    PATTERN_VERSION_KEY = "#{CACHE_NAMESPACE}pattern_cache_version"

    class << self
      # Get or create a default instance (for services that haven't migrated to DI yet)
      # Thread-safe: Mutex prevents concurrent first-access from creating duplicate instances
      def instance
        @singleton_mutex ||= Mutex.new
        @singleton_mutex.synchronize { @default_instance ||= new }
      end

      # Factory method for creating cache instances
      def create(options = {})
        new(options)
      end

      # Reset the singleton instance (test use only)
      def reset_singleton!
        @default_instance = nil
      end
    end

    def initialize(options = {})
      @memory_cache = build_memory_cache
      @metrics_collector = MetricsCollector.new
      @lock = Mutex.new
      @logger = options.fetch(:logger, Rails.logger)
      @healthy = true

      @logger.info "[PatternCache] Initialized with L1 (Memory) + L2 (Rails.cache) caching"

      # Warm cache in production for consistent performance
      warm_cache if Rails.env.production? && options.fetch(:warm_cache, true)
    end

    # Get a single pattern by ID with caching
    def get_pattern(pattern_id)
      return nil unless pattern_id

      benchmark_with_metrics("get_pattern") do
        fetch_with_tiered_cache(
          pattern_cache_key(pattern_id),
          memory_ttl: memory_ttl,
          l2_ttl: l2_ttl
        ) do
          CategorizationPattern.active.find_by(id: pattern_id)
        end
      end
    end

    # Get patterns relevant to an expense
    def get_patterns_for_expense(expense)
      return [] unless expense

      # Return cached patterns if available (for batch processing)
      return Thread.current[:pattern_cache_preloaded] if Thread.current[:pattern_cache_preloaded]

      benchmark_with_metrics("get_patterns_for_expense") do
        # Get all active patterns that might match this expense
        patterns = CategorizationPattern
          .active
          .includes(:category)
          .order(usage_count: :desc, success_rate: :desc)
          .limit(100)

        patterns.to_a
      end
    end

    # Preload patterns for multiple texts
    def preload_for_texts(texts)
      return if texts.blank?

      # Load all patterns once for batch processing
      Thread.current[:pattern_cache_preloaded] = CategorizationPattern
        .active
        .includes(:category)
        .order(usage_count: :desc, success_rate: :desc)
        .to_a
    end

    # Clear preloaded patterns after batch processing
    def clear_preloaded_patterns
      Thread.current[:pattern_cache_preloaded] = nil
    end

    # Invalidate cache for a specific category by bumping the pattern cache version.
    # All keys embed the version, so stale entries are simply ignored — no
    # delete_matched scan required.
    def invalidate_category(category_id)
      increment_pattern_cache_version
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
          l2_ttl: l2_ttl / 2
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
          l2_ttl: l2_ttl
        ) do
          CompositePattern.active.find_by(id: composite_id)
        end
      end
    end

    # Get user preference with caching.
    #
    # PR 9: user preferences are per-user via email_account_id — they must
    # not leak across users. The lookup now requires email_account_id so
    # each user's history is isolated. Cache keys include the account id
    # so different users' entries don't overwrite each other.
    #
    # Passing `nil` for email_account_id returns `nil` (fail closed) —
    # an anonymous call has no owner context to match preferences to.
    def get_user_preference(merchant_name, email_account_id = nil)
      return nil if merchant_name.blank?
      return nil if email_account_id.nil?

      benchmark_with_metrics("get_user_preference") do
        normalized_merchant = merchant_name.downcase.strip

        fetch_with_tiered_cache(
          user_pref_cache_key(normalized_merchant, email_account_id),
          memory_ttl: memory_ttl * 2, # Longer TTL for user preferences
          l2_ttl: l2_ttl * 2
        ) do
          UserCategoryPreference.find_by(
            email_account_id: email_account_id,
            context_type: "merchant",
            context_value: normalized_merchant
          )
        end
      end
    end

    # Get all active patterns (used for bulk operations)
    def get_all_active_patterns
      benchmark_with_metrics("get_all_active_patterns") do
        fetch_with_tiered_cache(
          all_active_cache_key,
          memory_ttl: 1.minute, # Short TTL for large collections
          l2_ttl: 5.minutes
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

    # Clear all caches by bumping the version key (stale keys expire naturally)
    def invalidate_all
      @lock.synchronize do
        @memory_cache.clear
        increment_pattern_cache_version

        Rails.logger.info "[PatternCache] All caches cleared"
      end
    rescue => e
      Rails.logger.error "[PatternCache] Error clearing caches: #{e.message}"
    end

    # Warm cache with commonly used patterns
    def warm_cache
      Rails.logger.info "[PatternCache] Starting cache warming..."
      start_time = Time.current

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

      warmup_stats[:duration] = (Time.current - start_time).round(3)

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
        l2_cache_available: Rails.cache.respond_to?(:write),
        configuration: {
          memory_ttl: memory_ttl.to_i,
          l2_ttl: l2_ttl.to_i,
          max_memory_size: MEMORY_CACHE_MAX_SIZE
        }
      )
    end

    # Get cache hit rate
    def hit_rate
      @metrics_collector.hit_rate
    end

    # Check service health
    def healthy?
      @healthy = begin
        # Check memory cache is responding
        @memory_cache.read("health_check_#{Time.current.to_i}")

        # Check L2 (Rails.cache) is responding
        Rails.cache.write("cat:health_check", true, expires_in: 30.seconds)

        # Check metrics are being collected. hit_rate may be nil if no
        # lookups have happened yet; that's a healthy "no traffic" state,
        # not a failure. The actual contract for this method is "did the
        # health probes succeed?" — the metrics call merely needs to not
        # raise.
        @metrics_collector.hit_rate

        true
      rescue => e
        Rails.logger.error "[PatternCache] Health check failed: #{e.message}"
        false
      end
    end

    # Reset cache and metrics by bumping the version key (stale keys expire naturally)
    def reset!
      @lock.synchronize do
        @memory_cache.clear
        @metrics_collector = MetricsCollector.new
        increment_pattern_cache_version

        Rails.logger.info "[PatternCache] Cache and metrics reset completed"
      end
    rescue => e
      Rails.logger.error "[PatternCache] Reset failed: #{e.message}"
    end

    # Get cache statistics (alias for metrics for compatibility)
    def stats
      metrics_data = metrics
      rate = hit_rate
      hits_hash = metrics_data[:hits]
      {
        entries: metrics_data[:memory_cache_entries] || 0,
        memory_bytes: (metrics_data[:memory_cache_entries] || 0) * 1024, # Rough estimate
        # Sum the per-tier hash directly. Pre-PER-549 this read
        # `metrics_data.dig(:hits, :total)` but `:total` was never a key
        # in the {memory:, redis:} shape, so #stats has been silently
        # returning hits=0 to dashboard helpers and the /api/health
        # endpoint since the metrics shape was introduced.
        hits: hits_hash.is_a?(Hash) ? hits_hash.values.sum : (hits_hash || 0),
        misses: metrics_data[:misses] || 0,
        evictions: metrics_data[:evictions] || 0,
        # Decimal in [0, 1] for callers that want a fraction; nil when no
        # lookups have happened yet so callers can distinguish "quiet"
        # from "0% hit rate".
        hit_rate: rate.nil? ? nil : (rate / 100.0)
      }
    end

    # Clear memory cache (useful for cleanup in long-running processes)
    def clear_memory_cache
      @lock.synchronize do
        @memory_cache.clear
        Rails.logger.info "[PatternCache] Memory cache cleared"
      end
    end

    # Preload patterns for a collection of expenses
    def preload_for_expenses(expenses)
      return if expenses.blank?

      # PR 9: preload user preferences keyed by (merchant, email_account)
      # so each user's preferences are isolated in the cache. API-layer
      # ephemeral expenses may lack email_account_id — skip those.
      expenses.each do |expense|
        next unless expense.merchant_name?
        next unless expense.respond_to?(:email_account_id) && expense.email_account_id.present?

        get_user_preference(expense.merchant_name, expense.email_account_id)
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

    def fetch_with_tiered_cache(key, memory_ttl:, l2_ttl:, &block)
      # L1: Check memory cache first
      value = fetch_from_memory(key)

      if value
        @metrics_collector.record_hit(:memory)
        return value
      end

      # L2: Use Rails.cache.fetch which handles read/write/lock atomically
      race_condition_ttl = if defined?(Services::Infrastructure::PerformanceConfig)
                            Services::Infrastructure::PerformanceConfig.race_condition_ttl
      else
                            10.seconds
      end

      # Detect L2 hit vs miss by tracking whether the fetch block ran. The
      # earlier comment claimed "we handle this when we promote to L1" but
      # the actual record_hit(:redis) call was never wired up — the result
      # was that every L2 hit went uncounted, which is what produced the
      # always-0% hit rate alert (PER-549).
      block_ran = false
      value = Rails.cache.fetch(key, expires_in: l2_ttl, race_condition_ttl: race_condition_ttl) do
        block_ran = true
        @metrics_collector.record_miss
        yield
      end

      if value
        @metrics_collector.record_hit(:redis) unless block_ran
        # Promote to L1 memory cache
        write_to_memory(key, value, memory_ttl)
      end

      value
    rescue => e
      Rails.logger.error "[PatternCache] Error in fetch_with_tiered_cache: #{e.message}"
      # Fallback to direct database query
      yield
    end

    def fetch_from_memory(key)
      @memory_cache.read(key)
    end

    def write_to_memory(key, value, ttl)
      @memory_cache.write(key, value, expires_in: ttl)
    end

    def cache_value(key, value, memory_ttl:, l2_ttl:)
      write_to_memory(key, value, memory_ttl)
      Rails.cache.write(key, value, expires_in: l2_ttl)
    end

    def cache_pattern(pattern)
      cache_value(
        pattern_cache_key(pattern.id),
        pattern,
        memory_ttl: memory_ttl,
        l2_ttl: l2_ttl
      )
    end

    def cache_composite(composite)
      cache_value(
        composite_cache_key(composite.id),
        composite,
        memory_ttl: memory_ttl,
        l2_ttl: l2_ttl
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
        l2_ttl: l2_ttl * 2
      )
    end

    def invalidate_pattern(pattern)
      key = pattern_cache_key(pattern.id)
      invalidate_key(key)

      # Also invalidate type-based cache
      type_key = type_cache_key(pattern.pattern_type)
      invalidate_key(type_key)

      # Invalidate all patterns cache
      invalidate_key(all_active_cache_key)
    end

    def invalidate_composite(composite)
      key = composite_cache_key(composite.id)
      invalidate_key(key)
    end

    def invalidate_user_preference(preference)
      return unless preference.context_type == "merchant"

      normalized_merchant = preference.context_value.downcase.strip
      # PR 9: cache keys include email_account_id, so invalidation must
      # target the specific user's key. Invalidate just this preference's
      # entry instead of a broad sweep.
      key = user_pref_cache_key(normalized_merchant, preference.email_account_id)
      invalidate_key(key)
    end

    def invalidate_key(key)
      @memory_cache.delete(key)
      Rails.cache.delete(key)
    rescue => e
      Rails.logger.error "[PatternCache] Error invalidating key #{key}: #{e.message}"
    end

    # Cache key generation methods — every key embeds the dynamic pattern version
    # so that incrementing the version atomically invalidates all pattern-related
    # entries without any delete_matched scan.
    def pattern_cache_key(pattern_id)
      "#{PATTERN_KEY_PREFIX}:#{pattern_id}:#{CACHE_VERSION}:pv#{pattern_cache_version}"
    end

    def type_cache_key(pattern_type)
      "#{PATTERN_KEY_PREFIX}:type:#{pattern_type}:#{CACHE_VERSION}:pv#{pattern_cache_version}"
    end

    def all_active_cache_key
      "#{PATTERN_KEY_PREFIX}:all:active:#{CACHE_VERSION}:pv#{pattern_cache_version}"
    end

    def composite_cache_key(composite_id)
      "#{COMPOSITE_KEY_PREFIX}:#{composite_id}:#{CACHE_VERSION}"
    end

    def user_pref_cache_key(merchant_name, email_account_id = nil)
      # PR 9: include the account id so different users' preferences
      # don't overwrite each other in the shared cache.
      "#{USER_PREF_KEY_PREFIX}:#{email_account_id || 'global'}:#{merchant_name}:#{CACHE_VERSION}"
    end

    # Returns the current pattern cache version integer, reading from Rails.cache
    # so the value is shared across all processes/threads.
    # Initializes to 0 if absent; increment_pattern_cache_version bumps it to >=1.
    def pattern_cache_version
      Rails.cache.read(PATTERN_VERSION_KEY) || 0
    end

    # Atomically increment the pattern cache version using the shared
    # CacheVersioning concern, which handles both MemoryStore and
    # distributed cache backends (Redis/Memcache) safely.
    def increment_pattern_cache_version
      atomic_cache_increment(PATTERN_VERSION_KEY, log_tag: "[PatternCache]", logger: @logger)
    end

    # TTL configuration methods
    def memory_ttl
      Rails.application.config.try(:pattern_cache_memory_ttl) || DEFAULT_MEMORY_TTL
    end

    def l2_ttl
      Rails.application.config.try(:pattern_cache_l2_ttl) || DEFAULT_L2_TTL
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
    #
    # Hit/miss counters are backed by Rails.cache (Solid Cache → Postgres) so
    # that the running Puma process AND the forked Solid Queue worker
    # processes (`processes: 2` for high priority + `processes: 1` for
    # standard, per config/queue.yml) share a single source of truth.
    #
    # Before this change, every process had its own per-instance counters,
    # the PerformanceMonitoring thread runs in only one of them, and most
    # real categorizations happen in different processes — so the monitoring
    # thread always reported 0% hit rate even when categorization was
    # working perfectly (PER-549).
    #
    # Operation timing samples (`@operations`) stay in-process — they're a
    # debugging aid, not a cross-process metric, and shipping them through
    # Rails.cache on every cached lookup would dwarf the underlying ops.
    class MetricsCollector
      # Hit/miss keys are namespaced under the pattern cache and rotate
      # daily, so today's counts are isolated from older windows and old
      # windows expire naturally via Solid Cache's max_age. Rails.cache has
      # no native key TTL on increment-only flows; the explicit window key
      # handles rotation without the write+increment dance.
      COUNTER_NAMESPACE = "#{CACHE_NAMESPACE}metrics:".freeze
      WINDOW_TTL        = 25.hours # one full window plus the rotation overlap

      # Test helper: clears the current window's hit/miss counters
      # globally across every process reading this Rails.cache. Use in
      # spec before-blocks so prior examples don't pollute the asserted
      # counts. Not for production — counters are window-rotated and
      # auto-expire via Solid Cache's max_age, and zeroing them mid-day
      # would silence the very alerts PER-549/PER-550 added.
      def self.reset_window!
        raise "reset_window! is a test helper; never invoke from production" if Rails.env.production?

        Rails.cache.delete("#{COUNTER_NAMESPACE}hits:memory:#{Date.current}")
        Rails.cache.delete("#{COUNTER_NAMESPACE}hits:redis:#{Date.current}")
        Rails.cache.delete("#{COUNTER_NAMESPACE}misses:#{Date.current}")
      end

      def initialize
        @operations = Hash.new { |h, k| h[k] = [] }
        @lock = Mutex.new
      end

      def record_hit(level)
        cache_increment("hits:#{level}")
      end

      def record_miss
        cache_increment("misses")
      end

      def record_operation(name, duration_ms)
        @lock.synchronize do
          # Keep only last 1000 samples per operation
          @operations[name] << duration_ms
          @operations[name].shift if @operations[name].size > 1000
        end
      end

      # Returns the hit rate as a percentage (0..100) for the current window,
      # or nil when no lookups have happened yet. Returning nil instead of
      # 0.0 lets the monitoring layer distinguish "no traffic" from "all
      # misses" so it doesn't fire a critical alert during quiet periods.
      def hit_rate
        h = hits
        m = misses_count
        total = h.values.sum + m
        return nil if total.zero?

        (h.values.sum.to_f / total * 100).round(2)
      end

      def hits
        { memory: cache_read("hits:memory"), redis: cache_read("hits:redis") }
      end

      def misses_count
        cache_read("misses")
      end

      def summary
        # hits / misses_count / hit_rate read from Rails.cache and don't
        # need the in-process @lock — fetch them outside the synchronize
        # block so a slow Rails.cache read can't serialize concurrent
        # summary calls. The lock only guards @operations.
        cache_hits = hits
        cache_misses = misses_count
        cache_hit_rate = hit_rate

        ops = @lock.synchronize { operation_stats }

        {
          hits: cache_hits,
          misses: cache_misses,
          hit_rate: cache_hit_rate,
          operations: ops
        }
      end

      private

      def cache_increment(suffix)
        # Solid Cache's `increment` is upsert-atomic: missing key → seeds
        # at amount, existing → SELECT...FOR UPDATE-protected increment.
        # The earlier "exist? + write 0 + increment" sequence assumed
        # Memcached semantics ("raises on missing key") which Solid Cache
        # does not share. Single round-trip on every code path.
        # `expires_in:` only takes effect on the seeding write — once the
        # key exists, Solid Cache preserves the original `expires_at`.
        # That's fine here because window keys rotate by date suffix, so
        # each new day's first increment establishes the TTL fresh.
        Rails.cache.increment(window_key(suffix), 1, expires_in: WINDOW_TTL)
      rescue StandardError => e
        # Don't let a metrics-cache hiccup propagate into the lookup path.
        # The lookup result is the user-visible thing; metrics are
        # diagnostic and can degrade gracefully.
        Rails.logger.warn "[PatternCache::MetricsCollector] cache_increment(#{suffix}) failed: #{e.class}: #{e.message}"
      end

      def cache_read(suffix)
        Rails.cache.read(window_key(suffix), raw: true).to_i
      rescue StandardError
        0
      end

      def window_key(suffix)
        "#{COUNTER_NAMESPACE}#{suffix}:#{Date.current}"
      end

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
