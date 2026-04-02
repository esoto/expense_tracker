# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastAnalyticsCleanupJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:cache_mock) { double('Cache') }

  before do
    # Mock Rails cache and logger
    allow(Rails).to receive(:cache).and_return(cache_mock)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)

    # Mock FailedBroadcastStore
    allow(FailedBroadcastStore).to receive(:cleanup_old_records).and_return(5)
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
        allow(job).to receive(:cleanup_analytics_cache).and_raise(StandardError, 'Cache error')
        allow(job).to receive(:record_cleanup_metrics)
      end

      it 'catches the error, logs it, records metrics, and re-raises' do
        expect { job.perform }.to raise_error(StandardError, 'Cache error')

        expect(Rails.logger).to have_received(:error).with('[BROADCAST_ANALYTICS_CLEANUP] Cleanup error: Cache error')
        expect(job).to have_received(:record_cleanup_metrics).with({
          failed_broadcasts_cleaned: 5,
          cache_keys_cleaned: 0,
          errors: 1
        })
      end
    end
  end

  describe '#cleanup_analytics_cache' do
    before do
      allow(job).to receive(:cleanup_cache_pattern_fallback).and_return(0)
    end

    it 'uses fallback cleanup for all patterns' do
      result = job.send(:cleanup_analytics_cache)

      expect(job).to have_received(:cleanup_cache_pattern_fallback).exactly(5).times
      expect(result).to eq(0)
    end

    context 'when cleanup fails for a pattern' do
      before do
        call_count = 0
        allow(job).to receive(:cleanup_cache_pattern_fallback) do
          call_count += 1
          raise StandardError, 'Cache error' if call_count == 1
          0
        end
      end

      it 'logs the error and continues with other patterns' do
        result = job.send(:cleanup_analytics_cache)

        expect(Rails.logger).to have_received(:warn).with(match(/Error cleaning cache pattern.*Cache error/))
        expect(result).to eq(0)
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
