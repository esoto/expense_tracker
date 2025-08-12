# frozen_string_literal: true

# Helper methods for testing categorization engine with proper isolation
module CategorizationTestHelper
  def reset_categorization_engine!(force_gc: false)
    # Use proper singleton reset method instead of direct manipulation
    if defined?(Categorization::Engine)
      begin
        Categorization::Engine.reset_singleton!
      rescue => e
        Rails.logger.warn "[Test] Failed to reset categorization engine: #{e.message}"
      end
    end

    if defined?(Categorization::PatternCache)
      begin
        Categorization::PatternCache.instance_variable_set(:@instance, nil)
      rescue => e
        Rails.logger.warn "[Test] Failed to reset pattern cache: #{e.message}"
      end
    end

    # Clear Rails cache
    Rails.cache.clear

    # Reset Redis if available (skip connection errors in test environment)
    begin
      redis = Redis.new
      redis.flushdb if redis.connected?
    rescue Redis::CannotConnectError, Redis::ConnectionError, Redis::TimeoutError => e
      Rails.logger.debug "[Test] Redis not available for cleanup: #{e.message}"
    rescue => e
      Rails.logger.warn "[Test] Unexpected Redis error: #{e.message}"
    end

    # Optional garbage collection (can cause performance issues if overused)
    GC.start if force_gc || ENV['FORCE_GC_IN_TESTS']
  end

  def with_clean_engine(&block)
    reset_categorization_engine!
    yield
  ensure
    reset_categorization_engine!
  end

  def debug_cache_state
    return {} unless defined?(Categorization::Engine)

    engine = Categorization::Engine.instance
    {
      engine_initialized: engine.present?,
      total_categorizations: engine.metrics.dig(:engine, :total_categorizations),
      successful_categorizations: engine.metrics.dig(:engine, :successful_categorizations),
      cache_size: engine.metrics.dig(:cache, :size) || 0,
      thread_pool_active: engine.respond_to?(:thread_pool_status) ? engine.thread_pool_status : "unknown"
    }
  rescue StandardError => e
    { error: e.message }
  end

  def wait_for_async_operations(timeout: 2.seconds)
    # Give any async operations time to complete
    start_time = Time.current

    loop do
      break if Time.current - start_time > timeout

      # Check if there are pending operations
      engine = Categorization::Engine.instance
      thread_pool = engine.instance_variable_get(:@thread_pool)

      if thread_pool && thread_pool.respond_to?(:active_count)
        break if thread_pool.active_count == 0
      else
        break
      end

      sleep 0.01
    end
  end
end

RSpec.configure do |config|
  config.include CategorizationTestHelper, type: :service

  config.before(:each, type: :service) do
    reset_categorization_engine!
  end

  config.after(:each, type: :service) do
    wait_for_async_operations if respond_to?(:wait_for_async_operations)
  end
end
