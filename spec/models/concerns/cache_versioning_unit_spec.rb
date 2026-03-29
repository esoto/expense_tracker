# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheVersioning, type: :model, unit: true do
  # Minimal host class that includes the concern
  let(:host_class) do
    Class.new do
      include CacheVersioning

      def self.name
        "TestHostClass"
      end
    end
  end

  let(:host_instance) { host_class.new }
  let(:test_key) { "cache_versioning_spec:version:#{SecureRandom.hex(4)}" }

  after { Rails.cache.delete(test_key) }

  describe "MEMORY_STORE_MUTEX constant" do
    # Access via const_get to bypass private_constant visibility
    let(:mutex) { CacheVersioning.const_get(:MEMORY_STORE_MUTEX) }

    it "is a Mutex" do
      expect(mutex).to be_a(Mutex)
    end

    it "is the same object on every access (not re-created)" do
      m1 = CacheVersioning.const_get(:MEMORY_STORE_MUTEX)
      m2 = CacheVersioning.const_get(:MEMORY_STORE_MUTEX)
      expect(m1).to equal(m2)
    end
  end

  describe ".atomic_cache_increment (class method)" do
    context "when Rails.cache is MemoryStore" do
      before do
        allow(Rails.cache).to receive(:is_a?).with(ActiveSupport::Cache::MemoryStore).and_return(true)
      end

      it "initialises the key to 1 when absent" do
        Rails.cache.delete(test_key)
        host_class.atomic_cache_increment(test_key)
        expect(Rails.cache.read(test_key)).to eq(1)
      end

      it "increments the key by 1 each call" do
        Rails.cache.write(test_key, 5)
        host_class.atomic_cache_increment(test_key)
        expect(Rails.cache.read(test_key)).to eq(6)
      end

      it "returns the new version value written to the cache" do
        Rails.cache.write(test_key, 2)
        host_class.atomic_cache_increment(test_key)
        expect(Rails.cache.read(test_key)).to eq(3)
      end

      it "uses MEMORY_STORE_MUTEX for thread safety" do
        mutex = CacheVersioning.const_get(:MEMORY_STORE_MUTEX)
        expect(mutex).to receive(:synchronize).and_call_original
        host_class.atomic_cache_increment(test_key)
      end

      it "does not use lazy ||= mutex initialisation" do
        # The concern must NOT use @version_mutex ||= patterns — the constant
        # must be fully initialised at class-load time.
        source = CacheVersioning.instance_method(:atomic_cache_increment).source_location.first
        content = File.read(source)
        expect(content).not_to match(/@\w+_mutex\s*\|\|=/)
      end
    end

    context "when Rails.cache is a distributed backend (e.g. Redis)" do
      before do
        allow(Rails.cache).to receive(:is_a?).with(ActiveSupport::Cache::MemoryStore).and_return(false)
      end

      it "delegates to Rails.cache.increment" do
        expect(Rails.cache).to receive(:increment).with(test_key, 1, initial: 1).and_return(1)
        host_class.atomic_cache_increment(test_key)
      end

      it "falls back to Rails.cache.write when increment returns nil" do
        allow(Rails.cache).to receive(:increment).and_return(nil)
        expect(Rails.cache).to receive(:write).with(test_key, 1)
        host_class.atomic_cache_increment(test_key)
      end
    end

    context "error handling" do
      it "logs an error and returns nil when an exception occurs" do
        allow(Rails.cache).to receive(:is_a?).and_raise(StandardError, "cache exploded")
        expect(Rails.logger).to receive(:error).with(/cache exploded/)
        result = host_class.atomic_cache_increment(test_key)
        expect(result).to be_nil
      end

      it "includes the log_tag in the error message" do
        allow(Rails.cache).to receive(:is_a?).and_raise(StandardError, "boom")
        expect(Rails.logger).to receive(:error).with(/\[MyService\]/)
        host_class.atomic_cache_increment(test_key, log_tag: "[MyService]")
      end
    end

    context "default log_tag" do
      it "uses the class name when no log_tag is supplied" do
        allow(Rails.cache).to receive(:is_a?).and_raise(StandardError, "err")
        expect(Rails.logger).to receive(:error).with(/TestHostClass/)
        host_class.atomic_cache_increment(test_key)
      end
    end
  end

  describe "#atomic_cache_increment (instance method)" do
    context "when Rails.cache is MemoryStore" do
      before do
        allow(Rails.cache).to receive(:is_a?).with(ActiveSupport::Cache::MemoryStore).and_return(true)
      end

      it "delegates to the class method" do
        expect(host_class).to receive(:atomic_cache_increment).with(test_key, log_tag: "TestHostClass", logger: Rails.logger)
        host_instance.atomic_cache_increment(test_key)
      end

      it "increments the key correctly" do
        Rails.cache.write(test_key, 3)
        host_instance.atomic_cache_increment(test_key)
        expect(Rails.cache.read(test_key)).to eq(4)
      end
    end
  end

  describe "integration: consumers use the concern" do
    it "DashboardService includes CacheVersioning" do
      expect(Services::DashboardService.ancestors).to include(CacheVersioning)
    end

    it "MetricsCalculator includes CacheVersioning" do
      expect(Services::MetricsCalculator.ancestors).to include(CacheVersioning)
    end

    it "CategorizationPattern includes CacheVersioning" do
      expect(CategorizationPattern.ancestors).to include(CacheVersioning)
    end

    it "PatternFeedback includes CacheVersioning" do
      expect(PatternFeedback.ancestors).to include(CacheVersioning)
    end

    it "PatternLearningEvent includes CacheVersioning" do
      expect(PatternLearningEvent.ancestors).to include(CacheVersioning)
    end

    it "Services::Categorization::PatternCache includes CacheVersioning" do
      expect(Services::Categorization::PatternCache.ancestors).to include(CacheVersioning)
    end
  end

  describe "thread safety: no lazy mutex initialization" do
    it "Services::DashboardService does not use lazy version_mutex" do
      source_path = Rails.root.join("app/services/dashboard_service.rb")
      content = File.read(source_path)
      expect(content).not_to match(/@version_mutex\s*\|\|=/)
    end

    it "Services::MetricsCalculator does not use lazy version_mutex" do
      source_path = Rails.root.join("app/services/metrics_calculator.rb")
      content = File.read(source_path)
      expect(content).not_to match(/@version_mutex\s*\|\|=/)
    end
  end
end
