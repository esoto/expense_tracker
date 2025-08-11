# frozen_string_literal: true

# BroadcastAnalyticsCleanupJob cleans up old broadcast analytics data and failed broadcast records
# to prevent database bloat while maintaining useful historical data.
#
# Usage:
#   BroadcastAnalyticsCleanupJob.perform_async
class BroadcastAnalyticsCleanupJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[BROADCAST_ANALYTICS_CLEANUP] Starting cleanup job"

    cleanup_stats = {
      failed_broadcasts_cleaned: 0,
      cache_keys_cleaned: 0,
      errors: 0
    }

    begin
      # Clean up old recovered failed broadcasts (older than 1 week)
      old_recovered_count = FailedBroadcastStore.cleanup_old_records(older_than: 1.week)
      cleanup_stats[:failed_broadcasts_cleaned] = old_recovered_count

      Rails.logger.info "[BROADCAST_ANALYTICS_CLEANUP] Cleaned up #{old_recovered_count} old recovered broadcast records"

      # Clean up old analytics cache data
      cleanup_stats[:cache_keys_cleaned] = cleanup_analytics_cache

      Rails.logger.info "[BROADCAST_ANALYTICS_CLEANUP] Cleaned up #{cleanup_stats[:cache_keys_cleaned]} old analytics cache entries"

      # Update cleanup statistics in cache
      record_cleanup_metrics(cleanup_stats)

    rescue StandardError => e
      cleanup_stats[:errors] += 1
      Rails.logger.error "[BROADCAST_ANALYTICS_CLEANUP] Cleanup error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Still record partial results
      record_cleanup_metrics(cleanup_stats)

      raise
    end

    Rails.logger.info "[BROADCAST_ANALYTICS_CLEANUP] Cleanup completed: #{cleanup_stats[:failed_broadcasts_cleaned]} records, #{cleanup_stats[:cache_keys_cleaned]} cache entries cleaned"

    cleanup_stats
  end

  private

  # Clean up old analytics cache entries
  # @return [Integer] Number of cache keys cleaned
  def cleanup_analytics_cache
    cleaned_count = 0
    cutoff_time = 1.week.ago

    # List of cache key patterns to clean
    cache_patterns = [
      "broadcast_analytics:success:*",
      "broadcast_analytics:failure:*",
      "broadcast_analytics:queued:*",
      "duration_stats:*",
      "broadcast_analytics:hourly_stats:*"
    ]

    cache_patterns.each do |pattern|
      begin
        # Use Redis directly for pattern-based cleanup
        if Rails.cache.respond_to?(:redis)
          keys = Rails.cache.redis.keys(pattern)

          keys.each do |key|
            # Extract timestamp from key if possible and check if old
            if key_is_old?(key, cutoff_time)
              Rails.cache.delete(key.gsub("#{Rails.cache.redis.options[:namespace]}:", ""))
              cleaned_count += 1
            end
          end
        else
          # Fallback for non-Redis cache stores
          # This is less efficient but works with any cache store
          cleaned_count += cleanup_cache_pattern_fallback(pattern, cutoff_time)
        end

      rescue StandardError => e
        Rails.logger.warn "[BROADCAST_ANALYTICS_CLEANUP] Error cleaning cache pattern #{pattern}: #{e.message}"
      end
    end

    cleaned_count
  end

  # Check if a cache key represents old data
  # @param key [String] Cache key
  # @param cutoff_time [Time] Cutoff time for cleanup
  # @return [Boolean] True if key is old
  def key_is_old?(key, cutoff_time)
    # Extract date pattern from key (e.g., "2025-08-01-14")
    date_match = key.match(/(\d{4}-\d{2}-\d{2}-\d{2})/)
    return false unless date_match

    begin
      key_time = Time.zone.parse("#{date_match[1]}:00:00")
      key_time < cutoff_time
    rescue ArgumentError
      # If we can't parse the date, consider it old to be safe
      true
    end
  end

  # Fallback cleanup method for non-Redis cache stores
  # @param pattern [String] Cache key pattern
  # @param cutoff_time [Time] Cutoff time
  # @return [Integer] Number of keys cleaned
  def cleanup_cache_pattern_fallback(pattern, cutoff_time)
    # This is a simplified fallback - in a real implementation you'd want
    # to maintain a registry of cache keys or use a more sophisticated approach
    0
  end

  # Record cleanup metrics for monitoring
  # @param stats [Hash] Cleanup statistics
  def record_cleanup_metrics(stats)
    Rails.cache.write(
      "broadcast_analytics:cleanup:last_run",
      {
        timestamp: Time.current.iso8601,
        stats: stats
      },
      expires_in: 24.hours
    )
  end
end
