# Redis configuration for categorization pattern caching
# Note: This initializer is safe to load even if Redis is not available

# Skip Redis configuration in test environment to allow proper test isolation
unless Rails.env.test?
  if defined?(Redis)
    redis_config = {
      host: ENV.fetch("REDIS_HOST", "localhost"),
      port: ENV.fetch("REDIS_PORT", 6379),
      db: ENV.fetch("REDIS_DB", 0),
      password: ENV.fetch("REDIS_PASSWORD", nil),
      timeout: 1
    }

    # Test connection on startup (with graceful fallback)
    begin
      test_redis = Redis.new(redis_config)
      test_redis.ping
      test_redis.disconnect!

      Rails.logger.info "✅ Redis connected successfully" if defined?(Rails.logger)

      # Configure Rails cache store to use Redis
      Rails.application.configure do
        config.cache_store = :redis_cache_store, redis_config.merge(
          namespace: "categorization",
          expires_in: 24.hours
        )
      end

    rescue => e
      if defined?(Rails.logger)
        Rails.logger.warn "⚠️  Redis connection failed: #{e.message}"
        Rails.logger.warn "   Categorization caching will use memory-only cache"
      end

      # Fallback to memory cache
      Rails.application.configure do
        config.cache_store = :memory_store, { size: 32.megabytes }
      end
    end
  else
    # Redis gem not available, use memory cache
    Rails.application.configure do
      config.cache_store = :memory_store, { size: 32.megabytes }
    end
  end
end
