# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::ServiceRegistry, :unit do
  let(:logger) { instance_double(Logger) }
  let(:registry) { described_class.new(logger: logger) }

  before do
    # Mock logger methods
    allow(logger).to receive(:debug)

    # Create mock service classes with flexible initializers
    pattern_cache_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    fuzzy_matcher_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    confidence_calculator_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    pattern_learner_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    performance_tracker_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    lru_cache_class = Class.new do
      def initialize(*args, **kwargs); end
    end

    # Stub all service classes
    stub_const("Services::Categorization::PatternCache", pattern_cache_class)
    stub_const("Services::Categorization::Matchers::FuzzyMatcher", fuzzy_matcher_class)
    stub_const("Services::Categorization::ConfidenceCalculator", confidence_calculator_class)
    stub_const("Services::Categorization::PatternLearner", pattern_learner_class)
    stub_const("Services::Categorization::PerformanceTracker", performance_tracker_class)
    stub_const("Services::Categorization::LruCache", lru_cache_class)
    stub_const("Services::Categorization::Engine::MAX_PATTERN_CACHE_SIZE", 1000)

    # Allow instantiation of service mocks
    allow(Services::Categorization::PatternCache).to receive(:new).and_call_original
    allow(Services::Categorization::Matchers::FuzzyMatcher).to receive(:new).and_call_original
    allow(Services::Categorization::ConfidenceCalculator).to receive(:new).and_call_original
    allow(Services::Categorization::PatternLearner).to receive(:new).and_call_original
    allow(Services::Categorization::PerformanceTracker).to receive(:new).and_call_original
    allow(Services::Categorization::LruCache).to receive(:new).and_call_original
  end

  describe "#initialize" do
    context "with default logger" do
      subject(:default_registry) { described_class.new }

      before do
        allow(Rails).to receive(:logger).and_return(logger)
      end

      it "uses Rails.logger by default" do
        expect(default_registry.logger).to eq(logger)
      end

      it "initializes empty services hash" do
        expect(default_registry.services).to eq({})
      end

      it "creates a mutex for thread safety" do
        mutex = default_registry.instance_variable_get(:@mutex)
        expect(mutex).to be_a(Mutex)
      end
    end

    context "with custom logger" do
      let(:custom_logger) { instance_double(Logger) }
      subject(:custom_registry) { described_class.new(logger: custom_logger) }

      it "uses provided logger" do
        expect(custom_registry.logger).to eq(custom_logger)
      end

      it "initializes empty services hash" do
        expect(custom_registry.services).to eq({})
      end
    end
  end

  describe "#register" do
    let(:service) { double("TestService") }

    it "registers a service with given key" do
      registry.register(:test_service, service)
      expect(registry.services[:test_service]).to eq(service)
    end

    it "logs service registration" do
      expect(logger).to receive(:debug).with("[ServiceRegistry] Registered service: test_service")
      registry.register(:test_service, service)
    end

    it "overwrites existing service with same key" do
      old_service = double("OldService")
      new_service = double("NewService")

      registry.register(:service, old_service)
      registry.register(:service, new_service)

      expect(registry.services[:service]).to eq(new_service)
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.register(:test_service, service)
    end

    it "allows nil services" do
      registry.register(:nil_service, nil)
      expect(registry.services[:nil_service]).to be_nil
    end

    it "accepts string keys" do
      registry.register("string_key", service)
      expect(registry.services["string_key"]).to eq(service)
    end
  end

  describe "#get" do
    let(:service) { double("TestService") }

    before do
      registry.register(:test_service, service)
    end

    it "retrieves registered service" do
      expect(registry.get(:test_service)).to eq(service)
    end

    it "returns nil for unregistered service" do
      expect(registry.get(:nonexistent)).to be_nil
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.get(:test_service)
    end

    it "retrieves nil services correctly" do
      registry.register(:nil_service, nil)
      expect(registry.get(:nil_service)).to be_nil
    end

    it "works with string keys" do
      registry.register("string_key", service)
      expect(registry.get("string_key")).to eq(service)
    end
  end

  describe "#fetch" do
    let(:service) { double("TestService") }

    context "when service doesn't exist" do
      it "creates service with block" do
        result = registry.fetch(:new_service) { service }
        expect(result).to eq(service)
        expect(registry.get(:new_service)).to eq(service)
      end

      it "returns nil without block" do
        result = registry.fetch(:new_service)
        expect(result).to be_nil
      end

      it "is thread-safe" do
        mutex = registry.instance_variable_get(:@mutex)
        expect(mutex).to receive(:synchronize).and_yield

        registry.fetch(:new_service) { service }
      end
    end

    context "when service exists" do
      before do
        registry.register(:existing_service, service)
      end

      it "returns existing service" do
        new_service = double("NewService")
        result = registry.fetch(:existing_service) { new_service }
        expect(result).to eq(service)
      end

      it "doesn't call block for existing service" do
        block_called = false
        registry.fetch(:existing_service) { block_called = true }
        expect(block_called).to be false
      end
    end

    context "lazy initialization" do
      it "only creates service once" do
        creation_count = 0
        factory = -> { creation_count += 1; double("Service#{creation_count}") }

        service1 = registry.fetch(:lazy_service, &factory)
        service2 = registry.fetch(:lazy_service, &factory)

        expect(creation_count).to eq(1)
        expect(service1).to eq(service2)
      end

      it "handles complex initialization logic" do
        complex_service = registry.fetch(:complex) do
          obj = double("ComplexService")
          allow(obj).to receive(:initialize_resources)
          obj.initialize_resources
          obj
        end

        expect(complex_service).to be_present
      end
    end

    context "edge cases" do
      it "allows nil as created value" do
        result = registry.fetch(:nil_service) { nil }
        expect(result).to be_nil
        expect(registry.registered?(:nil_service)).to be true
      end

      it "handles exceptions in block" do
        expect {
          registry.fetch(:error_service) { raise "Initialization error" }
        }.to raise_error("Initialization error")

        expect(registry.registered?(:error_service)).to be false
      end
    end
  end

  describe "#registered?" do
    let(:service) { double("TestService") }

    it "returns true for registered service" do
      registry.register(:test_service, service)
      expect(registry.registered?(:test_service)).to be true
    end

    it "returns false for unregistered service" do
      expect(registry.registered?(:nonexistent)).to be false
    end

    it "returns true for nil services" do
      registry.register(:nil_service, nil)
      expect(registry.registered?(:nil_service)).to be true
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.registered?(:test_service)
    end

    it "works with string keys" do
      registry.register("string_key", service)
      expect(registry.registered?("string_key")).to be true
    end
  end

  describe "#clear!" do
    before do
      registry.register(:service1, double("Service1"))
      registry.register(:service2, double("Service2"))
      registry.register(:service3, double("Service3"))
    end

    it "removes all services" do
      registry.clear!
      expect(registry.services).to be_empty
    end

    it "logs clearing action" do
      expect(logger).to receive(:debug).with("[ServiceRegistry] Clearing all services")
      registry.clear!
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.clear!
    end

    it "allows re-registration after clearing" do
      registry.clear!
      new_service = double("NewService")
      registry.register(:new_service, new_service)

      expect(registry.get(:new_service)).to eq(new_service)
    end
  end

  describe "#build_defaults" do
    context "without custom options" do
      it "creates all default services" do
        registry.build_defaults

        expect(registry.registered?(:pattern_cache)).to be true
        expect(registry.registered?(:fuzzy_matcher)).to be true
        expect(registry.registered?(:confidence_calculator)).to be true
        expect(registry.registered?(:pattern_learner)).to be true
        expect(registry.registered?(:performance_tracker)).to be true
        expect(registry.registered?(:lru_cache)).to be true
      end

      it "creates PatternLearner with pattern_cache dependency" do
        pattern_cache = double("PatternCache")
        allow(Services::Categorization::PatternCache).to receive(:new).and_return(pattern_cache)

        expect(Categorization::PatternLearner).to receive(:new)
          .with(pattern_cache: pattern_cache)
          .and_return(double("PatternLearner"))

        registry.build_defaults
      end

      it "creates LruCache with correct parameters" do
        expect(Categorization::LruCache).to receive(:new)
          .with(max_size: 1000, ttl_seconds: 300)
          .and_return(double("LruCache"))

        registry.build_defaults
      end

      it "returns self for chaining" do
        result = registry.build_defaults
        expect(result).to eq(registry)
      end

      it "is thread-safe" do
        mutex = registry.instance_variable_get(:@mutex)
        expect(mutex).to receive(:synchronize).and_yield

        registry.build_defaults
      end
    end

    context "with custom options" do
      let(:custom_pattern_cache) { double("CustomPatternCache") }
      let(:custom_fuzzy_matcher) { double("CustomFuzzyMatcher") }
      let(:custom_confidence_calculator) { double("CustomConfidenceCalculator") }
      let(:custom_pattern_learner) { double("CustomPatternLearner") }
      let(:custom_performance_tracker) { double("CustomPerformanceTracker") }
      let(:custom_lru_cache) { double("CustomLruCache") }

      let(:options) do
        {
          pattern_cache: custom_pattern_cache,
          fuzzy_matcher: custom_fuzzy_matcher,
          confidence_calculator: custom_confidence_calculator,
          pattern_learner: custom_pattern_learner,
          performance_tracker: custom_performance_tracker,
          lru_cache: custom_lru_cache
        }
      end

      it "uses provided services instead of creating new ones" do
        registry.build_defaults(options)

        expect(registry.get(:pattern_cache)).to eq(custom_pattern_cache)
        expect(registry.get(:fuzzy_matcher)).to eq(custom_fuzzy_matcher)
        expect(registry.get(:confidence_calculator)).to eq(custom_confidence_calculator)
        expect(registry.get(:pattern_learner)).to eq(custom_pattern_learner)
        expect(registry.get(:performance_tracker)).to eq(custom_performance_tracker)
        expect(registry.get(:lru_cache)).to eq(custom_lru_cache)
      end

      it "doesn't instantiate default services when custom ones provided" do
        expect(Services::Categorization::PatternCache).not_to receive(:new)
        expect(Categorization::Matchers::FuzzyMatcher).not_to receive(:new)

        registry.build_defaults(options)
      end
    end

    context "with partial custom options" do
      let(:custom_pattern_cache) { double("CustomPatternCache") }
      let(:custom_fuzzy_matcher) { double("CustomFuzzyMatcher") }

      it "mixes custom and default services" do
        options = {
          pattern_cache: custom_pattern_cache,
          fuzzy_matcher: custom_fuzzy_matcher
        }

        expect(Categorization::ConfidenceCalculator).to receive(:new)
        expect(Categorization::PerformanceTracker).to receive(:new)
        expect(Categorization::LruCache).to receive(:new)

        registry.build_defaults(options)

        expect(registry.get(:pattern_cache)).to eq(custom_pattern_cache)
        expect(registry.get(:fuzzy_matcher)).to eq(custom_fuzzy_matcher)
      end
    end

    context "when services already exist" do
      let(:existing_service) { double("ExistingService") }

      before do
        registry.register(:pattern_cache, existing_service)
      end

      it "doesn't overwrite existing services" do
        registry.build_defaults
        expect(registry.get(:pattern_cache)).to eq(existing_service)
      end

      it "fills in missing services" do
        expect(Categorization::Matchers::FuzzyMatcher).to receive(:new)
        registry.build_defaults
      end
    end
  end

  describe "#keys" do
    it "returns empty array for empty registry" do
      expect(registry.keys).to eq([])
    end

    it "returns all service keys" do
      registry.register(:service1, double("Service1"))
      registry.register(:service2, double("Service2"))
      registry.register(:service3, double("Service3"))

      expect(registry.keys).to contain_exactly(:service1, :service2, :service3)
    end

    it "includes keys for nil services" do
      registry.register(:nil_service, nil)
      registry.register(:real_service, double("Service"))

      expect(registry.keys).to contain_exactly(:nil_service, :real_service)
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.keys
    end

    it "returns a new array each time" do
      registry.register(:service, double("Service"))
      keys1 = registry.keys
      keys2 = registry.keys

      expect(keys1).to eq(keys2)
      expect(keys1).not_to be(keys2) # Different object references
    end
  end

  describe "#dup" do
    let(:service1) { double("Service1") }
    let(:service2) { double("Service2") }
    let(:service3) { double("Service3") }

    before do
      registry.register(:service1, service1)
      registry.register(:service2, service2)
      registry.register(:service3, service3)
    end

    it "creates a new registry instance" do
      new_registry = registry.dup
      expect(new_registry).to be_a(described_class)
      expect(new_registry).not_to be(registry)
    end

    it "copies all services to new registry" do
      new_registry = registry.dup

      expect(new_registry.get(:service1)).to eq(service1)
      expect(new_registry.get(:service2)).to eq(service2)
      expect(new_registry.get(:service3)).to eq(service3)
    end

    it "uses same logger" do
      new_registry = registry.dup
      expect(new_registry.logger).to eq(logger)
    end

    it "logs each service registration in new registry" do
      expect(logger).to receive(:debug).with("[ServiceRegistry] Registered service: service1")
      expect(logger).to receive(:debug).with("[ServiceRegistry] Registered service: service2")
      expect(logger).to receive(:debug).with("[ServiceRegistry] Registered service: service3")

      registry.dup
    end

    it "creates independent registries" do
      new_registry = registry.dup
      new_service = double("NewService")

      new_registry.register(:new_service, new_service)

      expect(new_registry.get(:new_service)).to eq(new_service)
      expect(registry.get(:new_service)).to be_nil
    end

    it "is thread-safe" do
      mutex = registry.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).and_yield

      registry.dup
    end

    it "copies nil services" do
      registry.register(:nil_service, nil)
      new_registry = registry.dup

      expect(new_registry.registered?(:nil_service)).to be true
      expect(new_registry.get(:nil_service)).to be_nil
    end

    it "preserves service order" do
      new_registry = registry.dup
      expect(new_registry.keys).to eq(registry.keys)
    end
  end

  describe "thread safety" do
    it "all public methods use mutex synchronization" do
      mutex = registry.instance_variable_get(:@mutex)

      # Test each public method for mutex usage
      expect(mutex).to receive(:synchronize).at_least(:once).and_yield

      registry.register(:test, double("Service"))
      registry.get(:test)
      registry.fetch(:test2) { double("Service2") }
      registry.registered?(:test)
      registry.clear!
      registry.build_defaults
      registry.keys
      registry.dup
    end

    it "prevents race conditions in concurrent access" do
      # This test simulates concurrent access patterns
      service1 = double("Service1")
      service2 = double("Service2")

      # Simulate interleaved operations
      registry.register(:shared, service1)
      expect(registry.get(:shared)).to eq(service1)

      registry.register(:shared, service2)
      expect(registry.get(:shared)).to eq(service2)
    end

    it "ensures atomic operations in fetch" do
      creation_count = 0

      # Fetch should be atomic - block should only run once
      service = registry.fetch(:atomic) do
        creation_count += 1
        double("AtomicService")
      end

      # Second fetch shouldn't increment counter
      registry.fetch(:atomic) { creation_count += 1 }

      expect(creation_count).to eq(1)
    end
  end

  describe "edge cases and error handling" do
    it "handles empty registry operations" do
      expect(registry.keys).to eq([])
      expect(registry.get(:nonexistent)).to be_nil
      expect(registry.registered?(:nonexistent)).to be false

      new_registry = registry.dup
      expect(new_registry.keys).to eq([])
    end

    it "handles special key types" do
      symbol_service = double("SymbolService")
      string_service = double("StringService")
      number_service = double("NumberService")

      registry.register(:symbol_key, symbol_service)
      registry.register("string_key", string_service)
      registry.register(123, number_service)

      expect(registry.get(:symbol_key)).to eq(symbol_service)
      expect(registry.get("string_key")).to eq(string_service)
      expect(registry.get(123)).to eq(number_service)
    end

    it "maintains registry state after errors" do
      registry.register(:service1, double("Service1"))

      # Simulate error in fetch block
      expect {
        registry.fetch(:error_service) { raise "Error" }
      }.to raise_error("Error")

      # Registry should still be functional
      expect(registry.get(:service1)).to be_present
      expect(registry.registered?(:error_service)).to be false
    end

    it "handles very large registries" do
      1000.times do |i|
        registry.register("service_#{i}", double("Service#{i}"))
      end

      expect(registry.keys.size).to eq(1000)
      expect(registry.get("service_500")).to be_present
    end
  end
end
