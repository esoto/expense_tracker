# frozen_string_literal: true

# Pattern Cache Configuration and Initialization
# This initializer configures the categorization pattern cache and optionally warms it on startup

Rails.application.configure do
  # Configure TTL values for pattern cache
  config.pattern_cache_memory_ttl = ENV.fetch("PATTERN_CACHE_MEMORY_TTL", 5).to_i.minutes
  config.pattern_cache_redis_ttl = ENV.fetch("PATTERN_CACHE_REDIS_TTL", 24).to_i.hours
end

# Warm cache on startup in production and staging
if Rails.env.production? || Rails.env.staging?
  Rails.application.config.after_initialize do
    # Run cache warming in a background thread to avoid blocking startup
    Thread.new do
      begin
        Rails.logger.info "[PatternCache] Scheduling cache warming..."
        sleep 5 # Wait for application to fully initialize

        ActiveRecord::Base.connection_pool.with_connection do
          Categorization::PatternCache.instance.warm_cache
        end
      rescue => e
        Rails.logger.error "[PatternCache] Cache warming failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end

# Optional: Log cache configuration (skip in test to avoid issues)
unless Rails.env.test?
  Rails.application.config.after_initialize do
    if defined?(Categorization::PatternCache)
      cache_config = {
        memory_ttl: Rails.application.config.pattern_cache_memory_ttl,
        redis_ttl: Rails.application.config.pattern_cache_redis_ttl,
        redis_available: Categorization::PatternCache.instance.instance_variable_get(:@redis_available)
      }

      Rails.logger.info "[PatternCache] Configuration: #{cache_config.inspect}"
    end
  end
end
