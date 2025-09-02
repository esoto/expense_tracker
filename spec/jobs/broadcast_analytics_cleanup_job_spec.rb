# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastAnalyticsCleanupJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:redis_mock) { double('Redis') }
  let(:cache_mock) { double('Cache', redis: redis_mock) }

  before do
    # Mock Rails cache and logger
    allow(Rails).to receive(:cache).and_return(cache_mock)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)

    # Mock FailedBroadcastStore
    allow(FailedBroadcastStore).to receive(:cleanup_old_records).and_return(5)

    # Mock Redis options
    allow(redis_mock).to receive(:options).and_return(namespace: 'test_namespace')
  end

  describe '#perform' do
    context 'when cleanup completes successfully' do
      before do
        # Mock successful cache cleanup
        allow(job).to receive(:cleanup_analytics_cache).and_return(10)
        allow(job).to receive(:record_cleanup_metrics)
      end

      it 'cleans up failed broadcasts and cache entries' do
        result = job.perform

        expect(FailedBroadcastStore).to have_received(:cleanup_old_records).with(older_than: 1.week)
        expect(job).to have_received(:cleanup_analytics_cache)
        expect(job).to have_received(:record_cleanup_metrics)

        expect(result).to eq({
          failed_broadcasts_cleaned: 5,
          cache_keys_cleaned: 10,
          errors: 0
        })
      end

      it 'logs cleanup progress' do
        job.perform

        expect(Rails.logger).to have_received(:info).with('[BROADCAST_ANALYTICS_CLEANUP] Starting cleanup job')
        expect(Rails.logger).to have_received(:info).with('[BROADCAST_ANALYTICS_CLEANUP] Cleaned up 5 old recovered broadcast records')
        expect(Rails.logger).to have_received(:info).with('[BROADCAST_ANALYTICS_CLEANUP] Cleaned up 10 old analytics cache entries')
        expect(Rails.logger).to have_received(:info).with('[BROADCAST_ANALYTICS_CLEANUP] Cleanup completed: 5 records, 10 cache entries cleaned')
      end
    end

    context 'when FailedBroadcastStore cleanup fails' do
      before do
        allow(FailedBroadcastStore).to receive(:cleanup_old_records).and_raise(StandardError, 'Database error')
        allow(job).to receive(:record_cleanup_metrics)
      end

      it 'catches the error, logs it, records metrics, and re-raises' do
        expect { job.perform }.to raise_error(StandardError, 'Database error')

        expect(Rails.logger).to have_received(:error).with('[BROADCAST_ANALYTICS_CLEANUP] Cleanup error: Database error')
        expect(job).to have_received(:record_cleanup_metrics).with({
          failed_broadcasts_cleaned: 0,
          cache_keys_cleaned: 0,
          errors: 1
        })
      end
    end

    context 'when cache cleanup fails' do
      before do
        allow(job).to receive(:cleanup_analytics_cache).and_raise(StandardError, 'Redis error')
        allow(job).to receive(:record_cleanup_metrics)
      end

      it 'catches the error, logs it, records metrics, and re-raises' do
        expect { job.perform }.to raise_error(StandardError, 'Redis error')

        expect(Rails.logger).to have_received(:error).with('[BROADCAST_ANALYTICS_CLEANUP] Cleanup error: Redis error')
        expect(job).to have_received(:record_cleanup_metrics).with({
          failed_broadcasts_cleaned: 5,
          cache_keys_cleaned: 0,
          errors: 1
        })
      end
    end
  end

  describe '#cleanup_analytics_cache' do
    let(:old_keys) do
      [
        'test_namespace:broadcast_analytics:success:2024-01-01-10',
        'test_namespace:broadcast_analytics:failure:2024-01-01-11'
      ]
    end

    let(:recent_keys) do
      [
        "test_namespace:broadcast_analytics:success:#{1.day.ago.strftime('%Y-%m-%d-%H')}",
        "test_namespace:duration_stats:#{Time.current.strftime('%Y-%m-%d-%H')}"
      ]
    end

    context 'with Redis cache store' do
      before do
        allow(cache_mock).to receive(:respond_to?).with(:redis).and_return(true)
        allow(cache_mock).to receive(:delete)

        # Mock different responses for different patterns
        allow(redis_mock).to receive(:keys).with('broadcast_analytics:success:*').and_return(old_keys.select { |k| k.include?('success') })
        allow(redis_mock).to receive(:keys).with('broadcast_analytics:failure:*').and_return(old_keys.select { |k| k.include?('failure') })
        allow(redis_mock).to receive(:keys).with('broadcast_analytics:queued:*').and_return([])
        allow(redis_mock).to receive(:keys).with('duration_stats:*').and_return([])
        allow(redis_mock).to receive(:keys).with('broadcast_analytics:hourly_stats:*').and_return([])
      end

      it 'cleans up old cache entries' do
        result = job.send(:cleanup_analytics_cache)

        expect(cache_mock).to have_received(:delete).with('broadcast_analytics:success:2024-01-01-10')
        expect(cache_mock).to have_received(:delete).with('broadcast_analytics:failure:2024-01-01-11')
        expect(result).to eq(2)
      end

      it 'skips recent cache entries' do
        allow(redis_mock).to receive(:keys).and_return(recent_keys)

        result = job.send(:cleanup_analytics_cache)

        expect(cache_mock).not_to have_received(:delete)
        expect(result).to eq(0)
      end

      context 'when Redis operations fail for a pattern' do
        before do
          allow(redis_mock).to receive(:keys).with('broadcast_analytics:success:*').and_raise(StandardError, 'Redis connection error')
          allow(redis_mock).to receive(:keys).with('broadcast_analytics:failure:*').and_return([])
          allow(redis_mock).to receive(:keys).with('broadcast_analytics:queued:*').and_return([])
          allow(redis_mock).to receive(:keys).with('duration_stats:*').and_return([])
          allow(redis_mock).to receive(:keys).with('broadcast_analytics:hourly_stats:*').and_return([])
        end

        it 'logs the error and continues with other patterns' do
          result = job.send(:cleanup_analytics_cache)

          expect(Rails.logger).to have_received(:warn).with('[BROADCAST_ANALYTICS_CLEANUP] Error cleaning cache pattern broadcast_analytics:success:*: Redis connection error')
          expect(result).to eq(0)
        end
      end
    end

    context 'with non-Redis cache store' do
      before do
        allow(cache_mock).to receive(:respond_to?).with(:redis).and_return(false)
        allow(job).to receive(:cleanup_cache_pattern_fallback).and_return(0)
      end

      it 'uses fallback cleanup method' do
        result = job.send(:cleanup_analytics_cache)

        expect(job).to have_received(:cleanup_cache_pattern_fallback).exactly(5).times
        expect(result).to eq(0)
      end
    end
  end

  describe '#key_is_old?' do
    let(:cutoff_time) { 1.week.ago }

    context 'with valid date patterns' do
      it 'returns true for old keys' do
        old_key = 'broadcast_analytics:success:2024-01-01-10'

        result = job.send(:key_is_old?, old_key, cutoff_time)

        expect(result).to be true
      end

      it 'returns false for recent keys' do
        recent_key = "broadcast_analytics:success:#{Time.current.strftime('%Y-%m-%d-%H')}"

        result = job.send(:key_is_old?, recent_key, cutoff_time)

        expect(result).to be false
      end
    end

    context 'with invalid date patterns' do
      it 'returns false for keys without date patterns' do
        invalid_key = 'broadcast_analytics:success:invalid'

        result = job.send(:key_is_old?, invalid_key, cutoff_time)

        expect(result).to be false
      end

      it 'returns true for keys with unparseable dates' do
        invalid_date_key = 'broadcast_analytics:success:9999-99-99-99'

        result = job.send(:key_is_old?, invalid_date_key, cutoff_time)

        expect(result).to be true
      end
    end
  end

  describe '#cleanup_cache_pattern_fallback' do
    it 'returns 0 for the simplified implementation' do
      result = job.send(:cleanup_cache_pattern_fallback, 'pattern:*', 1.week.ago)

      expect(result).to eq(0)
    end
  end

  describe '#record_cleanup_metrics' do
    let(:stats) do
      {
        failed_broadcasts_cleaned: 5,
        cache_keys_cleaned: 10,
        errors: 0
      }
    end

    before do
      allow(cache_mock).to receive(:write)
      allow(Time).to receive(:current).and_return(Time.zone.parse('2025-08-30 12:00:00'))
    end

    it 'writes cleanup metrics to cache' do
      job.send(:record_cleanup_metrics, stats)

      expect(cache_mock).to have_received(:write).with(
        'broadcast_analytics:cleanup:last_run',
        {
          timestamp: '2025-08-30T12:00:00Z',
          stats: stats
        },
        expires_in: 24.hours
      )
    end
  end

  describe 'job configuration' do
    it 'is configured to use low priority queue' do
      expect(described_class.queue_name).to eq('low')
    end
  end
end
