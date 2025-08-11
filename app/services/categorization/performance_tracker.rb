# frozen_string_literal: true

require "concurrent"

module Categorization
  # Thread-safe performance tracking service for categorization operations
  # Monitors and reports on categorization performance metrics with bounded memory usage
  # Ensures operations stay within performance targets (<10ms)
  class PerformanceTracker
    include ActiveSupport::Benchmarkable

    # Performance thresholds
    TARGET_TIME_MS = 10.0
    WARNING_TIME_MS = 8.0
    CRITICAL_TIME_MS = 15.0

    # Sample size for statistics (bounded memory usage)
    MAX_SAMPLES = 1000
    PERCENTILE_SAMPLES = 100

    # Performance states
    HEALTH_STATES = %i[excellent good fair poor unknown].freeze

    attr_reader :start_time

    def initialize(logger: Rails.logger)
      @logger = logger

      # Thread-safe collections using concurrent-ruby
      @operations = Concurrent::Map.new
      @categorizations = Concurrent::Array.new
      @cache_performance = Concurrent::Hash.new.merge!(hits: 0, misses: 0, total: 0)

      # Atomic counters for thread safety
      @cache_hits = Concurrent::AtomicFixnum.new(0)
      @cache_misses = Concurrent::AtomicFixnum.new(0)
      @cache_total = Concurrent::AtomicFixnum.new(0)

      @start_time = Time.current

      # Mutex for complex operations
      @stats_mutex = Mutex.new
      @sample_mutex = Mutex.new
    end

    # Track a categorization operation (thread-safe)
    def track_categorization(expense_id: nil, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cache_hits_before = current_cache_hits
      correlation_id = Thread.current[:correlation_id] || SecureRandom.uuid

      begin
        result = yield

        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        cache_hits_delta = current_cache_hits - cache_hits_before

        record_categorization(
          expense_id: expense_id,
          duration_ms: duration_ms,
          cache_hits: cache_hits_delta,
          successful: result.respond_to?(:successful?) ? result.successful? : false,
          method: result.respond_to?(:method) ? result.method : "unknown",
          correlation_id: correlation_id
        )

        # Log performance issues
        log_performance_issue(duration_ms, expense_id, correlation_id)

        result
      rescue => e
        # Record failed categorization
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        record_categorization(
          expense_id: expense_id,
          duration_ms: duration_ms,
          cache_hits: 0,
          successful: false,
          method: "error",
          correlation_id: correlation_id,
          error: e.class.name
        )
        raise
      end
    end

    # Track a specific operation within categorization (thread-safe)
    def track_operation(operation_name, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = yield

      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Thread-safe operation recording
      @sample_mutex.synchronize do
        operation_samples = @operations[operation_name] ||= Concurrent::Array.new
        operation_samples << duration_ms

        # Maintain bounded size by removing oldest samples
        while operation_samples.size > MAX_SAMPLES
          operation_samples.shift
        end
      end

      result
    rescue => e
      # Still record the failed operation timing
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      @sample_mutex.synchronize do
        operation_samples = @operations["#{operation_name}_errors"] ||= Concurrent::Array.new
        operation_samples << duration_ms
        while operation_samples.size > MAX_SAMPLES
          operation_samples.shift
        end
      end
      raise
    end

    # Record cache performance (thread-safe)
    def record_cache_hit
      @cache_hits.increment
      @cache_total.increment
    end

    def record_cache_miss
      @cache_misses.increment
      @cache_total.increment
    end

    # Get performance summary (thread-safe)
    def summary
      @stats_mutex.synchronize do
        {
          categorizations: categorization_stats,
          operations: operation_stats,
          cache: cache_stats,
          performance_health: performance_health,
          uptime_seconds: Time.current - @start_time,
          memory_usage: memory_usage_stats
        }
      end
    end

    # Check if performance is within target
    def within_target?
      return true if @categorizations.empty?

      avg_time = average_categorization_time
      avg_time <= TARGET_TIME_MS
    end

    # Get detailed metrics for monitoring
    def detailed_metrics
      @stats_mutex.synchronize do
        {
          current_performance: current_performance_metrics,
          by_method: categorization_by_method,
          slow_operations: slow_operations,
          optimization_suggestions: optimization_suggestions,
          percentiles: percentile_metrics,
          error_rates: error_rate_metrics
        }
      end
    end

    # Reset all metrics (thread-safe)
    def reset!
      @stats_mutex.synchronize do
        @operations.clear
        @categorizations.clear
        @cache_hits.value = 0
        @cache_misses.value = 0
        @cache_total.value = 0
        @start_time = Time.current
      end

      @logger.info "[PerformanceTracker] Metrics reset completed"
    end

    # Export metrics for monitoring systems
    def export_metrics
      {
        timestamp: Time.current.iso8601,
        metrics: summary,
        detailed: detailed_metrics
      }
    end

    private

    def record_categorization(expense_id:, duration_ms:, cache_hits:, successful:, method:, correlation_id:, error: nil)
      categorization_data = {
        expense_id: expense_id,
        duration_ms: duration_ms,
        cache_hits: cache_hits,
        successful: successful,
        method: method,
        correlation_id: correlation_id,
        error: error,
        timestamp: Time.current
      }

      # Thread-safe array operations
      @categorizations << categorization_data

      # Maintain bounded size
      @sample_mutex.synchronize do
        while @categorizations.size > MAX_SAMPLES
          @categorizations.shift
        end
      end
    end

    def current_cache_hits
      # Try to get from PatternCache if available
      if defined?(PatternCache) && PatternCache.instance
        PatternCache.instance.metrics[:hits]&.values&.sum || 0
      else
        @cache_hits.value
      end
    rescue
      @cache_hits.value
    end

    def log_performance_issue(duration_ms, expense_id, correlation_id)
      if duration_ms > CRITICAL_TIME_MS
        @logger.error "[PerformanceTracker] Critical performance: #{duration_ms.round(2)}ms " \
                     "for expense #{expense_id} (correlation_id: #{correlation_id})"
      elsif duration_ms > WARNING_TIME_MS
        @logger.warn "[PerformanceTracker] Slow categorization: #{duration_ms.round(2)}ms " \
                    "for expense #{expense_id} (correlation_id: #{correlation_id})"
      end
    end

    def categorization_stats
      return {} if @categorizations.empty?

      samples = @categorizations.to_a
      durations = samples.map { |c| c[:duration_ms] }

      {
        count: samples.size,
        avg_ms: average(durations),
        min_ms: durations.min&.round(3) || 0,
        max_ms: durations.max&.round(3) || 0,
        p50_ms: percentile(durations, 0.50),
        p95_ms: percentile(durations, 0.95),
        p99_ms: percentile(durations, 0.99),
        within_target_pct: within_target_percentage(samples),
        success_rate: success_rate(samples),
        error_rate: error_rate(samples)
      }
    end

    def operation_stats
      stats = {}

      @operations.each do |operation_name, samples|
        durations = samples.to_a
        next if durations.empty?

        stats[operation_name] = {
          count: durations.size,
          avg_ms: average(durations),
          min_ms: durations.min&.round(3) || 0,
          max_ms: durations.max&.round(3) || 0,
          p95_ms: percentile(durations, 0.95),
          within_target_pct: durations.count { |d| d <= TARGET_TIME_MS }.to_f / durations.size * 100
        }
      end

      stats
    end

    def cache_stats
      total = @cache_total.value
      return { hit_rate: 0.0, total: 0 } if total == 0

      hits = @cache_hits.value
      misses = @cache_misses.value

      {
        hits: hits,
        misses: misses,
        total: total,
        hit_rate: (hits.to_f / total * 100).round(2),
        miss_rate: (misses.to_f / total * 100).round(2)
      }
    end

    def performance_health
      return :unknown if @categorizations.empty?

      samples = @categorizations.to_a
      avg_time = average(samples.map { |c| c[:duration_ms] })
      success_pct = success_rate(samples)

      if avg_time <= TARGET_TIME_MS && success_pct >= 95
        :excellent
      elsif avg_time <= WARNING_TIME_MS && success_pct >= 90
        :good
      elsif avg_time <= CRITICAL_TIME_MS && success_pct >= 80
        :fair
      else
        :poor
      end
    end

    def current_performance_metrics
      samples = @categorizations.to_a

      {
        last_100_avg_ms: recent_average(samples, 100),
        last_1000_avg_ms: recent_average(samples, 1000),
        trending: performance_trend(samples),
        current_load: current_load_metrics
      }
    end

    def categorization_by_method
      samples = @categorizations.to_a
      grouped = samples.group_by { |c| c[:method] }

      grouped.transform_values do |method_samples|
        durations = method_samples.map { |c| c[:duration_ms] }
        {
          count: method_samples.size,
          avg_ms: average(durations),
          success_rate: success_rate(method_samples),
          error_rate: error_rate(method_samples)
        }
      end
    end

    def slow_operations
      threshold = CRITICAL_TIME_MS
      slow_ops = {}

      @operations.each do |operation_name, samples|
        durations = samples.to_a
        slow_durations = durations.select { |d| d > threshold }

        next if slow_durations.empty?

        slow_ops[operation_name] = {
          slow_count: slow_durations.size,
          slow_percentage: (slow_durations.size.to_f / durations.size * 100).round(2),
          max_ms: durations.max&.round(3) || 0,
          avg_slow_ms: average(slow_durations)
        }
      end

      slow_ops
    end

    def optimization_suggestions
      suggestions = []

      # Check cache hit rate
      cache_data = cache_stats
      if cache_data[:total] > 0 && cache_data[:hit_rate] < 70
        suggestions << {
          type: :cache,
          message: "Low cache hit rate (#{cache_data[:hit_rate]}%). Consider warming cache or increasing TTL.",
          severity: :warning
        }
      end

      # Check for consistently slow operations
      @operations.each do |op_name, samples|
        durations = samples.to_a
        next if durations.empty?

        avg = average(durations)
        if avg > TARGET_TIME_MS / 2
          suggestions << {
            type: :operation,
            message: "Operation '#{op_name}' is slow (avg: #{avg.round(2)}ms). Consider optimization.",
            severity: avg > TARGET_TIME_MS ? :critical : :warning
          }
        end
      end

      # Check overall performance
      samples = @categorizations.to_a
      if samples.any?
        avg_time = average(samples.map { |c| c[:duration_ms] })
        if avg_time > TARGET_TIME_MS
          suggestions << {
            type: :performance,
            message: "Average time (#{avg_time.round(2)}ms) exceeds target (#{TARGET_TIME_MS}ms).",
            severity: :critical
          }
        end

        # Check error rate
        err_rate = error_rate(samples)
        if err_rate > 5.0
          suggestions << {
            type: :reliability,
            message: "High error rate (#{err_rate.round(2)}%). Investigate failures.",
            severity: :critical
          }
        end
      end

      suggestions
    end

    def percentile_metrics
      samples = @categorizations.to_a
      return {} if samples.empty?

      durations = samples.map { |c| c[:duration_ms] }

      {
        p10: percentile(durations, 0.10),
        p25: percentile(durations, 0.25),
        p50: percentile(durations, 0.50),
        p75: percentile(durations, 0.75),
        p90: percentile(durations, 0.90),
        p95: percentile(durations, 0.95),
        p99: percentile(durations, 0.99)
      }
    end

    def error_rate_metrics
      samples = @categorizations.to_a
      grouped_by_error = samples.group_by { |c| c[:error] }

      error_types = grouped_by_error.reject { |k, _| k.nil? }

      {
        total_errors: samples.count { |c| !c[:successful] },
        error_rate: error_rate(samples),
        errors_by_type: error_types.transform_values(&:size)
      }
    end

    def memory_usage_stats
      {
        categorization_samples: @categorizations.size,
        operation_types: @operations.keys.size,
        total_operation_samples: @operations.values.sum { |v| v.size },
        estimated_memory_kb: estimate_memory_usage_kb
      }
    end

    def average_categorization_time
      samples = @categorizations.to_a
      return 0.0 if samples.empty?

      durations = samples.map { |c| c[:duration_ms] }
      average(durations)
    end

    def recent_average(samples, count)
      recent = samples.last(count)
      return 0.0 if recent.empty?

      durations = recent.map { |c| c[:duration_ms] }
      average(durations)
    end

    def performance_trend(samples)
      return :stable if samples.size < 100

      first_half = samples.first(samples.size / 2)
      second_half = samples.last(samples.size / 2)

      first_avg = average(first_half.map { |c| c[:duration_ms] })
      second_avg = average(second_half.map { |c| c[:duration_ms] })

      diff_pct = ((second_avg - first_avg) / first_avg * 100).abs

      if diff_pct < 5
        :stable
      elsif second_avg < first_avg
        :improving
      else
        :degrading
      end
    end

    def current_load_metrics
      # Estimate current system load based on recent activity
      recent_samples = @categorizations.to_a.last(10)

      return { load: :idle, requests_per_second: 0 } if recent_samples.empty?

      time_span = recent_samples.last[:timestamp] - recent_samples.first[:timestamp]
      return { load: :idle, requests_per_second: 0 } if time_span == 0

      requests_per_second = recent_samples.size / time_span.to_f

      load = if requests_per_second < 1
               :low
      elsif requests_per_second < 10
               :moderate
      elsif requests_per_second < 50
               :high
      else
               :very_high
      end

      { load: load, requests_per_second: requests_per_second.round(2) }
    end

    def within_target_percentage(samples)
      return 0.0 if samples.empty?

      within_target = samples.count { |c| c[:duration_ms] <= TARGET_TIME_MS }
      (within_target.to_f / samples.size * 100).round(2)
    end

    def success_rate(samples)
      return 0.0 if samples.empty?

      successful = samples.count { |c| c[:successful] }
      (successful.to_f / samples.size * 100).round(2)
    end

    def error_rate(samples)
      return 0.0 if samples.empty?

      errors = samples.count { |c| !c[:successful] }
      (errors.to_f / samples.size * 100).round(2)
    end

    def average(values)
      return 0.0 if values.empty?
      (values.sum.to_f / values.size).round(3)
    end

    def percentile(values, pct)
      return 0.0 if values.empty?

      sorted = values.sort
      index = (pct * sorted.size).ceil - 1
      index = [ index, 0 ].max
      sorted[index]&.round(3) || 0.0
    end

    def estimate_memory_usage_kb
      # Rough estimate of memory usage
      categorization_size = @categorizations.size * 0.5 # ~500 bytes per record
      operation_samples = @operations.values.sum { |v| v.size } * 0.1 # ~100 bytes per sample

      ((categorization_size + operation_samples) / 1024.0).round(2)
    end
  end
end
