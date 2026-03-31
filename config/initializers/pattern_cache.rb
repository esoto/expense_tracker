# frozen_string_literal: true

# Pattern Cache Configuration and Initialization
# This initializer configures the categorization pattern cache and optionally warms it on startup

Rails.application.configure do
  # Configure TTL values for pattern cache
  config.pattern_cache_memory_ttl = ENV.fetch("PATTERN_CACHE_MEMORY_TTL", 15).to_i.minutes
  config.pattern_cache_l2_ttl = ENV.fetch("PATTERN_CACHE_L2_TTL", 1).to_i.hours
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
          Services::Categorization::PatternCache.instance.warm_cache
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
    if defined?(Services::Categorization::PatternCache)
      cache_config = {
        memory_ttl: Rails.application.config.pattern_cache_memory_ttl,
        l2_ttl: Rails.application.config.pattern_cache_l2_ttl
      }

      Rails.logger.info "[PatternCache] Configuration: #{cache_config.inspect}"
    end
  end
end
