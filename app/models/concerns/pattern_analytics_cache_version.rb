# frozen_string_literal: true

# O(1) cache version key management for pattern analytics caches.
# Replaces O(n) delete_matched scans with a simple integer increment.
#
# Usage:
#   PatternAnalyticsCacheVersion.current           # => 1
#   PatternAnalyticsCacheVersion.increment!        # bumps to 2
#   Rails.cache.fetch("pattern_analytics:#{PatternAnalyticsCacheVersion.current}:key") { ... }
module PatternAnalyticsCacheVersion
  CACHE_VERSION_KEY = "pattern_analytics:cache_version"

  def self.current
    Rails.cache.fetch(CACHE_VERSION_KEY) { 1 }
  end

  def self.increment!
    new_version = current + 1
    Rails.cache.write(CACHE_VERSION_KEY, new_version)
    new_version
  end
end
