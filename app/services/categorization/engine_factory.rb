# frozen_string_literal: true

module Categorization
  # Factory for creating and managing categorization engine instances
  # Replaces singleton pattern with configurable instances for better testing
  class EngineFactory
    class << self
      # Get a shared instance (default behavior)
      def default
        @default ||= create_engine(:default)
      end

      # Create a new engine instance with custom configuration
      def create(name = nil, config = {})
        name ||= SecureRandom.uuid
        create_engine(name, config)
      end

      # Get or create a named engine instance
      def get(name)
        engines[name] || create_engine(name)
      end

      # Clear all cached engines (useful for testing)
      def reset!
        @engines = nil
        @default = nil
      end

      # Get all active engines
      def active_engines
        engines.values
      end

      # Configure default engine settings
      def configure
        yield(configuration) if block_given?
      end

      def configuration
        @configuration ||= OpenStruct.new(
          cache_size: 1000,
          cache_ttl: 300,
          batch_size: 100,
          enable_circuit_breaker: true,
          circuit_breaker_threshold: 5,
          circuit_breaker_timeout: 60,
          enable_metrics: true,
          enable_learning: true,
          confidence_threshold: 0.7
        )
      end

      private

      def engines
        @engines ||= Concurrent::Map.new
      end

      def create_engine(name, custom_config = {})
        config = configuration.to_h.merge(custom_config)

        engine = Engine.new(
          cache_size: config[:cache_size],
          cache_ttl: config[:cache_ttl],
          batch_size: config[:batch_size],
          enable_circuit_breaker: config[:enable_circuit_breaker],
          circuit_breaker_threshold: config[:circuit_breaker_threshold],
          circuit_breaker_timeout: config[:circuit_breaker_timeout],
          enable_metrics: config[:enable_metrics],
          enable_learning: config[:enable_learning],
          confidence_threshold: config[:confidence_threshold]
        )

        engines[name] = engine
        engine
      end
    end
  end

  # Update Engine class to remove singleton pattern
  class Engine
    attr_reader :config, :metrics, :cache

    def initialize(options = {})
      @config = options
      @mutex = Mutex.new
      @logger = options[:logger] || Rails.logger

      initialize_components(options)
      initialize_metrics if options[:enable_metrics]

      @logger.info "[Categorization::Engine] Initialized with config: #{options.inspect}"
    end

    # Remove singleton-related code
    # Remove class methods that delegate to instance

    private

    def initialize_components(options)
      # Initialize cache
      @cache = LRUCache.new(
        max_size: options[:cache_size] || 1000,
        ttl: options[:cache_ttl] || 300
      )

      # Initialize services (no longer using singleton)
      @pattern_cache_service = options[:pattern_cache] || PatternCache.new
      @fuzzy_matcher = options[:fuzzy_matcher] || Matchers::FuzzyMatcher.new
      @confidence_calculator = options[:confidence_calculator] || ConfidenceCalculator.new
      @pattern_learner = options[:pattern_learner] || PatternLearner.new

      # Initialize circuit breakers if enabled
      if options[:enable_circuit_breaker]
        initialize_circuit_breakers(options)
      end
    end

    def initialize_circuit_breakers(options)
      threshold = options[:circuit_breaker_threshold] || 5
      timeout = options[:circuit_breaker_timeout] || 60

      @circuit_breakers = {
        database: SimpleCircuitBreaker.new(
          name: "database",
          threshold: threshold,
          timeout: timeout,
          logger: @logger
        ),
        cache: SimpleCircuitBreaker.new(
          name: "cache",
          threshold: threshold,
          timeout: timeout,
          logger: @logger
        )
      }
    end

    def initialize_metrics
      @metrics = Concurrent::Hash.new do |hash, key|
        hash[key] = Concurrent::AtomicFixnum.new(0)
      end

      @timing_metrics = Concurrent::Hash.new do |hash, key|
        hash[key] = []
      end
    end
  end
end
