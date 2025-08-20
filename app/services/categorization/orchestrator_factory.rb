# frozen_string_literal: true

require "ostruct"

module Categorization
  # Factory for creating orchestrator instances with proper dependency injection
  # Provides different configurations for various environments and use cases
  # Thread-safe singleton pattern for shared service instances
  #
  # Usage:
  #   # Default production configuration
  #   orchestrator = OrchestratorFactory.create_production
  #
  #   # Test configuration with mocked services
  #   orchestrator = OrchestratorFactory.create_test
  #
  #   # Custom configuration
  #   orchestrator = OrchestratorFactory.create_custom(
  #     pattern_cache: MyCustomCache.new,
  #     matcher: MyCustomMatcher.new
  #   )
  class OrchestratorFactory
    class << self
      # Thread-safe service registry
      def service_registry
        @service_registry ||= {}
      end

      # Create production-ready orchestrator with all optimizations
      def create_production(options = {})
        registry = build_production_registry(options)

        Orchestrator.new(
          pattern_cache: registry[:pattern_cache],
          matcher: registry[:matcher],
          confidence_calculator: registry[:confidence_calculator],
          pattern_learner: registry[:pattern_learner],
          performance_tracker: registry[:performance_tracker],
          circuit_breaker: registry[:circuit_breaker],
          logger: options[:logger] || Rails.logger
        )
      end

      # Create test orchestrator with simplified services
      def create_test(options = {})
        registry = build_test_registry(options)

        Orchestrator.new(
          pattern_cache: registry[:pattern_cache],
          matcher: registry[:matcher],
          confidence_calculator: registry[:confidence_calculator],
          pattern_learner: registry[:pattern_learner],
          performance_tracker: registry[:performance_tracker],
          logger: options[:logger] || Rails.logger
        )
      end

      # Create development orchestrator with debugging features
      def create_development(options = {})
        registry = build_development_registry(options)

        Orchestrator.new(
          pattern_cache: registry[:pattern_cache],
          matcher: registry[:matcher],
          confidence_calculator: registry[:confidence_calculator],
          pattern_learner: registry[:pattern_learner],
          performance_tracker: registry[:performance_tracker],
          logger: options[:logger] || Rails.logger
        )
      end

      # Create custom orchestrator with provided services
      def create_custom(services = {})
        registry = build_custom_registry(services)

        Orchestrator.new(
          pattern_cache: registry[:pattern_cache],
          matcher: registry[:matcher],
          confidence_calculator: registry[:confidence_calculator],
          pattern_learner: registry[:pattern_learner],
          performance_tracker: registry[:performance_tracker],
          circuit_breaker: services[:circuit_breaker],
          logger: services[:logger] || Rails.logger
        )
      end

      # Create minimal orchestrator for specific use cases
      def create_minimal(options = {})
        Orchestrator.new(
          pattern_cache: options[:pattern_cache] || InMemoryPatternCache.new,
          matcher: options[:matcher] || SimpleMatcher.new,
          confidence_calculator: options[:confidence_calculator] || SimpleConfidenceCalculator.new,
          pattern_learner: options[:pattern_learner] || NoOpPatternLearner.new,
          performance_tracker: options[:performance_tracker] || NoOpPerformanceTracker.new,
          logger: options[:logger] || Rails.logger
        )
      end

      private

      def build_production_registry(options)
        @registry_mutex ||= Mutex.new

        @registry_mutex.synchronize do
          {
            pattern_cache: options[:pattern_cache] || get_or_create_service(:pattern_cache) { build_production_pattern_cache },
            matcher: options[:matcher] || get_or_create_service(:matcher) { build_production_matcher },
            confidence_calculator: options[:confidence_calculator] || get_or_create_service(:confidence_calculator) { build_production_confidence_calculator },
            pattern_learner: options[:pattern_learner] || get_or_create_service(:pattern_learner) { build_production_pattern_learner },
            performance_tracker: options[:performance_tracker] || get_or_create_service(:performance_tracker) { build_production_performance_tracker },
            circuit_breaker: options[:circuit_breaker] || get_or_create_service(:circuit_breaker) { build_production_circuit_breaker }
          }
        end
      end

      def get_or_create_service(key, &block)
        service_registry[key] ||= yield
      end

      def build_test_registry(options)
        {
          pattern_cache: options[:pattern_cache] || InMemoryPatternCache.new,
          matcher: options[:matcher] || SimpleMatcher.new,
          confidence_calculator: options[:confidence_calculator] || SimpleConfidenceCalculator.new,
          pattern_learner: options[:pattern_learner] || TestPatternLearner.new,
          performance_tracker: options[:performance_tracker] || NoOpPerformanceTracker.new,
          circuit_breaker: options[:circuit_breaker] || TestCircuitBreaker.new
        }
      end

      def build_development_registry(options)
        {
          pattern_cache: options[:pattern_cache] || build_development_pattern_cache,
          matcher: options[:matcher] || build_development_matcher,
          confidence_calculator: options[:confidence_calculator] || build_development_confidence_calculator,
          pattern_learner: options[:pattern_learner] || build_development_pattern_learner,
          performance_tracker: options[:performance_tracker] || build_development_performance_tracker,
          circuit_breaker: options[:circuit_breaker] || build_development_circuit_breaker
        }
      end

      def build_custom_registry(services)
        {
          pattern_cache: services[:pattern_cache] || PatternCache.new,
          matcher: services[:matcher] || Matchers::FuzzyMatcher.new,
          confidence_calculator: services[:confidence_calculator] || ConfidenceCalculator.new,
          pattern_learner: services[:pattern_learner] || PatternLearner.new,
          performance_tracker: services[:performance_tracker] || PerformanceTracker.new,
          circuit_breaker: services[:circuit_breaker] || Orchestrator::CircuitBreaker.new
        }
      end

      # Production service builders

      def build_production_pattern_cache
        PatternCache.new(
          memory_cache_size: 100.megabytes,
          redis_enabled: true,
          ttl: 1.hour
        )
      end

      def build_production_matcher
        Matchers::FuzzyMatcher.new(
          min_similarity: 0.7,
          max_results: 10,
          use_caching: true
        )
      end

      def build_production_confidence_calculator
        ConfidenceCalculator.new(
          use_ml_scoring: true,
          cache_results: true
        )
      end

      def build_production_pattern_learner
        PatternLearner.new(
          min_confidence_to_learn: 0.8,
          batch_size: 100
        )
      end

      def build_production_performance_tracker
        PerformanceTracker.new(
          logger: Rails.logger
        )
      end

      def build_production_circuit_breaker
        Orchestrator::CircuitBreaker.new(
          failure_threshold: 5,
          timeout: 30.seconds
        )
      end

      # Test service builders

      def build_test_pattern_cache
        InMemoryPatternCache.new(max_size: 100)
      end

      def build_test_matcher
        SimpleMatcher.new
      end

      def build_test_confidence_calculator
        SimpleConfidenceCalculator.new
      end

      def build_test_pattern_learner
        TestPatternLearner.new
      end

      # Development service builders

      def build_development_pattern_cache
        PatternCache.new(
          memory_cache_size: 10.megabytes,
          redis_enabled: false,
          ttl: 5.minutes,
          debug_mode: true
        )
      end

      def build_development_matcher
        Matchers::FuzzyMatcher.new(
          min_similarity: 0.6,
          max_results: 20,
          debug_mode: true
        )
      end

      def build_development_confidence_calculator
        ConfidenceCalculator.new(
          use_ml_scoring: false,
          debug_mode: true
        )
      end

      def build_development_pattern_learner
        PatternLearner.new(
          min_confidence_to_learn: 0.6,
          debug_mode: true
        )
      end

      def build_development_performance_tracker
        # PerformanceTracker only accepts logger option
        PerformanceTracker.new(
          logger: Rails.logger
        )
      end

      def build_development_circuit_breaker
        Orchestrator::CircuitBreaker.new(
          failure_threshold: 10,
          timeout: 10.seconds
        )
      end
    end

    # Simple in-memory pattern cache for testing
    class InMemoryPatternCache
      def initialize(max_size: 100)
        @cache = {}
        @max_size = max_size
      end

      def get_pattern(pattern_id)
        @cache[pattern_id] || CategorizationPattern.find_by(id: pattern_id)
      end

      def get_patterns_for_expense(expense)
        CategorizationPattern.active.limit(10)
      end

      def get_user_preference(merchant_name)
        UserCategoryPreference.find_by(
          context_type: "merchant",
          context_value: merchant_name.downcase
        )
      end

      def preload_for_texts(texts)
        # No-op for testing
      end

      def invalidate_category(category_id)
        @cache.delete_if { |_, pattern| pattern.category_id == category_id }
      end

      def metrics
        { cache_size: @cache.size, max_size: @max_size }
      end

      def healthy?
        @cache.size < @max_size
      end

      def reset!
        @cache.clear
      end
    end

    # Simple matcher for testing
    class SimpleMatcher
      def match_pattern(text, patterns, options = {})
        matches = patterns.select do |pattern|
          text.downcase.include?(pattern.pattern_value.downcase)
        end

        Matchers::MatchResult.new(
          success: true,
          matches: matches.map { |p| { pattern: p, score: 0.8, type: "exact" } }
        )
      end

      def clear_cache
        # No-op
      end

      def metrics
        {}
      end

      def healthy?
        true
      end
    end

    # Simple confidence calculator for testing
    class SimpleConfidenceCalculator
      def calculate(expense, pattern, base_score)
        OpenStruct.new(
          score: base_score * 0.9,
          factor_breakdown: {
            text_match: { value: base_score, contribution: 0.7 },
            pattern_quality: { value: 0.8, contribution: 0.3 }
          },
          metadata: { factors_used: [ :text_match, :pattern_quality ] }
        )
      end

      def metrics
        {}
      end

      def healthy?
        true
      end
    end

    # Test pattern learner
    class TestPatternLearner
      def learn_from_correction(expense, correct_category, predicted_category, options = {})
        LearningResult.new(success: true, patterns_created: 1)
      end

      def metrics
        {}
      end

      def healthy?
        true
      end
    end

    # No-op pattern learner for minimal setup
    class NoOpPatternLearner
      def learn_from_correction(*)
        LearningResult.new(success: false, message: "Learning disabled")
      end

      def metrics
        {}
      end

      def healthy?
        true
      end
    end

    # No-op performance tracker for minimal setup
    class NoOpPerformanceTracker
      def track_operation(name)
        yield if block_given?
      end

      def record(operation, duration, metadata = {})
        # No-op
      end

      def record_failure(operation, metadata = {})
        # No-op
      end

      def reset!
        # No-op
      end

      def metrics
        {}
      end

      def healthy?
        true
      end
    end

    # Test circuit breaker that never opens
    class TestCircuitBreaker
      def call
        yield
      end

      def record_failure
        # No-op
      end

      def reset!
        # No-op
      end

      def state
        :closed
      end
    end
  end
end
