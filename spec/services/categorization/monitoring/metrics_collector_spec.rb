# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Monitoring::MetricsCollector, type: :service do
  # Reset the singleton between examples so each test gets a fresh state
  subject(:collector) { described_class.instance }

  before do
    # Force re-initialization of the singleton between tests
    described_class.instance.instance_variable_set(:@enabled, false)
    described_class.instance.instance_variable_set(:@client, nil)
  end

  after do
    # Prevent mock doubles from leaking to other specs via the singleton
    described_class.instance.instance_variable_set(:@enabled, false)
    described_class.instance.instance_variable_set(:@client, nil)
  end

  describe "constants" do
    it "defines confidence buckets covering 0..1", unit: true do
      buckets = described_class::CONFIDENCE_BUCKETS

      expect(buckets.keys).to include(:very_high, :high, :medium, :low, :very_low)
      expect(buckets[:very_high]).to cover(0.95)
      expect(buckets[:very_low]).to cover(0.1)
    end
  end

  describe "#initialize" do
    it "sets enabled from Rails config or defaults to false", unit: true do
      expect([ true, false ]).to include(collector.enabled)
    end

    it "sets a prefix", unit: true do
      expect(collector.prefix).to be_a(String)
      expect(collector.prefix).not_to be_empty
    end
  end

  describe "#track_categorization" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect { collector.track_categorization(expense_id: 1, success: true, confidence: 0.9, duration_ms: 5) }
          .not_to raise_error
      end
    end

    context "when enabled with a mock client" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:timing)
        allow(mock_client).to receive(:gauge)
        allow(mock_client).to receive(:histogram)
        allow(mock_client).to receive(:respond_to?).with(:histogram).and_return(true)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "increments attempts.total", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 10)

        expect(mock_client).to have_received(:increment).with("attempts.total", 1)
      end

      it "increments attempts.success on success", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 10)

        expect(mock_client).to have_received(:increment).with("attempts.success", 1)
      end

      it "increments attempts.failure on failure", unit: true do
        collector.track_categorization(expense_id: 1, success: false, confidence: 0.3, duration_ms: 10)

        expect(mock_client).to have_received(:increment).with("attempts.failure", 1)
      end

      it "tracks duration timing", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 15)

        expect(mock_client).to have_received(:timing).with("duration", 15)
      end

      it "tracks confidence gauge", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.85, duration_ms: 5)

        expect(mock_client).to have_received(:gauge).with("confidence.last", 0.85)
      end

      it "increments by method when method is provided", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 5, method: "pattern")

        expect(mock_client).to have_received(:increment).with("attempts.by_method.pattern", 1)
      end

      it "increments category count on success", unit: true do
        collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 5, category_id: 42)

        expect(mock_client).to have_received(:increment).with("categories.42", 1)
      end

      it "does not raise when an error occurs", unit: true do
        allow(mock_client).to receive(:increment).and_raise(StandardError, "connection refused")

        expect do
          collector.track_categorization(expense_id: 1, success: true, confidence: 0.8, duration_ms: 5)
        end.not_to raise_error
      end
    end
  end

  describe "#track_cache" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect do
          collector.track_cache(operation: :read, cache_type: :pattern, hit: true)
        end.not_to raise_error
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:timing)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "increments total operation counter", unit: true do
        collector.track_cache(operation: :read, cache_type: :pattern, hit: true)

        expect(mock_client).to have_received(:increment).with("cache.pattern.read.total", 1)
      end

      it "increments hit counter when cache is hit", unit: true do
        collector.track_cache(operation: :read, cache_type: :pattern, hit: true)

        expect(mock_client).to have_received(:increment).with("cache.pattern.read.hit", 1)
      end

      it "increments miss counter when cache is missed", unit: true do
        collector.track_cache(operation: :read, cache_type: :pattern, hit: false)

        expect(mock_client).to have_received(:increment).with("cache.pattern.read.miss", 1)
      end

      it "tracks duration timing when provided", unit: true do
        collector.track_cache(operation: :read, cache_type: :pattern, hit: true, duration_ms: 2.5)

        expect(mock_client).to have_received(:timing).with("cache.pattern.read.duration", 2.5)
      end

      it "does not track timing when duration_ms is nil", unit: true do
        collector.track_cache(operation: :read, cache_type: :pattern, hit: true)

        expect(mock_client).not_to have_received(:timing)
      end
    end
  end

  describe "#track_learning" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect do
          collector.track_learning(action: :create, pattern_type: :keyword, success: true)
        end.not_to raise_error
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:gauge)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "increments learning total counter", unit: true do
        collector.track_learning(action: :create, pattern_type: :keyword, success: true)

        expect(mock_client).to have_received(:increment).with("learning.keyword.create.total", 1)
      end

      it "increments success counter on success", unit: true do
        collector.track_learning(action: :create, pattern_type: :keyword, success: true)

        expect(mock_client).to have_received(:increment).with("learning.keyword.create.success", 1)
      end

      it "increments failure counter on failure", unit: true do
        collector.track_learning(action: :create, pattern_type: :keyword, success: false)

        expect(mock_client).to have_received(:increment).with("learning.keyword.create.failure", 1)
      end

      it "tracks confidence_change gauge when provided", unit: true do
        collector.track_learning(action: :update, pattern_type: :keyword, success: true, confidence_change: 0.1)

        expect(mock_client).to have_received(:gauge).with("learning.keyword.confidence_change", 0.1)
      end

      it "increments improvements when confidence_change is positive", unit: true do
        collector.track_learning(action: :update, pattern_type: :keyword, success: true, confidence_change: 0.05)

        expect(mock_client).to have_received(:increment).with("learning.keyword.improvements", 1)
      end

      it "increments degradations when confidence_change is negative", unit: true do
        collector.track_learning(action: :update, pattern_type: :keyword, success: true, confidence_change: -0.05)

        expect(mock_client).to have_received(:increment).with("learning.keyword.degradations", 1)
      end
    end
  end

  describe "#track_error" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect do
          collector.track_error(error_type: :timeout)
        end.not_to raise_error
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "increments errors.total", unit: true do
        collector.track_error(error_type: :timeout)

        expect(mock_client).to have_received(:increment).with("errors.total", 1)
      end

      it "increments errors.by_type", unit: true do
        collector.track_error(error_type: :timeout)

        expect(mock_client).to have_received(:increment).with("errors.by_type.timeout", 1)
      end

      it "increments errors.by_service when context includes service", unit: true do
        collector.track_error(error_type: :timeout, context: { service: "engine" })

        expect(mock_client).to have_received(:increment).with("errors.by_service.engine", 1)
      end

      it "increments errors.by_method when context includes method", unit: true do
        collector.track_error(error_type: :timeout, context: { method: "pattern_match" })

        expect(mock_client).to have_received(:increment).with("errors.by_method.pattern_match", 1)
      end

      it "ignores unknown context keys", unit: true do
        collector.track_error(error_type: :timeout, context: { unknown_key: "ignored" })

        # Should not increment for unknown_key
        expect(mock_client).not_to have_received(:increment).with("errors.by_unknown_key.ignored", 1)
      end
    end
  end

  describe "#track_performance" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect do
          collector.track_performance(metric_name: "cache_size", value: 500)
        end.not_to raise_error
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:gauge)
        allow(mock_client).to receive(:histogram)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "records a gauge for the metric", unit: true do
        collector.track_performance(metric_name: "cache_size", value: 500)

        expect(mock_client).to have_received(:gauge).with("performance.cache_size", 500)
      end

      it "records histogram when unit is :percentage", unit: true do
        collector.track_performance(metric_name: "hit_rate", value: 0.85, unit: :percentage)

        expect(mock_client).to have_received(:histogram).with("performance.hit_rate.percentage", 85.0)
      end

      it "records histogram when unit is :bytes", unit: true do
        collector.track_performance(metric_name: "mem", value: 1024, unit: :bytes)

        expect(mock_client).to have_received(:histogram).with("performance.mem.bytes", 1024)
      end

      it "increments count when unit is :count", unit: true do
        collector.track_performance(metric_name: "requests", value: 5, unit: :count)

        expect(mock_client).to have_received(:increment).with("performance.requests.count", 5)
      end
    end
  end

  describe "#snapshot" do
    context "when disabled" do
      it "returns an empty hash", unit: true do
        expect(collector.snapshot).to eq({})
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "returns a snapshot hash with enabled and prefix", unit: true do
        snapshot = collector.snapshot

        expect(snapshot).to include(
          enabled: true,
          prefix: be_a(String)
        )
        expect(snapshot).to have_key(:client_connected)
      end
    end
  end

  describe "#batch" do
    context "when disabled" do
      it "does nothing and does not raise", unit: true do
        expect { collector.batch { } }.not_to raise_error
      end
    end

    context "when enabled" do
      let(:mock_client) { instance_double("StatsD") }

      before do
        collector.instance_variable_set(:@enabled, true)
        collector.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:increment)
        allow(mock_client).to receive(:present?).and_return(true)
      end

      it "yields self to the block", unit: true do
        yielded = nil
        collector.batch { |c| yielded = c }

        expect(yielded).to eq(collector)
      end
    end
  end

  describe "class-level delegation" do
    it "delegates .track_categorization to instance", unit: true do
      expect(described_class).to respond_to(:track_categorization)
    end

    it "delegates .track_cache to instance", unit: true do
      expect(described_class).to respond_to(:track_cache)
    end

    it "delegates .track_learning to instance", unit: true do
      expect(described_class).to respond_to(:track_learning)
    end

    it "delegates .track_error to instance", unit: true do
      expect(described_class).to respond_to(:track_error)
    end

    it "delegates .track_performance to instance", unit: true do
      expect(described_class).to respond_to(:track_performance)
    end

    it "delegates .snapshot to instance", unit: true do
      expect(described_class).to respond_to(:snapshot)
    end

    it "delegates .batch to instance", unit: true do
      expect(described_class).to respond_to(:batch)
    end
  end
end
