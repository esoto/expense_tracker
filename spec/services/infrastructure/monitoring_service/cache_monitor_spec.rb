# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Services::Infrastructure::MonitoringService::CacheMonitor, type: :service, unit: true do
  include MonitoringServiceTestHelper

  let(:cache_monitor) { described_class }

  before do
    setup_time_helpers
    setup_logger_mock
  end

  describe ".metrics" do
    it "returns comprehensive cache metrics aggregation" do
      # Mock individual metric methods
      pattern_metrics = { hit_rate: 85.5, total_hits: 1000 }
      rails_metrics = { type: "ActiveSupport::Cache::MemoryStore" }
      performance_metrics = { average_warming_duration_seconds: 15.2 }
      health_status = { overall: "healthy" }

      allow(cache_monitor).to receive(:pattern_cache_metrics).and_return(pattern_metrics)
      allow(cache_monitor).to receive(:rails_cache_metrics).and_return(rails_metrics)
      allow(cache_monitor).to receive(:cache_performance_metrics).and_return(performance_metrics)
      allow(cache_monitor).to receive(:cache_health_status).and_return(health_status)

      result = cache_monitor.metrics

      expect(result).to eq({
        pattern_cache: pattern_metrics,
        rails_cache: rails_metrics,
        performance: performance_metrics,
        health: health_status
      })
    end

    it "calls all individual metrics methods" do
      expect(cache_monitor).to receive(:pattern_cache_metrics).and_return({})
      expect(cache_monitor).to receive(:rails_cache_metrics).and_return({})
      expect(cache_monitor).to receive(:cache_performance_metrics).and_return({})
      expect(cache_monitor).to receive(:cache_health_status).and_return({})

      cache_monitor.metrics
    end
  end

  describe ".pattern_cache_metrics" do
    context "when PatternCache is available" do
      it "returns complete pattern cache metrics" do
        mock_pattern_cache({
          hit_rate: 87.5,
          hits: 1200,
          misses: 180,
          memory_cache_entries: 650,
          redis_available: true,
          average_lookup_time_ms: 3.2
        })

        # Mock warmup status
        allow(cache_monitor).to receive(:warmup_status).and_return({
          status: "recent",
          last_run: current_time - 10.minutes,
          minutes_ago: 10
        })

        result = cache_monitor.pattern_cache_metrics

        expect(result).to include(
          hit_rate: 87.5,
          total_hits: 1200,
          total_misses: 180,
          memory_entries: 650,
          redis_available: true,
          average_lookup_time_ms: 3.2,
          warmup_status: {
            status: "recent",
            last_run: current_time - 10.minutes,
            minutes_ago: 10
          }
        )
      end

      it "handles nil average_lookup_time_ms gracefully" do
        mock_pattern_cache({
          hit_rate: 90.0,
          hits: 800,
          misses: 100,
          memory_cache_entries: 400,
          redis_available: true,
          average_lookup_time_ms: nil
        })

        allow(cache_monitor).to receive(:warmup_status).and_return({ status: "never_run" })

        result = cache_monitor.pattern_cache_metrics

        expect(result[:average_lookup_time_ms]).to eq(0)
      end

      it "handles PatternCache errors gracefully" do
        pattern_cache_instance = double("PatternCache instance")
        allow(pattern_cache_instance).to receive(:metrics).and_raise(StandardError.new("Redis connection failed"))

        pattern_cache_class = double("Services::Categorization::PatternCache")
        stub_const("Services::Categorization::PatternCache", pattern_cache_class)
        allow(pattern_cache_class).to receive(:instance).and_return(pattern_cache_instance)

        # Also stub the short form used in defined? checks
        categorization_module = Module.new
        categorization_module.const_set("PatternCache", pattern_cache_class)
        stub_const("Categorization", categorization_module)

        result = cache_monitor.pattern_cache_metrics

        expect(result).to eq({ error: "Redis connection failed" })
        expect(@logger_mock).to have_received(:error).with("Failed to get pattern cache metrics: Redis connection failed")
      end
    end

    context "when PatternCache is not defined" do
      it "returns empty hash when PatternCache is not available" do
        # Remove PatternCache constant if it exists
        if defined?(Services::Categorization::PatternCache)
          hide_const("Services::Categorization::PatternCache")
        end

        result = cache_monitor.pattern_cache_metrics

        expect(result).to eq({})
      end
    end
  end

  describe ".rails_cache_metrics" do
    context "when Rails.cache supports stats" do
      it "returns cache stats from Rails.cache" do
        cache_with_stats = double("Cache with stats")
        cache_stats = {
          get_hits: 1500,
          get_misses: 300,
          set_writes: 800,
          delete_hits: 50
        }

        allow(cache_with_stats).to receive(:respond_to?).with(:stats).and_return(true)
        allow(cache_with_stats).to receive(:stats).and_return(cache_stats)
        # Add clear method support for test framework compatibility
        allow(cache_with_stats).to receive(:clear)
        allow(Rails).to receive(:cache).and_return(cache_with_stats)

        result = cache_monitor.rails_cache_metrics

        expect(result).to eq(cache_stats)
      end
    end

    context "when Rails.cache does not support stats" do
      it "returns cache type and availability" do
        memory_cache = setup_memory_cache
        allow(cache_monitor).to receive(:test_cache_availability).and_return(true)

        result = cache_monitor.rails_cache_metrics

        expect(result).to eq({
          type: "ActiveSupport::Cache::MemoryStore",
          available: true
        })
      end

      it "handles unavailable cache" do
        memory_cache = setup_memory_cache
        allow(cache_monitor).to receive(:test_cache_availability).and_return(false)

        result = cache_monitor.rails_cache_metrics

        expect(result).to eq({
          type: "ActiveSupport::Cache::MemoryStore",
          available: false
        })
      end
    end
  end

  describe ".cache_performance_metrics" do
    let(:memory_cache) { setup_memory_cache }

    context "when performance data exists" do
      it "calculates performance metrics from recent cache data" do
        # Setup performance data for the last 10 days
        5.times do |i|
          key = "performance_metrics:pattern_cache:warming:#{(Date.current - i.days)}"
          data = {
            duration: 10.0 + (i * 2.5),
            patterns: 100 + (i * 20),
            timestamp: current_time - (i * 12).hours
          }
          memory_cache.write(key, data)
        end

        result = cache_monitor.cache_performance_metrics

        expect(result[:average_warming_duration_seconds]).to be_within(0.1).of(15.0) # Average of durations
        expect(result[:average_patterns_warmed]).to eq(140) # Average of patterns
        expect(result[:last_warming_at]).to eq(current_time) # Most recent timestamp
        expect(result[:warming_success_rate]).to eq(100.0) # All successful (no errors)
      end

      it "calculates success rate with mixed success/failure data" do
        # Setup mixed success/failure data
        3.times do |i|
          key = "performance_metrics:pattern_cache:warming:#{(Date.current - i.days)}"
          data = {
            duration: i.even? ? 12.5 : nil,
            patterns: i.even? ? 150 : 0,
            timestamp: current_time - (i * 8).hours,
            error: i.odd? ? "Connection timeout" : nil
          }
          memory_cache.write(key, data)
        end

        result = cache_monitor.cache_performance_metrics

        expect(result[:warming_success_rate]).to eq(66.67) # 2 out of 3 successful
      end

      it "handles missing duration and pattern data gracefully" do
        2.times do |i|
          key = "performance_metrics:pattern_cache:warming:#{(Date.current - i.days)}"
          data = {
            duration: nil,
            patterns: nil,
            timestamp: current_time - (i * 6).hours
          }
          memory_cache.write(key, data)
        end

        result = cache_monitor.cache_performance_metrics

        expect(result[:average_warming_duration_seconds]).to eq(0)
        expect(result[:average_patterns_warmed]).to eq(0)
        expect(result[:warming_success_rate]).to eq(100.0) # No errors present
      end
    end

    context "when no performance data exists" do
      it "returns empty hash when no data is available" do
        result = cache_monitor.cache_performance_metrics

        expect(result).to eq({})
      end
    end
  end

  describe ".cache_health_status" do
    it "returns overall healthy status when all caches are healthy" do
      pattern_health = { status: "healthy", hit_rate: 90.0 }
      rails_health = { status: "healthy", available: true }

      allow(cache_monitor).to receive(:check_pattern_cache_health).and_return(pattern_health)
      allow(cache_monitor).to receive(:check_rails_cache_health).and_return(rails_health)
      allow(cache_monitor).to receive(:generate_cache_recommendations).with(pattern_health, rails_health).and_return([])

      result = cache_monitor.cache_health_status

      expect(result).to include(
        overall: "healthy",
        pattern_cache: pattern_health,
        rails_cache: rails_health,
        recommendations: []
      )
    end

    it "returns degraded status when pattern cache has issues" do
      pattern_health = { status: "warning", hit_rate: 70.0 }
      rails_health = { status: "healthy", available: true }

      allow(cache_monitor).to receive(:check_pattern_cache_health).and_return(pattern_health)
      allow(cache_monitor).to receive(:check_rails_cache_health).and_return(rails_health)
      allow(cache_monitor).to receive(:generate_cache_recommendations).and_return([ "Consider cache tuning" ])

      result = cache_monitor.cache_health_status

      expect(result[:overall]).to eq("degraded")
    end

    it "returns critical status when any cache is critical" do
      pattern_health = { status: "healthy", hit_rate: 85.0 }
      rails_health = { status: "critical", available: false }

      allow(cache_monitor).to receive(:check_pattern_cache_health).and_return(pattern_health)
      allow(cache_monitor).to receive(:check_rails_cache_health).and_return(rails_health)
      allow(cache_monitor).to receive(:generate_cache_recommendations).and_return([ "Critical: Fix Rails cache" ])

      result = cache_monitor.cache_health_status

      expect(result[:overall]).to eq("critical")
    end
  end

  describe ".warmup_status" do
    let(:memory_cache) { setup_memory_cache }

    context "when warmup has never run" do
      it "returns never_run status" do
        result = cache_monitor.send(:warmup_status)

        expect(result).to eq({ status: "never_run" })
      end
    end

    context "when warmup ran recently" do
      it "returns recent status for warmup within 20 minutes" do
        last_warmup = {
          timestamp: current_time - 15.minutes,
          patterns_warmed: 500
        }
        memory_cache.write("pattern_cache:last_warmup", last_warmup)

        result = cache_monitor.send(:warmup_status)

        expect(result).to eq({
          status: "recent",
          last_run: current_time - 15.minutes,
          minutes_ago: 15
        })
      end
    end

    context "when warmup is stale" do
      it "returns stale status for warmup between 20 minutes and 1 hour" do
        last_warmup = {
          timestamp: current_time - 45.minutes,
          patterns_warmed: 300
        }
        memory_cache.write("pattern_cache:last_warmup", last_warmup)

        result = cache_monitor.send(:warmup_status)

        expect(result).to eq({
          status: "stale",
          last_run: current_time - 45.minutes,
          minutes_ago: 45
        })
      end
    end

    context "when warmup is outdated" do
      it "returns outdated status for warmup older than 1 hour" do
        last_warmup = {
          timestamp: current_time - 2.hours,
          patterns_warmed: 200
        }
        memory_cache.write("pattern_cache:last_warmup", last_warmup)

        result = cache_monitor.send(:warmup_status)

        expect(result).to eq({
          status: "outdated",
          last_run: current_time - 2.hours,
          minutes_ago: 120
        })
      end
    end
  end

  describe ".test_cache_availability" do
    let(:memory_cache) { setup_memory_cache }

    it "returns true when cache write/read succeeds" do
      result = cache_monitor.send(:test_cache_availability)

      expect(result).to be(true)
    end

    it "returns false when cache write fails" do
      allow(memory_cache).to receive(:write).and_raise(StandardError.new("Cache unavailable"))

      result = cache_monitor.send(:test_cache_availability)

      expect(result).to be(false)
    end
  end

  describe ".check_pattern_cache_health" do
    context "when PatternCache is not configured" do
      it "returns not_configured status" do
        hide_const("Services::Categorization::PatternCache") if defined?(Services::Categorization::PatternCache)

        result = cache_monitor.send(:check_pattern_cache_health)

        expect(result).to eq({ status: "not_configured" })
      end
    end

    context "when PatternCache is configured" do
      before do
        # Stub the Categorization module for defined? checks
        categorization_module = Module.new
        categorization_module.const_set("PatternCache", double("PatternCache"))
        stub_const("Categorization", categorization_module)
      end

      it "returns healthy status for good metrics" do
        allow(cache_monitor).to receive(:pattern_cache_metrics).and_return({
          hit_rate: 90.0,
          memory_entries: 500,
          redis_available: true,
          average_lookup_time_ms: 2.0
        })
        allow(cache_monitor).to receive(:identify_pattern_cache_issues).and_return([])

        result = cache_monitor.send(:check_pattern_cache_health)

        expect(result).to include(
          status: "healthy",
          hit_rate: 90.0,
          memory_usage: 500,
          issues: []
        )
      end

      it "returns warning status for moderate issues" do
        allow(cache_monitor).to receive(:pattern_cache_metrics).and_return({
          hit_rate: 70.0,
          memory_entries: 800
        })
        allow(cache_monitor).to receive(:identify_pattern_cache_issues).and_return([ "Low hit rate" ])

        result = cache_monitor.send(:check_pattern_cache_health)

        expect(result[:status]).to eq("warning")
      end

      it "returns degraded status for poor hit rate" do
        allow(cache_monitor).to receive(:pattern_cache_metrics).and_return({
          hit_rate: 45.0,
          memory_entries: 300
        })
        allow(cache_monitor).to receive(:identify_pattern_cache_issues).and_return([ "Low hit rate (45.0%)" ])

        result = cache_monitor.send(:check_pattern_cache_health)

        expect(result[:status]).to eq("degraded")
      end

      it "returns critical status when metrics have errors" do
        allow(cache_monitor).to receive(:pattern_cache_metrics).and_return({
          error: "Connection failed"
        })

        result = cache_monitor.send(:check_pattern_cache_health)

        expect(result[:status]).to eq("critical")
      end
    end
  end

  describe ".check_rails_cache_health" do
    it "returns healthy status when cache is available" do
      allow(cache_monitor).to receive(:test_cache_availability).and_return(true)

      result = cache_monitor.send(:check_rails_cache_health)

      expect(result).to eq({
        status: "healthy",
        available: true
      })
    end

    it "returns critical status when cache is unavailable" do
      allow(cache_monitor).to receive(:test_cache_availability).and_return(false)

      result = cache_monitor.send(:check_rails_cache_health)

      expect(result).to eq({
        status: "critical",
        available: false
      })
    end
  end

  describe ".identify_pattern_cache_issues" do
    it "identifies no issues for healthy metrics" do
      metrics = {
        hit_rate: 90.0,
        memory_entries: 500,
        redis_available: true,
        average_lookup_time_ms: 2.0
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to be_empty
    end

    it "identifies low hit rate issue" do
      metrics = {
        hit_rate: 65.0,
        memory_entries: 500,
        redis_available: true,
        average_lookup_time_ms: 2.0
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to include("Low hit rate (65.0%)")
    end

    it "identifies high memory usage issue" do
      metrics = {
        hit_rate: 90.0,
        memory_entries: 15000,
        redis_available: true,
        average_lookup_time_ms: 2.0
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to include("High memory usage (15000 entries)")
    end

    it "identifies Redis unavailability issue" do
      metrics = {
        hit_rate: 90.0,
        memory_entries: 500,
        redis_available: false,
        average_lookup_time_ms: 2.0
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to include("Redis unavailable")
    end

    it "identifies slow lookup issue" do
      metrics = {
        hit_rate: 90.0,
        memory_entries: 500,
        redis_available: true,
        average_lookup_time_ms: 8.5
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to include("Slow lookups (8.5ms)")
    end

    it "identifies multiple issues simultaneously" do
      metrics = {
        hit_rate: 60.0,
        memory_entries: 12000,
        redis_available: false,
        average_lookup_time_ms: 7.0
      }

      result = cache_monitor.send(:identify_pattern_cache_issues, metrics)

      expect(result).to include("Low hit rate (60.0%)")
      expect(result).to include("High memory usage (12000 entries)")
      expect(result).to include("Redis unavailable")
      expect(result).to include("Slow lookups (7.0ms)")
      expect(result.length).to eq(4)
    end
  end

  describe ".generate_cache_recommendations" do
    it "generates no recommendations for healthy caches" do
      pattern_health = { hit_rate: 90.0, memory_usage: 500 }
      rails_health = { available: true }

      result = cache_monitor.send(:generate_cache_recommendations, pattern_health, rails_health)

      expect(result).to be_empty
    end

    it "generates recommendations for low hit rate" do
      pattern_health = { hit_rate: 70.0, memory_usage: 500 }
      rails_health = { available: true }

      result = cache_monitor.send(:generate_cache_recommendations, pattern_health, rails_health)

      expect(result).to include("Consider increasing cache warming frequency")
      expect(result).to include("Review pattern matching logic for optimization")
    end

    it "generates recommendation for high memory usage" do
      pattern_health = { hit_rate: 90.0, memory_usage: 15000 }
      rails_health = { available: true }

      result = cache_monitor.send(:generate_cache_recommendations, pattern_health, rails_health)

      expect(result).to include("Consider implementing cache eviction for old patterns")
    end

    it "generates critical recommendation for unavailable Rails cache" do
      pattern_health = { hit_rate: 90.0, memory_usage: 500 }
      rails_health = { available: false }

      result = cache_monitor.send(:generate_cache_recommendations, pattern_health, rails_health)

      expect(result).to include("Critical: Rails cache is unavailable - check Redis/Solid Cache configuration")
    end

    it "combines multiple recommendations" do
      pattern_health = { hit_rate: 65.0, memory_usage: 12000 }
      rails_health = { available: false }

      result = cache_monitor.send(:generate_cache_recommendations, pattern_health, rails_health)

      expect(result).to include("Consider increasing cache warming frequency")
      expect(result).to include("Review pattern matching logic for optimization")
      expect(result).to include("Consider implementing cache eviction for old patterns")
      expect(result).to include("Critical: Rails cache is unavailable - check Redis/Solid Cache configuration")
      expect(result.length).to eq(4)
    end
  end

  describe ".calculate_warming_success_rate" do
    it "returns 0 for empty data" do
      result = cache_monitor.send(:calculate_warming_success_rate, [])

      expect(result).to eq(0)
    end

    it "returns 100% for all successful operations" do
      data = [
        { duration: 10.0, patterns: 100 },
        { duration: 12.5, patterns: 120 },
        { duration: 8.3, patterns: 95 }
      ]

      result = cache_monitor.send(:calculate_warming_success_rate, data)

      expect(result).to eq(100.0)
    end

    it "calculates correct percentage for mixed success/failure" do
      data = [
        { duration: 10.0, patterns: 100 },
        { error: "Timeout" },
        { duration: 12.5, patterns: 120 },
        { error: "Connection failed" },
        { duration: 8.3, patterns: 95 }
      ]

      result = cache_monitor.send(:calculate_warming_success_rate, data)

      expect(result).to eq(60.0) # 3 successful out of 5 total
    end

    it "returns 0% for all failed operations" do
      data = [
        { error: "Connection timeout" },
        { error: "Redis unavailable" },
        { error: "Memory error" }
      ]

      result = cache_monitor.send(:calculate_warming_success_rate, data)

      expect(result).to eq(0.0)
    end
  end
end
