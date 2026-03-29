# frozen_string_literal: true

# Shared concern for atomic cache-version key management.
#
# Extracted from the copy-pasted atomic-increment pattern that appeared in:
#   - Services::DashboardService.clear_cache
#   - Services::MetricsCalculator.atomic_increment
#   - CategorizationPattern#invalidate_cache
#   - PatternFeedback#invalidate_analytics_cache
#   - PatternLearningEvent#invalidate_analytics_cache
#   - Services::Categorization::PatternCache#increment_pattern_cache_version
#
# The concern provides a single, thread-safe implementation that works for both
# ActiveSupport::Cache::MemoryStore (test / single-process dev) and distributed
# backends such as Redis or Memcache.
#
# MemoryStore does not expose an atomic increment operation, so we fall back to a
# Mutex-protected read-modify-write.  The mutex is stored as a frozen constant so
# that it is fully initialised at class-load time and never subject to the lazy
# `||=` race condition.
module CacheVersioning
  extend ActiveSupport::Concern

  # Module-level mutex used by every caller that operates on MemoryStore.
  # Declared as a constant so it is created exactly once, not lazily, and is
  # therefore never subject to a double-initialisation race.
  MEMORY_STORE_MUTEX = Mutex.new
  private_constant :MEMORY_STORE_MUTEX

  module ClassMethods
    # Atomically increment +key+ in Rails.cache.
    #
    # @param key [String] the version key to increment
    # @param log_tag [String] label used in error log messages (e.g. "[DashboardService]")
    # @return [Integer, nil] the new version value, or nil if an error occurs
    def atomic_cache_increment(key, log_tag: name, logger: Rails.logger)
      if Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)
        MEMORY_STORE_MUTEX.synchronize do
          current = Rails.cache.read(key) || 0
          Rails.cache.write(key, current + 1)
        end
      else
        # Redis/Memcache: #increment is atomic.  Seed the key if absent.
        Rails.cache.increment(key, 1, initial: 1) ||
          Rails.cache.write(key, 1)
      end
    rescue => e
      logger.error "#{log_tag} Failed to increment cache version key #{key}: #{e.message}"
      nil
    end
  end

  # Instance-level convenience delegating to the class method.
  #
  # @param key [String] the version key to increment
  # @param log_tag [String] label used in error log messages
  # @param logger [Logger] logger instance (defaults to Rails.logger)
  # @return [Integer, nil]
  def atomic_cache_increment(key, log_tag: self.class.name, logger: Rails.logger)
    self.class.atomic_cache_increment(key, log_tag: log_tag, logger: logger)
  end
end
