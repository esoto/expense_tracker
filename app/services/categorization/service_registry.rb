# frozen_string_literal: true

module Services::Categorization
  # Service registry for managing dependencies in categorization engine
  # Provides dependency injection container for all categorization services
  class ServiceRegistry
    attr_reader :services, :logger

    def initialize(logger: Rails.logger)
      @logger = logger
      @services = {}
      @mutex = Mutex.new
    end

    # Register a service with a key
    def register(key, service)
      @mutex.synchronize do
        @services[key] = service
        @logger.debug "[ServiceRegistry] Registered service: #{key}"
      end
    end

    # Get a service by key
    def get(key)
      @mutex.synchronize do
        @services[key]
      end
    end

    # Get or create a service with a factory block
    def fetch(key, &block)
      @mutex.synchronize do
        @services[key] ||= yield if block_given?
      end
    end

    # Check if a service is registered
    def registered?(key)
      @mutex.synchronize do
        @services.key?(key)
      end
    end

    # Clear all services
    def clear!
      @mutex.synchronize do
        @logger.debug "[ServiceRegistry] Clearing all services"
        @services.clear
      end
    end

    # Build default services for categorization engine
    def build_defaults(options = {})
      @mutex.synchronize do
        # Uses singleton so model after_commit callbacks (which call PatternCache.instance.invalidate)
        # reach the same object the Engine reads from. DI override via options[:pattern_cache] still
        # takes precedence for test isolation.
        #
        # Future alternative (Option B): If independent cache instances are needed (e.g., per-tenant
        # isolation with different TTLs), replace this with PatternCache.new and implement version-key
        # broadcast invalidation. All PatternCache instances already embed PATTERN_VERSION_KEY in their
        # cache keys via CacheVersioning concern. The change would require: (1) ensure
        # increment_pattern_cache_version is called in model callbacks instead of instance.invalidate,
        # (2) add a version-check on every L1 read to detect stale entries, (3) accept a TTL-bounded
        # stale window on L1 (currently 15 minutes). See PER-327 epic for context.
        @services[:pattern_cache] ||= options[:pattern_cache] || PatternCache.instance
        @services[:fuzzy_matcher] ||= options[:fuzzy_matcher] || Matchers::FuzzyMatcher.new
        @services[:confidence_calculator] ||= options[:confidence_calculator] || ConfidenceCalculator.new
        @services[:pattern_learner] ||= options[:pattern_learner] || PatternLearner.new(pattern_cache: @services[:pattern_cache])
        @services[:performance_tracker] ||= options[:performance_tracker] || PerformanceTracker.instance
        @services[:lru_cache] ||= options[:lru_cache] || LruCache.new(
          max_size: Engine::MAX_PATTERN_CACHE_SIZE,
          ttl_seconds: 300
        )
      end
      self
    end

    # Get all service keys
    def keys
      @mutex.synchronize do
        @services.keys
      end
    end

    # Create a new registry with the same services (for testing)
    def dup
      new_registry = self.class.new(logger: @logger)
      @mutex.synchronize do
        @services.each do |key, service|
          new_registry.register(key, service)
        end
      end
      new_registry
    end
  end
end
