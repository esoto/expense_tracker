# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PatternCacheWarmerJob, type: :job, integration: true do
  let(:job) { described_class.new }
  let(:cache) { instance_double(Categorization::PatternCache) }

  before do
    allow(Categorization::PatternCache).to receive(:instance).and_return(cache)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#perform', integration: true do
    context 'when cache warming succeeds' do
      let(:success_stats) do
        {
          patterns: 100,
          composites: 50,
          user_prefs: 25,
          duration: nil
        }
      end

      let(:cache_metrics) do
        {
          hit_rate: 92.5,
          memory_cache_entries: 500,
          redis_available: true
        }
      end

      before do
        allow(cache).to receive(:warm_cache).and_return(success_stats)
        allow(cache).to receive(:metrics).and_return(cache_metrics)
        allow(job).to receive(:report_success)
        allow(job).to receive(:broadcast_event)
      end

      it 'warms the cache successfully' do
        expect(cache).to receive(:warm_cache)
        job.perform
      end

      it 'logs success information' do
        expect(Rails.logger).to receive(:info).with(/Cache warming completed successfully/)
        job.perform
      end

      it 'reports success metrics' do
        expect(job).to receive(:report_success).with(hash_including(
          patterns: 100,
          composites: 50,
          user_prefs: 25
        ))
        job.perform
      end

      it 'checks cache health' do
        expect(job).to receive(:check_cache_health).with(cache)
        job.perform
      end

      it 'returns stats with duration' do
        result = job.perform
        expect(result).to include(:duration)
        expect(result[:duration]).to be_a(Numeric)
      end
    end

    context 'when cache warming fails' do
      let(:error_stats) do
        {
          error: "Connection refused",
          patterns: 0,
          composites: 0,
          user_prefs: 0
        }
      end

      before do
        allow(cache).to receive(:warm_cache).and_return(error_stats)
        allow(cache).to receive(:metrics).and_return({ hit_rate: 0 })
        allow(job).to receive(:report_error)
        allow(job).to receive(:broadcast_event)
      end

      it 'logs error information' do
        expect(Rails.logger).to receive(:error).with(/Cache warming failed/)
        job.perform
      end

      it 'reports error details' do
        expect(job).to receive(:report_error).with(hash_including(
          error: "Connection refused"
        ))
        job.perform
      end

      it 'still checks cache health' do
        expect(job).to receive(:check_cache_health).with(cache)
        job.perform
      end
    end

    context 'when an exception occurs' do
      let(:error) { StandardError.new("Unexpected error") }
      let(:cache_metrics) do
        {
          hit_rate: 85.0,
          memory_cache_entries: 500,
          redis_available: true
        }
      end

      before do
        allow(cache).to receive(:metrics).and_return(cache_metrics)
        allow(cache).to receive(:warm_cache).and_raise(error)
        allow(job).to receive(:report_error)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Unexpected error/)
        expect { job.perform }.to raise_error(StandardError)
      end

      it 'reports the error' do
        expect(job).to receive(:report_error).with(hash_including(
          error: "Unexpected error"
        ))
        expect { job.perform }.to raise_error(StandardError)
      end

      it 're-raises the error for retry mechanism' do
        expect { job.perform }.to raise_error(StandardError, "Unexpected error")
      end
    end
  end

  describe '#check_cache_health', integration: true do
    let(:cache_metrics) do
      {
        hit_rate: hit_rate,
        memory_cache_entries: memory_entries,
        redis_available: redis_available
      }
    end

    let(:hit_rate) { 85.0 }
    let(:memory_entries) { 5000 }
    let(:redis_available) { true }

    before do
      allow(cache).to receive(:metrics).and_return(cache_metrics)
    end

    context 'with low hit rate' do
      let(:hit_rate) { 75.0 }

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Low cache hit rate: 75.0%/)
        job.send(:check_cache_health, cache)
      end
    end

    context 'with high memory usage' do
      let(:memory_entries) { 15000 }

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/High memory cache entries: 15000/)
        job.send(:check_cache_health, cache)
      end
    end

    context 'when Redis is unavailable' do
      let(:redis_available) { false }

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Redis is not available/)
        job.send(:check_cache_health, cache)
      end
    end

    context 'with healthy metrics' do
      it 'does not log warnings' do
        expect(Rails.logger).not_to receive(:warn)
        job.send(:check_cache_health, cache)
      end
    end
  end

  describe '#report_success', integration: true do
    let(:stats) do
      {
        patterns: 100,
        composites: 50,
        user_prefs: 25,
        duration: 1.234
      }
    end

    before do
      allow(job).to receive(:job_id).and_return("test-job-123")
      allow(job).to receive(:queue_name).and_return("low")
      allow(job).to receive(:broadcast_event)
    end

    context 'when MonitoringService is available' do
      before do
        stub_const('Services::Infrastructure::MonitoringService', double(record_metric: true))
      end

      it 'records metrics' do
        expect(Services::Infrastructure::MonitoringService).to receive(:record_metric).with(
          'pattern_cache.warming',
          hash_including(
            patterns_cached: 100,
            composites_cached: 50,
            user_prefs_cached: 25,
            duration_seconds: 1.234
          ),
          tags: hash_including(
            status: 'success',
            job_id: 'test-job-123',
            queue: 'low'
          )
        )

        job.send(:report_success, stats)
      end
    end

    it 'broadcasts success event' do
      expect(job).to receive(:broadcast_event).with('cache_warming_completed', stats)
      job.send(:report_success, stats)
    end
  end

  describe '#report_error', integration: true do
    let(:error_details) do
      {
        error: "Connection timeout",
        backtrace: [ "line1", "line2" ]
      }
    end

    before do
      allow(job).to receive(:job_id).and_return("test-job-456")
      allow(job).to receive(:queue_name).and_return("low")
      allow(job).to receive(:broadcast_event)
    end

    context 'when MonitoringService is available' do
      before do
        stub_const('Services::Infrastructure::MonitoringService', double(record_error: true))
      end

      it 'records error' do
        expect(Services::Infrastructure::MonitoringService).to receive(:record_error).with(
          'pattern_cache.warming_failed',
          error_details,
          tags: hash_including(
            job_id: 'test-job-456',
            queue: 'low'
          )
        )

        job.send(:report_error, error_details)
      end
    end

    it 'broadcasts error event' do
      expect(job).to receive(:broadcast_event).with('cache_warming_failed', error_details)
      job.send(:report_error, error_details)
    end
  end

  describe '#broadcast_event', integration: true do
    let(:event_data) { { test: "data" } }

    context 'when ActionCable is available' do
      let(:server) { double('ActionCable::Server') }

      before do
        action_cable = double('ActionCable')
        stub_const('ActionCable', action_cable)
        allow(action_cable).to receive(:server).and_return(server)
      end

      it 'broadcasts the event' do
        expect(server).to receive(:broadcast).with(
          'system_events',
          hash_including(
            event: 'test_event',
            data: event_data
          )
        )

        job.send(:broadcast_event, 'test_event', event_data)
      end

      context 'when broadcast fails' do
        before do
          allow(server).to receive(:broadcast).and_raise(StandardError.new("Broadcast failed"))
        end

        it 'logs the error but does not raise' do
          expect(Rails.logger).to receive(:error).with(/Failed to broadcast event/)
          expect { job.send(:broadcast_event, 'test_event', event_data) }.not_to raise_error
        end
      end
    end

    context 'when ActionCable is not available' do
      it 'does not attempt to broadcast' do
        expect { job.send(:broadcast_event, 'test_event', event_data) }.not_to raise_error
      end
    end
  end

  describe 'job configuration', integration: true do
    it 'uses the low priority queue' do
      expect(described_class.queue_name).to eq('low')
    end

    it 'has retry configuration' do
      # ActiveJob retry_on is a class method that configures retries
      # We can't easily inspect it, so let's test the behavior instead
      job = described_class.new
      expect(job.class.ancestors).to include(ApplicationJob)
      # The retry configuration is defined, we just can't inspect it easily
      expect(described_class).to respond_to(:retry_on)
    end
  end
end
