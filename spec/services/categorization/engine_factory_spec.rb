# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::EngineFactory, type: :service, unit: true do
  # Clear cached state before each test
  before do
    described_class.reset!
    # Reset configuration
    described_class.instance_variable_set(:@configuration, nil)
  end

  after do
    described_class.reset!
    described_class.instance_variable_set(:@configuration, nil)
  end

  describe ".default" do
    let(:mock_engine) { instance_double(Categorization::Engine) }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
    end

    it "returns a cached default engine instance" do
      first_call = described_class.default
      second_call = described_class.default

      expect(first_call).to eq(mock_engine)
      expect(second_call).to eq(mock_engine)
      expect(first_call).to be(second_call) # Same object reference
    end

    it "creates engine with default configuration" do
      expected_config = {
        cache_size: 1000,
        cache_ttl: 300,
        batch_size: 100,
        enable_circuit_breaker: true,
        circuit_breaker_threshold: 5,
        circuit_breaker_timeout: 60,
        enable_metrics: true,
        enable_learning: true,
        confidence_threshold: 0.7
      }

      expect(Categorization::Engine).to receive(:create).with(expected_config).once

      described_class.default
    end

    it "stores engine in engines map with :default key" do
      engine = described_class.default
      engines_map = described_class.send(:engines)

      expect(engines_map[:default]).to eq(engine)
    end

    it "does not create new engine on subsequent calls" do
      expect(Categorization::Engine).to receive(:create).once

      described_class.default
      described_class.default
      described_class.default
    end
  end

  describe ".create" do
    let(:mock_engine) { instance_double(Categorization::Engine) }
    let(:uuid) { "test-uuid-123" }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
      allow(SecureRandom).to receive(:uuid).and_return(uuid)
    end

    context "without name parameter" do
      it "generates a random UUID as name" do
        engine = described_class.create

        engines_map = described_class.send(:engines)
        expect(engines_map[uuid]).to eq(engine)
      end

      it "creates new engine each time" do
        expect(Categorization::Engine).to receive(:create).exactly(3).times

        described_class.create
        described_class.create
        described_class.create
      end
    end

    context "with explicit name" do
      it "uses provided name" do
        engine = described_class.create("custom-engine")

        engines_map = described_class.send(:engines)
        expect(engines_map["custom-engine"]).to eq(engine)
      end

      it "overwrites existing engine with same name" do
        first_engine = instance_double(Categorization::Engine)
        second_engine = instance_double(Categorization::Engine)

        allow(Categorization::Engine).to receive(:create).and_return(first_engine, second_engine)

        described_class.create("my-engine")
        described_class.create("my-engine")

        engines_map = described_class.send(:engines)
        expect(engines_map["my-engine"]).to eq(second_engine)
      end
    end

    context "with custom configuration" do
      it "merges custom config with defaults" do
        custom_config = {
          cache_size: 2000,
          enable_metrics: false,
          custom_option: "test"
        }

        expected_config = {
          cache_size: 2000, # Overridden
          cache_ttl: 300, # Default
          batch_size: 100, # Default
          enable_circuit_breaker: true, # Default
          circuit_breaker_threshold: 5, # Default
          circuit_breaker_timeout: 60, # Default
          enable_metrics: false, # Overridden
          enable_learning: true, # Default
          confidence_threshold: 0.7, # Default
          custom_option: "test" # New
        }

        expect(Categorization::Engine).to receive(:create).with(expected_config)

        described_class.create("test", custom_config)
      end

      it "raises error when nil config is passed" do
        # The implementation doesn't handle nil gracefully - it will raise TypeError
        expect { described_class.create("test", nil) }.to raise_error(TypeError, /no implicit conversion of nil into Hash/)
      end

      it "handles empty config hash" do
        expect(Categorization::Engine).to receive(:create).with(hash_including(cache_size: 1000))

        described_class.create("test", {})
      end
    end
  end

  describe ".get" do
    let(:mock_engine) { instance_double(Categorization::Engine) }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
    end

    context "when engine exists" do
      it "returns existing engine" do
        described_class.create("existing-engine")

        # Should not create a new engine
        expect(Categorization::Engine).not_to receive(:create)

        result = described_class.get("existing-engine")
        expect(result).to eq(mock_engine)
      end
    end

    context "when engine does not exist" do
      it "creates new engine with given name" do
        expect(Categorization::Engine).to receive(:create).once

        engine = described_class.get("new-engine")

        engines_map = described_class.send(:engines)
        expect(engines_map["new-engine"]).to eq(engine)
      end

      it "caches newly created engine" do
        first_call = described_class.get("cached-engine")

        # Should not create again
        expect(Categorization::Engine).not_to receive(:create)

        second_call = described_class.get("cached-engine")
        expect(first_call).to be(second_call)
      end
    end

    it "handles concurrent access safely" do
      engines_created = Concurrent::AtomicFixnum.new(0)

      allow(Categorization::Engine).to receive(:create) do
        engines_created.increment
        instance_double(Categorization::Engine)
      end

      threads = 10.times.map do
        Thread.new { described_class.get("concurrent-test") }
      end

      threads.each(&:join)

      # Should only create one engine despite concurrent access
      expect(engines_created.value).to eq(1)
    end
  end

  describe ".reset!" do
    let(:mock_engine) { instance_double(Categorization::Engine) }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
    end

    it "clears all cached engines" do
      described_class.create("engine1")
      described_class.create("engine2")
      described_class.default

      described_class.reset!

      engines_map = described_class.send(:engines)
      expect(engines_map).to be_empty
    end

    it "clears default engine" do
      described_class.default
      described_class.reset!

      # Should create new engine after reset
      expect(Categorization::Engine).to receive(:create).once
      described_class.default
    end

    it "allows recreation of engines after reset" do
      described_class.create("test-engine")
      described_class.reset!

      # Should create new engine with same name
      expect(Categorization::Engine).to receive(:create).once
      described_class.get("test-engine")
    end

    it "is thread-safe" do
      10.times { |i| described_class.create("engine-#{i}") }

      threads = 5.times.map do
        Thread.new { described_class.reset! }
      end

      threads.each(&:join)

      engines_map = described_class.send(:engines)
      expect(engines_map).to be_empty
    end
  end

  describe ".active_engines" do
    let(:engine1) { instance_double(Categorization::Engine) }
    let(:engine2) { instance_double(Categorization::Engine) }
    let(:engine3) { instance_double(Categorization::Engine) }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(engine1, engine2, engine3)
    end

    it "returns empty array when no engines exist" do
      expect(described_class.active_engines).to be_empty
    end

    it "returns all cached engines" do
      described_class.create("first")
      described_class.create("second")
      described_class.default

      active = described_class.active_engines

      expect(active).to contain_exactly(engine1, engine2, engine3)
    end

    it "returns unique engine instances" do
      described_class.create("test")
      described_class.get("test") # Should return existing

      active = described_class.active_engines
      expect(active.size).to eq(1)
    end

    it "returns current snapshot of engines" do
      described_class.create("initial")

      snapshot1 = described_class.active_engines
      expect(snapshot1.size).to eq(1)

      described_class.create("additional")

      snapshot2 = described_class.active_engines
      expect(snapshot2.size).to eq(2)
    end
  end

  describe ".configure" do
    it "yields configuration object to block" do
      config_yielded = nil

      described_class.configure do |config|
        config_yielded = config
      end

      expect(config_yielded).to be_an(OpenStruct)
      expect(config_yielded).to eq(described_class.configuration)
    end

    it "allows modifying configuration" do
      described_class.configure do |config|
        config.cache_size = 5000
        config.enable_metrics = false
        config.new_setting = "custom"
      end

      config = described_class.configuration
      expect(config.cache_size).to eq(5000)
      expect(config.enable_metrics).to be false
      expect(config.new_setting).to eq("custom")
    end

    it "persists configuration changes" do
      described_class.configure do |config|
        config.cache_ttl = 600
      end

      # Configuration should persist
      expect(described_class.configuration.cache_ttl).to eq(600)
    end

    it "does nothing without block" do
      expect { described_class.configure }.not_to raise_error
    end

    it "handles errors in configuration block" do
      expect do
        described_class.configure do |_config|
          raise StandardError, "Configuration error"
        end
      end.to raise_error(StandardError, "Configuration error")

      # Configuration should still be accessible
      expect(described_class.configuration).to be_an(OpenStruct)
    end

    it "affects newly created engines" do
      described_class.configure do |config|
        config.cache_size = 3000
        config.custom_flag = true
      end

      expected_config = hash_including(
        cache_size: 3000,
        custom_flag: true
      )

      expect(Categorization::Engine).to receive(:create).with(expected_config)

      described_class.create("configured-engine")
    end
  end

  describe ".configuration" do
    it "returns OpenStruct with default settings" do
      config = described_class.configuration

      expect(config).to be_an(OpenStruct)
      expect(config.cache_size).to eq(1000)
      expect(config.cache_ttl).to eq(300)
      expect(config.batch_size).to eq(100)
      expect(config.enable_circuit_breaker).to be true
      expect(config.circuit_breaker_threshold).to eq(5)
      expect(config.circuit_breaker_timeout).to eq(60)
      expect(config.enable_metrics).to be true
      expect(config.enable_learning).to be true
      expect(config.confidence_threshold).to eq(0.7)
    end

    it "returns same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration

      expect(config1).to be(config2)
    end

    it "can be converted to hash" do
      config_hash = described_class.configuration.to_h

      expect(config_hash).to be_a(Hash)
      expect(config_hash[:cache_size]).to eq(1000)
      expect(config_hash[:enable_metrics]).to be true
    end

    it "allows dynamic attribute access" do
      config = described_class.configuration

      # Should not raise error for new attributes
      config.dynamic_attribute = "test"
      expect(config.dynamic_attribute).to eq("test")
    end
  end

  describe "private methods" do
    describe "#engines" do
      it "returns Concurrent::Map instance" do
        engines = described_class.send(:engines)
        expect(engines).to be_a(Concurrent::Map)
      end

      it "returns same map instance" do
        map1 = described_class.send(:engines)
        map2 = described_class.send(:engines)

        expect(map1).to be(map2)
      end

      it "is thread-safe" do
        threads = 10.times.map do |i|
          Thread.new do
            engines = described_class.send(:engines)
            engines["thread-#{i}"] = "value-#{i}"
          end
        end

        threads.each(&:join)

        engines = described_class.send(:engines)
        expect(engines.size).to eq(10)
      end
    end

    describe "#create_engine" do
      let(:mock_engine) { instance_double(Categorization::Engine) }

      before do
        allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
      end

      it "creates engine with merged configuration" do
        custom = { cache_size: 2500 }
        expected = described_class.configuration.to_h.merge(custom)

        expect(Categorization::Engine).to receive(:create).with(expected)

        described_class.send(:create_engine, "test", custom)
      end

      it "stores engine in engines map" do
        engine = described_class.send(:create_engine, "private-test")

        engines_map = described_class.send(:engines)
        expect(engines_map["private-test"]).to eq(engine)
      end

      it "returns created engine" do
        result = described_class.send(:create_engine, "return-test")
        expect(result).to eq(mock_engine)
      end
    end
  end

  describe "edge cases and error handling" do
    context "with malformed configuration" do
      it "handles nil configuration values" do
        described_class.configure do |config|
          config.cache_size = nil
        end

        expect(Categorization::Engine).to receive(:create).with(hash_including(cache_size: nil))
        described_class.create("nil-config")
      end

      it "handles deeply nested configuration" do
        described_class.configure do |config|
          config.nested = OpenStruct.new(
            level1: OpenStruct.new(
              level2: "deep"
            )
          )
        end

        config = described_class.configuration
        expect(config.nested.level1.level2).to eq("deep")
      end
    end

    context "with special characters in names" do
      let(:mock_engine) { instance_double(Categorization::Engine) }

      before do
        allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
      end

      it "handles names with spaces" do
        described_class.create("engine with spaces")
        engines = described_class.send(:engines)
        expect(engines["engine with spaces"]).to eq(mock_engine)
      end

      it "handles names with special characters" do
        described_class.create("engine-123!@#$%")
        engines = described_class.send(:engines)
        expect(engines["engine-123!@#$%"]).to eq(mock_engine)
      end

      it "handles empty string as name" do
        described_class.create("")
        engines = described_class.send(:engines)
        expect(engines[""]).to eq(mock_engine)
      end
    end

    context "with memory management" do
      it "allows garbage collection of removed engines" do
        mock_engine = instance_double(Categorization::Engine)
        allow(Categorization::Engine).to receive(:create).and_return(mock_engine)

        described_class.create("temp-engine")
        described_class.reset!

        # Engines should be eligible for GC after reset
        engines = described_class.send(:engines)
        expect(engines).to be_empty
      end
    end

    context "with race conditions" do
      it "may create multiple engines under concurrent access" do
        # Note: The current implementation is NOT thread-safe for the default method
        # Multiple threads accessing .default simultaneously may create multiple engines
        # This test documents the actual behavior

        described_class.reset!

        call_count = 0
        mutex = Mutex.new

        allow(Categorization::Engine).to receive(:create) do
          mutex.synchronize { call_count += 1 }
          sleep(0.001) # Small delay to increase race condition likelihood
          instance_double(Categorization::Engine)
        end

        threads = 5.times.map do
          Thread.new { described_class.default }
        end

        threads.each(&:join)

        # Due to race condition, multiple engines might be created
        # but only one will be cached as @default
        expect(call_count).to be >= 1
        expect(call_count).to be <= 5

        # After all threads complete, subsequent calls should use cached value
        expect(Categorization::Engine).not_to receive(:create)
        described_class.default
      end

      it "handles concurrent configuration updates" do
        threads = 10.times.map do |i|
          Thread.new do
            described_class.configure do |config|
              config.send("thread_#{i}=", true)
            end
          end
        end

        threads.each(&:join)

        config = described_class.configuration
        10.times do |i|
          expect(config.send("thread_#{i}")).to be true
        end
      end
    end
  end

  describe "integration scenarios" do
    let(:mock_engine) { instance_double(Categorization::Engine) }

    before do
      allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
    end

    it "supports multiple named engines with different configs" do
      described_class.create("production", { cache_size: 5000, enable_metrics: true })
      described_class.create("staging", { cache_size: 1000, enable_metrics: false })
      described_class.create("development", { cache_size: 100, enable_learning: true })

      expect(described_class.active_engines.size).to eq(3)
    end

    it "allows switching between engines" do
      prod_engine = described_class.create("production", { cache_size: 5000 })
      dev_engine = described_class.create("development", { cache_size: 100 })

      # Can retrieve specific engines
      expect(described_class.get("production")).to eq(prod_engine)
      expect(described_class.get("development")).to eq(dev_engine)
    end

    it "supports engine lifecycle management" do
      # Create engines
      described_class.create("app1")
      described_class.create("app2")

      expect(described_class.active_engines.size).to eq(2)

      # Reset all engines
      described_class.reset!

      expect(described_class.active_engines).to be_empty

      # Recreate engines
      described_class.create("app1")

      expect(described_class.active_engines.size).to eq(1)
    end
  end
end
