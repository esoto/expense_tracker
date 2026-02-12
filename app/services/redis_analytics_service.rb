# frozen_string_literal: true

require "redis"
require "connection_pool"

# Services::RedisAnalyticsService provides direct Redis access for high-performance analytics
# and time-series data storage, bypassing Rails cache for better performance
# and more sophisticated Redis features.
#
# Features:
# - Direct Redis connection with connection pooling
# - Time-series data storage with automatic expiration
# - Atomic operations for counters and statistics
# - Pipeline support for bulk operations
# - Cluster-ready design patterns
#
# Usage:
#   Services::RedisAnalyticsService.increment_counter('broadcast_success', tags: { channel: 'SyncStatus' })
#   Services::RedisAnalyticsService.record_timing('broadcast_duration', 0.123, tags: { priority: 'high' })
#   Services::RedisAnalyticsService.get_time_series('broadcast_success', window: 1.hour)
module Services
  class RedisAnalyticsService
  # Redis key prefixes for different data types
  KEY_PREFIXES = {
    counter: "analytics:counter",
    timing: "analytics:timing",
    series: "analytics:series",
    summary: "analytics:summary",
    health: "analytics:health"
  }.freeze

  # Time bucket sizes for different granularities
  TIME_BUCKETS = {
    minute: 60,
    hour: 3600,
    day: 86400,
    week: 604800
  }.freeze

  # Default expiration times
  EXPIRATION = {
    minute: 3.days,
    hour: 2.weeks,
    day: 3.months,
    week: 1.year
  }.freeze

  class << self
    # Get Redis connection from pool
    # @return [Redis] Redis connection
    def redis
      @redis_pool ||= ConnectionPool.new(
        size: redis_pool_size,
        timeout: redis_timeout
      ) do
        Redis.new(redis_config)
      end

      @redis_pool.with { |redis| yield redis }
    rescue ConnectionPool::Error => e
      Rails.logger.error "[REDIS_ANALYTICS] Connection pool error: #{e.message}"
      raise
    end

    # Increment a counter with optional tags and time bucketing
    # @param counter_name [String] Counter name
    # @param increment [Integer] Amount to increment
    # @param tags [Hash] Tags for categorization
    # @param bucket [Symbol] Time bucket granularity (:minute, :hour, :day, :week)
    # @return [Integer] New counter value
    def increment_counter(counter_name, increment: 1, tags: {}, bucket: :hour)
      timestamp = Time.current
      bucket_key = generate_time_bucket_key(counter_name, timestamp, bucket, tags)

      redis do |conn|
        # Use pipeline for efficiency
        conn.pipelined do |pipeline|
          # Increment the counter
          pipeline.incrby(bucket_key, increment)

          # Set expiration if not already set
          pipeline.expire(bucket_key, EXPIRATION[bucket].to_i)

          # Update global counter
          global_key = generate_global_key(counter_name, tags)
          pipeline.incrby(global_key, increment)
          pipeline.expire(global_key, EXPIRATION[:week].to_i)
        end.first # Return the counter increment result
      end
    end

    # Record timing data with percentile calculation
    # @param metric_name [String] Metric name
    # @param duration [Float] Duration in seconds
    # @param tags [Hash] Tags for categorization
    # @param bucket [Symbol] Time bucket granularity
    def record_timing(metric_name, duration, tags: {}, bucket: :hour)
      timestamp = Time.current
      bucket_key = generate_time_bucket_key(metric_name, timestamp, bucket, tags, prefix: :timing)

      # Store timing data for percentile calculations
      redis do |conn|
        conn.pipelined do |pipeline|
          # Add to sorted set for percentile calculations (score = duration)
          pipeline.zadd(bucket_key, duration, "#{timestamp.to_f}:#{SecureRandom.hex(4)}")

          # Limit sorted set size to prevent memory bloat (keep last 10k measurements)
          pipeline.zremrangebyrank(bucket_key, 0, -10001)

          # Set expiration
          pipeline.expire(bucket_key, EXPIRATION[bucket].to_i)

          # Update summary statistics
          update_timing_summary(pipeline, metric_name, duration, tags, timestamp)
        end
      end
    end

    # Get time series data for a metric
    # @param metric_name [String] Metric name
    # @param window [ActiveSupport::Duration] Time window
    # @param bucket [Symbol] Time bucket granularity
    # @param tags [Hash] Tags filter
    # @return [Hash] Time series data
    def get_time_series(metric_name, window: 1.hour, bucket: :hour, tags: {})
      end_time = Time.current
      start_time = end_time - window

      # Generate all bucket keys in the time range
      bucket_keys = generate_time_range_keys(metric_name, start_time, end_time, bucket, tags)

      return { data: [], total: 0, average: 0 } if bucket_keys.empty?

      redis do |conn|
        # Get values for all time buckets
        values = conn.mget(*bucket_keys)

        # Build time series data
        series_data = bucket_keys.map.with_index do |key, index|
          bucket_time = extract_time_from_key(key, bucket)
          {
            timestamp: bucket_time.iso8601,
            value: (values[index] || 0).to_i
          }
        end

        total = values.compact.sum(&:to_i)
        average = total > 0 ? total.to_f / values.compact.size : 0

        {
          data: series_data,
          total: total,
          average: average.round(2),
          window_seconds: window.to_i,
          bucket_size: TIME_BUCKETS[bucket]
        }
      end
    end

    # Get timing percentiles for a metric
    # @param metric_name [String] Metric name
    # @param percentiles [Array<Float>] Percentiles to calculate (0.0-1.0)
    # @param window [ActiveSupport::Duration] Time window
    # @param tags [Hash] Tags filter
    # @return [Hash] Percentile data
    def get_timing_percentiles(metric_name, percentiles: [ 0.5, 0.95, 0.99 ], window: 1.hour, tags: {})
      end_time = Time.current
      start_time = end_time - window

      # Get timing keys in range
      bucket_keys = generate_time_range_keys(
        metric_name, start_time, end_time, :hour, tags, prefix: :timing
      )

      return build_empty_percentiles(percentiles) if bucket_keys.empty?

      redis do |conn|
        # Get all timing measurements and combine them
        all_timings = []

        bucket_keys.each do |key|
          # Get all scores from sorted set
          timings = conn.zrange(key, 0, -1, with_scores: true)
          all_timings.concat(timings.map(&:last)) # Extract scores (durations)
        end

        return build_empty_percentiles(percentiles) if all_timings.empty?

        # Calculate percentiles
        all_timings.sort!
        total_count = all_timings.size

        result = {
          count: total_count,
          min: all_timings.first.round(3),
          max: all_timings.last.round(3),
          average: (all_timings.sum / total_count).round(3),
          percentiles: {}
        }

        percentiles.each do |percentile|
          index = [ (percentile * (total_count - 1)).round, total_count - 1 ].min
          result[:percentiles]["p#{(percentile * 100).to_i}"] = all_timings[index].round(3)
        end

        result
      end
    end

    # Get aggregated metrics summary
    # @param window [ActiveSupport::Duration] Time window
    # @return [Hash] Metrics summary
    def get_metrics_summary(window: 1.hour)
      summary_key = "#{KEY_PREFIXES[:summary]}:#{window.to_i}"

      redis do |conn|
        # Try to get cached summary first
        cached_summary = conn.get(summary_key)
        return JSON.parse(cached_summary) if cached_summary

        # Calculate fresh summary
        summary = calculate_metrics_summary(window)

        # Cache for 1 minute to avoid recalculation
        conn.setex(summary_key, 60, summary.to_json)

        summary
      end
    end

    # Cleanup old analytics data
    # @param older_than [ActiveSupport::Duration] Clean data older than this
    # @return [Integer] Number of keys cleaned
    def cleanup_old_data(older_than: 1.week)
      cutoff_time = Time.current - older_than
      cleaned_count = 0

      redis do |conn|
        # Scan for old analytics keys
        KEY_PREFIXES.values.each do |prefix|
          pattern = "#{prefix}:*"

          conn.scan_each(match: pattern, count: 1000) do |key|
            # Extract timestamp from key if possible
            if key_older_than_cutoff?(key, cutoff_time)
              conn.del(key)
              cleaned_count += 1
            end
          end
        end
      end

      Rails.logger.info "[REDIS_ANALYTICS] Cleaned up #{cleaned_count} old analytics keys"
      cleaned_count
    end

    # Health check for Redis analytics
    # @return [Hash] Health status
    def health_check
      health_key = "#{KEY_PREFIXES[:health]}:status"

      redis do |conn|
        start_time = Time.current

        # Perform basic operations
        conn.set(health_key, "ok")
        status = conn.get(health_key)
        conn.del(health_key)

        duration = (Time.current - start_time).to_f

        {
          status: status == "ok" ? "healthy" : "unhealthy",
          response_time: duration.round(3),
          timestamp: start_time.iso8601,
          redis_info: {
            version: conn.info["redis_version"],
            uptime: conn.info["uptime_in_seconds"].to_i,
            connected_clients: conn.info["connected_clients"].to_i,
            used_memory: conn.info["used_memory_human"]
          }
        }
      end
    rescue StandardError => e
      {
        status: "unhealthy",
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    private

    # Get Redis configuration
    # @return [Hash] Redis config
    def redis_config
      {
        url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
        timeout: redis_timeout,
        reconnect_attempts: 3,
        inherit_socket: false
      }
    end

    # Get Redis pool size from environment
    # @return [Integer] Pool size
    def redis_pool_size
      ENV.fetch("REDIS_ANALYTICS_POOL_SIZE", 10).to_i
    end

    # Get Redis timeout from environment
    # @return [Float] Timeout in seconds
    def redis_timeout
      ENV.fetch("REDIS_ANALYTICS_TIMEOUT", 1.0).to_f
    end

    # Generate time bucket key
    # @param metric_name [String] Metric name
    # @param timestamp [Time] Timestamp
    # @param bucket [Symbol] Bucket granularity
    # @param tags [Hash] Tags
    # @param prefix [Symbol] Key prefix type
    # @return [String] Redis key
    def generate_time_bucket_key(metric_name, timestamp, bucket, tags = {}, prefix: :counter)
      bucket_timestamp = (timestamp.to_i / TIME_BUCKETS[bucket]) * TIME_BUCKETS[bucket]
      tag_string = tags.empty? ? "" : ":#{tags.map { |k, v| "#{k}=#{v}" }.join(',')}"

      "#{KEY_PREFIXES[prefix]}:#{metric_name}#{tag_string}:#{bucket}:#{bucket_timestamp}"
    end

    # Generate global key (no time bucketing)
    # @param metric_name [String] Metric name
    # @param tags [Hash] Tags
    # @return [String] Redis key
    def generate_global_key(metric_name, tags = {})
      tag_string = tags.empty? ? "" : ":#{tags.map { |k, v| "#{k}=#{v}" }.join(',')}"
      "#{KEY_PREFIXES[:counter]}:#{metric_name}#{tag_string}:global"
    end

    # Generate all keys in a time range
    # @param metric_name [String] Metric name
    # @param start_time [Time] Start time
    # @param end_time [Time] End time
    # @param bucket [Symbol] Bucket granularity
    # @param tags [Hash] Tags
    # @param prefix [Symbol] Key prefix type
    # @return [Array<String>] Redis keys
    def generate_time_range_keys(metric_name, start_time, end_time, bucket, tags = {}, prefix: :counter)
      keys = []
      bucket_size = TIME_BUCKETS[bucket]

      current_time = (start_time.to_i / bucket_size) * bucket_size
      end_timestamp = end_time.to_i

      while current_time <= end_timestamp
        keys << generate_time_bucket_key(
          metric_name,
          Time.at(current_time),
          bucket,
          tags,
          prefix: prefix
        )
        current_time += bucket_size
      end

      keys
    end

    # Extract timestamp from bucket key
    # @param key [String] Redis key
    # @param bucket [Symbol] Bucket granularity
    # @return [Time] Timestamp
    def extract_time_from_key(key, bucket)
      timestamp = key.split(":").last.to_i
      Time.at(timestamp)
    end

    # Check if key is older than cutoff time
    # @param key [String] Redis key
    # @param cutoff_time [Time] Cutoff time
    # @return [Boolean] True if older
    def key_older_than_cutoff?(key, cutoff_time)
      # Extract timestamp from key (assumes it's the last component)
      match = key.match(/:(\d{10})$/)
      return false unless match

      key_time = Time.at(match[1].to_i)
      key_time < cutoff_time
    end

    # Update timing summary statistics
    # @param pipeline [Redis::Pipeline] Redis pipeline
    # @param metric_name [String] Metric name
    # @param duration [Float] Duration
    # @param tags [Hash] Tags
    # @param timestamp [Time] Timestamp
    def update_timing_summary(pipeline, metric_name, duration, tags, timestamp)
      summary_key = generate_time_bucket_key(
        "#{metric_name}_summary",
        timestamp,
        :hour,
        tags,
        prefix: :summary
      )

      # Update min/max using Lua script for atomicity
      lua_script = <<~LUA
        local key = KEYS[1]
        local duration = tonumber(ARGV[1])
        local current = redis.call('HMGET', key, 'min', 'max', 'count', 'sum')

        local min_val = current[1] and tonumber(current[1]) or duration
        local max_val = current[2] and tonumber(current[2]) or duration
        local count = current[3] and tonumber(current[3]) or 0
        local sum = current[4] and tonumber(current[4]) or 0

        min_val = math.min(min_val, duration)
        max_val = math.max(max_val, duration)
        count = count + 1
        sum = sum + duration

        redis.call('HMSET', key, 'min', min_val, 'max', max_val, 'count', count, 'sum', sum)
        redis.call('EXPIRE', key, #{EXPIRATION[:hour].to_i})

        return {min_val, max_val, count, sum}
      LUA

      pipeline.eval(lua_script, keys: [ summary_key ], argv: [ duration ])
    end

    # Calculate comprehensive metrics summary
    # @param window [ActiveSupport::Duration] Time window
    # @return [Hash] Metrics summary
    def calculate_metrics_summary(window)
      # This would implement comprehensive metrics calculation
      # For now, return a simplified summary
      {
        window_seconds: window.to_i,
        calculated_at: Time.current.iso8601,
        broadcast_metrics: {
          total_attempts: 0,
          success_rate: 0,
          average_duration: 0
        },
        system_health: health_check
      }
    end

    # Build empty percentiles result
    # @param percentiles [Array<Float>] Percentiles
    # @return [Hash] Empty result
    def build_empty_percentiles(percentiles)
      {
        count: 0,
        min: 0,
        max: 0,
        average: 0,
        percentiles: percentiles.map { |p| [ "p#{(p * 100).to_i}", 0 ] }.to_h
      }
    end
  end
  end
end
