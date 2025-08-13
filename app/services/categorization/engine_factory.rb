# frozen_string_literal: true

require "ostruct"

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

        # Use the proper Engine class with dependency injection
        engine = Engine.create(config)

        engines[name] = engine
        engine
      end
    end
  end

end
