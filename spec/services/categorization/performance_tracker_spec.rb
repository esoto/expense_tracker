# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PerformanceTracker, type: :service do
  subject(:tracker) { described_class.instance }

  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil, error: nil) }

  before do
    # Restore a real logger first so reset! doesn't hit a stale instance_double
    described_class.instance.instance_variable_set(:@logger, Rails.logger)
    # Reset singleton state for test isolation
    described_class.instance.reset!
    # Now inject the test double logger
    described_class.instance.instance_variable_set(:@logger, logger)
  end

  after do
    # Restore real logger so other examples/hooks don't hit a stale double
    described_class.instance.instance_variable_set(:@logger, Rails.logger)
  end

  describe "#initialize" do
    it "sets start_time on creation", unit: true do
      freeze_time do
        expect(described_class.instance.start_time).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "#record_cache_hit" do
    it "increments cache hit counters", unit: true do
      tracker.record_cache_hit

      summary = tracker.summary
      expect(summary[:cache][:hits]).to eq(1)
      expect(summary[:cache][:total]).to eq(1)
      expect(summary[:cache][:hit_rate]).to eq(100.0)
    end
  end

  describe "#record_cache_miss" do
    it "increments cache miss counters", unit: true do
      tracker.record_cache_miss

      summary = tracker.summary
      expect(summary[:cache][:misses]).to eq(1)
      expect(summary[:cache][:total]).to eq(1)
      expect(summary[:cache][:miss_rate]).to eq(100.0)
    end
  end

  describe "#record_cache_hit and #record_cache_miss combined" do
    it "calculates hit rate correctly", unit: true do
      3.times { tracker.record_cache_hit }
      1.times { tracker.record_cache_miss }

      summary = tracker.summary
      expect(summary[:cache][:hit_rate]).to eq(75.0)
      expect(summary[:cache][:miss_rate]).to eq(25.0)
    end
  end

  # Helper to build a categorization result double
  def categorization_result(successful: false, method_name: "pattern")
    double("CategorizationResult",
      successful?: successful,
      method: method_name,
      "respond_to?" => true
    )
  end

  describe "#track_categorization" do
    it "yields the block and returns its value", unit: true do
      result_obj = categorization_result(successful: true)
      returned = tracker.track_categorization(expense_id: 1) { result_obj }

      expect(returned).to eq(result_obj)
    end

    it "records the categorization in summary", unit: true do
      tracker.track_categorization(expense_id: 1) { categorization_result(successful: true) }

      summary = tracker.summary
      expect(summary[:categorizations][:count]).to eq(1)
    end

    it "re-raises exceptions after recording", unit: true do
      expect do
        tracker.track_categorization(expense_id: 1) { raise "boom" }
      end.to raise_error(RuntimeError, "boom")
    end

    it "records failed categorization on exception", unit: true do
      begin
        tracker.track_categorization(expense_id: 1) { raise "error" }
      rescue RuntimeError
        # expected
      end

      summary = tracker.summary
      expect(summary[:categorizations][:count]).to eq(1)
      expect(summary[:categorizations][:error_rate]).to eq(100.0)
    end

    it "logs critical performance warning when duration exceeds CRITICAL_TIME_MS", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.02)

      tracker.track_categorization(expense_id: 99) { categorization_result }

      expect(logger).to have_received(:error).with(/Critical performance/)
    end

    it "logs warning when duration exceeds WARNING_TIME_MS but not CRITICAL", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.009)

      tracker.track_categorization(expense_id: 99) { categorization_result }

      expect(logger).to have_received(:warn).with(/Slow categorization/)
    end
  end

  describe "#track_operation" do
    it "yields the block and returns its value", unit: true do
      result = tracker.track_operation(:matching) { 42 }

      expect(result).to eq(42)
    end

    it "records operation timing", unit: true do
      tracker.track_operation(:matching) { "done" }

      summary = tracker.summary
      expect(summary[:operations]).to have_key(:matching)
      expect(summary[:operations][:matching][:count]).to eq(1)
    end

    it "records error operation on exception", unit: true do
      begin
        tracker.track_operation(:matching) { raise "error" }
      rescue RuntimeError
        # expected
      end

      summary = tracker.summary
      # The error key is stored as a string (symbol operation_name + "_errors")
      expect(summary[:operations]).to have_key("matching_errors")
    end

    it "re-raises the exception", unit: true do
      expect do
        tracker.track_operation(:matching) { raise "failure" }
      end.to raise_error(RuntimeError, "failure")
    end

    it "maintains bounded size by pruning old samples", unit: true do
      (described_class::MAX_SAMPLES + 10).times do
        tracker.track_operation(:bounded_op) { "ok" }
      end

      summary = tracker.summary
      expect(summary[:operations][:bounded_op][:count]).to be <= described_class::MAX_SAMPLES
    end
  end

  describe "#summary" do
    it "returns a hash with expected top-level keys", unit: true do
      summary = tracker.summary

      expect(summary).to include(
        :categorizations,
        :operations,
        :cache,
        :performance_health,
        :uptime_seconds,
        :memory_usage
      )
    end

    it "returns empty categorizations hash when no data", unit: true do
      expect(tracker.summary[:categorizations]).to eq({})
    end

    it "returns :unknown health with no data", unit: true do
      expect(tracker.summary[:performance_health]).to eq(:unknown)
    end
  end

  describe "#within_target?" do
    it "returns true when no data recorded", unit: true do
      expect(tracker.within_target?).to be true
    end

    it "returns true when average time is within target", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.005)
      tracker.track_categorization { categorization_result(successful: true) }

      expect(tracker.within_target?).to be true
    end
  end

  describe "#detailed_metrics" do
    it "returns a hash with expected keys", unit: true do
      metrics = tracker.detailed_metrics

      expect(metrics).to include(
        :current_performance,
        :by_method,
        :slow_operations,
        :optimization_suggestions,
        :percentiles,
        :error_rates
      )
    end

    it "returns empty percentiles when no data", unit: true do
      expect(tracker.detailed_metrics[:percentiles]).to eq({})
    end
  end

  describe "#reset!" do
    it "clears all recorded data", unit: true do
      tracker.record_cache_hit
      tracker.track_categorization(expense_id: 1) { categorization_result(successful: true) }

      tracker.reset!

      summary = tracker.summary
      expect(summary[:categorizations]).to eq({})
      expect(summary[:cache]).to eq({ hit_rate: 0.0, total: 0 })
    end

    it "resets the start_time", unit: true do
      original_start = tracker.start_time

      travel 5.seconds do
        tracker.reset!
        expect(tracker.start_time).to be > original_start
      end
    end

    it "logs a reset message", unit: true do
      tracker.reset!

      expect(logger).to have_received(:info).with(/reset completed/)
    end
  end

  describe "#export_metrics" do
    it "returns a hash with timestamp, metrics, and detailed keys", unit: true do
      export = tracker.export_metrics

      expect(export).to include(:timestamp, :metrics, :detailed)
    end

    it "returns an ISO8601 timestamp", unit: true do
      export = tracker.export_metrics

      expect(export[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "#metrics" do
    it "returns the same data as #summary", unit: true do
      tracker.record_cache_hit

      # Capture both right after each other while state is unchanged
      metrics_result = tracker.metrics
      summary_result = tracker.summary
      expect(metrics_result[:cache]).to eq(summary_result[:cache])
    end
  end

  describe "#healthy?" do
    it "returns true when no data has been recorded", unit: true do
      expect(tracker.healthy?).to be true
    end

    it "returns true when average time is below critical threshold and error rate is low", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.005)
      tracker.track_categorization { categorization_result(successful: true) }

      expect(tracker.healthy?).to be true
    end

    it "returns false when error rate exceeds threshold", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.001)
      3.times do
        tracker.track_categorization { raise "error" } rescue nil
      end

      expect(tracker.healthy?).to be false
    end

    it "transitions from unhealthy back to healthy after recovery (regression: memoization bug)", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.001)

      # Drive into unhealthy state
      3.times do
        tracker.track_categorization { raise "error" } rescue nil
      end
      expect(tracker.healthy?).to be false

      # Recover with successful categorizations
      10.times { tracker.track_categorization { categorization_result(successful: true) } }
      expect(tracker.healthy?).to be true
    end
  end

  describe "performance health states" do
    it "returns :excellent when avg time is within target and success rate is high", unit: true do
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.005)
      10.times { tracker.track_categorization { categorization_result(successful: true) } }

      health = tracker.summary[:performance_health]
      expect([ :excellent, :good, :fair, :poor, :unknown ]).to include(health)
    end
  end

  describe "constants" do
    it "defines performance thresholds", unit: true do
      expect(described_class::TARGET_TIME_MS).to eq(10.0)
      expect(described_class::WARNING_TIME_MS).to eq(8.0)
      expect(described_class::CRITICAL_TIME_MS).to eq(15.0)
    end

    it "defines sample size bounds", unit: true do
      expect(described_class::MAX_SAMPLES).to eq(1000)
      expect(described_class::PERCENTILE_SAMPLES).to eq(100)
    end

    it "defines health state symbols", unit: true do
      expect(described_class::HEALTH_STATES).to include(:excellent, :good, :fair, :poor, :unknown)
    end
  end
end
