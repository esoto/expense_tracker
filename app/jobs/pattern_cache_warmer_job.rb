# frozen_string_literal: true

# Background job for warming the pattern cache periodically
# This ensures frequently used patterns are always cached for optimal performance
class PatternCacheWarmerJob < ApplicationJob
  queue_as :low

  # Retry configuration for resilience
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform
    Rails.logger.info "[PatternCacheWarmer] Starting cache warming job..."

    start_time = Time.current

    # Get the cache instance
    cache = Services::Categorization::PatternCache.instance

    # Perform memory cleanup if needed
    cleanup_memory_if_needed(cache)

    # Perform cache warming
    stats = cache.warm_cache

    # Calculate duration
    duration = Time.current - start_time
    stats[:duration] = duration.round(3)

    # Log results
    if stats[:error]
      Rails.logger.error "[PatternCacheWarmer] Cache warming failed: #{stats[:error]}"
      report_error(stats)
    else
      Rails.logger.info "[PatternCacheWarmer] Cache warming completed successfully"
      Rails.logger.info "[PatternCacheWarmer] Stats: #{stats.inspect}"
      report_success(stats)
    end

    # Check cache health
    check_cache_health(cache)

    stats
  rescue => e
    Rails.logger.error "[PatternCacheWarmer] Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Report the error
    report_error({ error: e.message, backtrace: e.backtrace.first(5) })

    # Re-raise to trigger retry
    raise
  end

  private

  def report_success(stats)
    # Report metrics if monitoring service is available
    if defined?(Services::Infrastructure::MonitoringService)
      Services::Infrastructure::MonitoringService.record_metric(
        "pattern_cache.warming",
        {
          patterns_cached: stats[:patterns],
          composites_cached: stats[:composites],
          user_prefs_cached: stats[:user_prefs],
          duration_seconds: stats[:duration]
        },
        tags: {
          status: "success",
          job_id: job_id,
          queue: queue_name
        }
      )
    end

    # Broadcast success event if needed
    broadcast_event("cache_warming_completed", stats)
  end

  def report_error(error_details)
    # Report error metrics
    if defined?(Services::Infrastructure::MonitoringService)
      Services::Infrastructure::MonitoringService.record_error(
        "pattern_cache.warming_failed",
        error_details,
        tags: {
          job_id: job_id,
          queue: queue_name
        }
      )
    end

    # Broadcast error event
    broadcast_event("cache_warming_failed", error_details)
  end

  def cleanup_memory_if_needed(cache)
    metrics = cache.metrics
    memory_entries = metrics[:memory_cache_entries] || 0

    # Get thresholds from configuration
    warning_threshold = if defined?(Services::Infrastructure::PerformanceConfig)
                          Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :memory_entries, :warning)
    else
                          10_000
    end

    if memory_entries > warning_threshold
      Rails.logger.info "[PatternCacheWarmer] Memory cache has #{memory_entries} entries, performing cleanup..."

      # Clear stale entries from memory cache
      if cache.respond_to?(:clear_memory_cache)
        cache.clear_memory_cache
        Rails.logger.info "[PatternCacheWarmer] Memory cache cleared"
      end

      # Force garbage collection to free memory
      GC.start if memory_entries > warning_threshold * 2

      # Report cleanup
      if defined?(Services::Infrastructure::MonitoringService)
        Services::Infrastructure::MonitoringService.record_metric(
          "pattern_cache.memory_cleanup",
          {
            entries_before: memory_entries,
            threshold: warning_threshold
          },
          tags: { job_id: job_id }
        )
      end
    end
  end

  def check_cache_health(cache)
    metrics = cache.metrics

    # Check hit rate using configuration
    hit_rate = metrics[:hit_rate] || 0
    target_hit_rate = if defined?(Services::Infrastructure::PerformanceConfig)
                        Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :hit_rate, :target)
    else
                        80.0
    end

    if hit_rate < target_hit_rate
      Rails.logger.warn "[PatternCacheWarmer] Low cache hit rate: #{hit_rate}% (target: #{target_hit_rate}%)"
    end

    # Check memory usage using configuration
    memory_entries = metrics[:memory_cache_entries] || 0
    warning_threshold = if defined?(Services::Infrastructure::PerformanceConfig)
                          Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :memory_entries, :warning)
    else
                          10_000
    end

    if memory_entries > warning_threshold
      Rails.logger.warn "[PatternCacheWarmer] High memory cache entries: #{memory_entries} (warning: >#{warning_threshold})"
    end

    # Check Redis availability
    unless metrics[:redis_available]
      Rails.logger.warn "[PatternCacheWarmer] Redis is not available - using memory cache only"
    end
  end

  def broadcast_event(event_type, data)
    return unless defined?(ActionCable) && ActionCable.server.present?

    ActionCable.server.broadcast(
      "system_events",
      {
        event: event_type,
        timestamp: Time.current.iso8601,
        data: data
      }
    )
  rescue => e
    Rails.logger.error "[PatternCacheWarmer] Failed to broadcast event: #{e.message}"
  end
end
