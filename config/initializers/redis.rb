# Redis configuration for categorization pattern caching (L2 tier)
# Note: This initializer is safe to load even if Redis is not available.
# Redis is used by PatternCache as the L2 cache layer — it does NOT override Rails.cache.
# Rails.cache is configured in config/environments/*.rb (Solid Cache in production).

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

      Rails.logger.info "✅ Redis connected successfully (used for PatternCache L2, not Rails.cache)"

    rescue => e
      if defined?(Rails.logger)
        Rails.logger.warn "⚠️  Redis connection failed: #{e.message}"
        Rails.logger.warn "   Categorization caching will use memory-only cache (L1 only)"
      end
    end
  end
end
