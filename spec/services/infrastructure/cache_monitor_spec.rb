# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/infrastructure/monitoring_service'

RSpec.describe Infrastructure::MonitoringService::CacheMonitor do
  describe '.metrics' do
    it 'returns comprehensive cache metrics' do
      metrics = described_class.metrics

      expect(metrics).to include(
        :pattern_cache,
        :rails_cache,
        :performance,
        :health
      )
    end
  end

  describe '.pattern_cache_metrics' do
    context 'when PatternCache is available' do
      let(:pattern_cache) { double('PatternCache') }
      let(:cache_metrics) do
        {
          hit_rate: 85.5,
          hits: 1000,
          misses: 170,
          memory_cache_entries: 500,
          redis_available: true,
          average_lookup_time_ms: 0.8
        }
      end

      before do
        allow(Categorization::PatternCache).to receive(:instance).and_return(pattern_cache)
        allow(pattern_cache).to receive(:metrics).and_return(cache_metrics)
        allow(described_class).to receive(:warmup_status).and_return({ status: "recent" })
      end

      it 'returns pattern cache metrics' do
        metrics = described_class.pattern_cache_metrics

        expect(metrics).to include(
          hit_rate: 85.5,
          total_hits: 1000,
          total_misses: 170,
          memory_entries: 500,
          redis_available: true,
          average_lookup_time_ms: 0.8,
          warmup_status: { status: "recent" }
        )
      end
    end

    context 'when PatternCache is not available' do
      before do
        # Stub the module method to simulate PatternCache not being defined
        stub_const("Categorization::PatternCache", nil)
        hide_const("Categorization::PatternCache")
      end

      it 'returns empty hash' do
        expect(described_class.pattern_cache_metrics).to eq({})
      end
    end

    context 'when fetching metrics fails' do
      before do
        allow(Categorization::PatternCache).to receive(:instance).and_raise(StandardError.new("Connection error"))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns error information' do
        metrics = described_class.pattern_cache_metrics
        expect(metrics).to eq({ error: "Connection error" })
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Failed to get pattern cache metrics/)
        described_class.pattern_cache_metrics
      end
    end
  end

  describe '.rails_cache_metrics' do
    context 'when cache supports stats' do
      let(:cache_stats) { { hits: 5000, misses: 500, hit_rate: 90.9 } }
      let(:cache_with_stats) { double('CacheWithStats') }

      before do
        allow(Rails).to receive(:cache).and_return(cache_with_stats)
        allow(cache_with_stats).to receive(:respond_to?).with(:stats).and_return(true)
        allow(cache_with_stats).to receive(:stats).and_return(cache_stats)
      end

      it 'returns cache stats' do
        expect(described_class.rails_cache_metrics).to eq(cache_stats)
      end
    end

    context 'when cache does not support stats' do
      let(:basic_cache) { double('BasicCache') }

      before do
        allow(Rails).to receive(:cache).and_return(basic_cache)
        allow(basic_cache).to receive(:respond_to?).with(:stats).and_return(false)
        allow(basic_cache.class).to receive(:name).and_return("ActiveSupport::Cache::MemoryStore")
        allow(basic_cache).to receive(:write).with(anything, anything, anything).and_return(true)
      end

      it 'returns basic information' do
        metrics = described_class.rails_cache_metrics

        expect(metrics).to include(
          type: "ActiveSupport::Cache::MemoryStore",
          available: true
        )
      end
    end
  end

  describe '.cache_performance_metrics' do
    context 'with performance data available' do
      before do
        # Mock recent performance data
        allow(Rails.cache).to receive(:read).and_return(nil)
        allow(Rails.cache).to receive(:read)
          .with("performance_metrics:pattern_cache:warming:#{Date.current}")
          .and_return({
            duration: 2.5,
            patterns: 100,
            timestamp: Time.current
          })
      end

      it 'calculates performance metrics' do
        metrics = described_class.cache_performance_metrics

        expect(metrics).to include(
          :average_warming_duration_seconds,
          :average_patterns_warmed,
          :warming_success_rate
        )
      end
    end

    context 'with no performance data' do
      before do
        allow(Rails.cache).to receive(:read).and_return(nil)
      end

      it 'returns empty hash' do
        expect(described_class.cache_performance_metrics).to eq({})
      end
    end
  end

  describe '.cache_health_status' do
    let(:pattern_cache) { double('PatternCache') }

    before do
      allow(Categorization::PatternCache).to receive(:instance).and_return(pattern_cache)
      allow(pattern_cache).to receive(:metrics).and_return({
        hit_rate: 92,
        memory_cache_entries: 500,
        redis_available: true
      })
      allow(Rails.cache).to receive(:write).and_return(true)
    end

    it 'returns overall health status' do
      health = described_class.cache_health_status

      expect(health).to include(
        overall: "healthy",
        pattern_cache: hash_including(:status, :hit_rate, :memory_usage),
        rails_cache: hash_including(:status, :available),
        recommendations: an_instance_of(Array)
      )
    end

    context 'with degraded performance' do
      before do
        allow(pattern_cache).to receive(:metrics).and_return({
          hit_rate: 65,
          memory_cache_entries: 15000,
          redis_available: false
        })
      end

      it 'identifies issues and provides recommendations' do
        health = described_class.cache_health_status

        expect(health[:overall]).to eq("degraded")
        expect(health[:pattern_cache][:issues]).to include(
          "Low hit rate (65%)",
          "High memory usage (15000 entries)",
          "Redis unavailable"
        )
        expect(health[:recommendations]).not_to be_empty
      end
    end
  end

  describe 'private methods' do
    describe '#warmup_status' do
      context 'when warmup was run recently' do
        before do
          allow(Rails.cache).to receive(:read)
            .with("pattern_cache:last_warmup")
            .and_return({
              timestamp: 10.minutes.ago
            })
        end

        it 'returns recent status' do
          status = described_class.send(:warmup_status)

          expect(status).to include(
            status: "recent",
            minutes_ago: be_within(1).of(10)
          )
        end
      end

      context 'when warmup is stale' do
        before do
          allow(Rails.cache).to receive(:read)
            .with("pattern_cache:last_warmup")
            .and_return({
              timestamp: 45.minutes.ago
            })
        end

        it 'returns stale status' do
          status = described_class.send(:warmup_status)
          expect(status[:status]).to eq("stale")
        end
      end

      context 'when warmup is outdated' do
        before do
          allow(Rails.cache).to receive(:read)
            .with("pattern_cache:last_warmup")
            .and_return({
              timestamp: 2.hours.ago
            })
        end

        it 'returns outdated status' do
          status = described_class.send(:warmup_status)
          expect(status[:status]).to eq("outdated")
        end
      end

      context 'when warmup was never run' do
        before do
          allow(Rails.cache).to receive(:read)
            .with("pattern_cache:last_warmup")
            .and_return(nil)
        end

        it 'returns never_run status' do
          status = described_class.send(:warmup_status)
          expect(status).to eq({ status: "never_run" })
        end
      end
    end

    describe '#test_cache_availability' do
      context 'when cache is available' do
        before do
          allow(Rails.cache).to receive(:write).and_return(true)
        end

        it 'returns true' do
          expect(described_class.send(:test_cache_availability)).to be true
        end
      end

      context 'when cache is unavailable' do
        before do
          allow(Rails.cache).to receive(:write).and_raise(StandardError)
        end

        it 'returns false' do
          expect(described_class.send(:test_cache_availability)).to be false
        end
      end
    end
  end
end
