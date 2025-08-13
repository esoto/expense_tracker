# frozen_string_literal: true

# Helper methods for testing categorization engine with proper isolation
module CategorizationTestHelper
  def reset_categorization_engine!(force_gc: false)
    # Clean up any test engines that might be running
    # No longer using singleton pattern

    # Reset PatternCache if it has singleton behavior
    if defined?(Categorization::PatternCache)
      begin
        if Categorization::PatternCache.respond_to?(:reset_singleton!)
          Categorization::PatternCache.reset_singleton!
        elsif Categorization::PatternCache.instance_variable_defined?(:@instance)
          Categorization::PatternCache.instance_variable_set(:@instance, nil)
        end
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

  # Create a fresh engine instance with clean dependencies
  def create_test_engine(options = {})
    service_registry = Categorization::ServiceRegistry.new(logger: Rails.logger)

    # Create fresh instances of all services
    pattern_cache = Categorization::PatternCache.new
    service_registry.register(:pattern_cache, pattern_cache)
    service_registry.register(:fuzzy_matcher, Categorization::Matchers::FuzzyMatcher.new)
    service_registry.register(:confidence_calculator, Categorization::ConfidenceCalculator.new)
    service_registry.register(:pattern_learner, Categorization::PatternLearner.new(pattern_cache: pattern_cache))
    service_registry.register(:performance_tracker, Categorization::PerformanceTracker.new)
    service_registry.register(:lru_cache, Categorization::LruCache.new(
      max_size: Categorization::Engine::MAX_PATTERN_CACHE_SIZE,
      ttl_seconds: 300
    ))

    # Create engine with fresh dependencies
    Categorization::Engine.new(
      service_registry: service_registry,
      skip_defaults: true,
      **options
    )
  end

  def with_clean_engine(&block)
    reset_categorization_engine!
    engine = create_test_engine
    yield(engine)
  ensure
    engine&.shutdown!
    reset_categorization_engine!
  end

  def debug_cache_state(engine = nil)
    return {} unless engine

    {
      engine_initialized: engine.present?,
      total_categorizations: engine.metrics.dig(:engine, :total_categorizations),
      successful_categorizations: engine.metrics.dig(:engine, :successful_categorizations),
      cache_size: engine.metrics.dig(:cache, :lru_cache, :size) || 0,
      thread_pool_active: engine.metrics.dig(:engine, :thread_pool_status) || "unknown",
      shutdown: engine.shutdown?
    }
  rescue StandardError => e
    { error: e.message }
  end

  def wait_for_async_operations(engine = nil, timeout: 2.seconds)
    return unless engine

    # Give any async operations time to complete
    start_time = Time.current

    loop do
      break if Time.current - start_time > timeout

      # Check if there are pending operations
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
    # Ensure proper cleanup after each test
    if defined?(@test_engine) && @test_engine
      @test_engine.shutdown!
      @test_engine = nil
    end

    # Clean up default instance
    reset_categorization_engine!
  end
end
