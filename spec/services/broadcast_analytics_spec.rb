# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastAnalytics, type: :service do
  include ActiveSupport::Testing::TimeHelpers
  let(:channel_name) { 'SyncStatusChannel' }
  let(:target_type) { 'SyncSession' }
  let(:target_id) { 123 }
  let(:priority) { :medium }

  before do
    # Clear cache before each test
    Rails.cache.clear
    
    # Stub RedisAnalyticsService to ensure fallback to Rails.cache
    allow(RedisAnalyticsService).to receive(:increment_counter).and_raise(StandardError, "Redis not available")
    allow(RedisAnalyticsService).to receive(:record_timing).and_raise(StandardError, "Redis not available")
  end

  describe '.record_success' do
    it 'records successful broadcast event' do
      freeze_time do
        described_class.record_success(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 1,
          duration: 0.045
        )

        # Check that counters were incremented
        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        success_count_key = "#{described_class::CACHE_KEYS[:success]}:count:#{hour_key}"
        channel_count_key = "#{described_class::CACHE_KEYS[:success]}:#{channel_name}:#{hour_key}"
        priority_count_key = "#{described_class::CACHE_KEYS[:success]}:#{priority}:#{hour_key}"

        expect(Rails.cache.read(success_count_key)).to eq(1)
        expect(Rails.cache.read(channel_count_key)).to eq(1)
        expect(Rails.cache.read(priority_count_key)).to eq(1)
      end
    end

    it 'updates duration statistics' do
      freeze_time do
        described_class.record_success(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 1,
          duration: 0.123
        )

        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        duration_key = "duration_stats:#{channel_name}:#{hour_key}"
        stats = Rails.cache.read(duration_key)

        expect(stats).to include(
          count: 1,
          sum: 0.123,
          min: 0.123,
          max: 0.123
        )
      end
    end

    it 'updates hourly statistics' do
      freeze_time do
        described_class.record_success(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 1,
          duration: 0.045
        )

        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        hourly_stats_key = "#{described_class::CACHE_KEYS[:hourly_stats]}:#{hour_key}"
        stats = Rails.cache.read(hourly_stats_key)

        expect(stats).to include(success: 1)
      end
    end

    it 'stores individual event data' do
      freeze_time do
        timestamp = Time.current
        described_class.record_success(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 2,
          duration: 0.067
        )

        # Individual event should be stored with timestamp as key
        event_key = "#{described_class::CACHE_KEYS[:success]}:events:#{timestamp.to_f}"
        event_data = Rails.cache.read(event_key)

        expect(event_data).to include(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority.to_s,
          attempt: 2,
          duration: 0.067,
          timestamp: timestamp.to_f,
          hour: timestamp.hour,
          date: timestamp.to_date.to_s
        )
      end
    end

    it 'logs structured success event' do
      allow(Rails.logger).to receive(:info)

      described_class.record_success(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 1,
        duration: 0.045
      )

      expect(Rails.logger).to have_received(:info).with(
        match(/BROADCAST_ANALYTICS.*Success.*SyncStatusChannel.*SyncSession#123.*Priority: medium.*Attempt: 1.*Duration: 0\.045s/)
      )
    end
  end

  describe '.record_failure' do
    let(:error_message) { 'Connection timeout' }

    it 'records failed broadcast event' do
      freeze_time do
        described_class.record_failure(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 2,
          error: error_message,
          duration: 0.025
        )

        # Check that failure counters were incremented
        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        failure_count_key = "#{described_class::CACHE_KEYS[:failure]}:count:#{hour_key}"
        channel_failure_key = "#{described_class::CACHE_KEYS[:failure]}:#{channel_name}:#{hour_key}"
        attempt_key = "#{described_class::CACHE_KEYS[:failure]}:attempt_2:#{hour_key}"

        expect(Rails.cache.read(failure_count_key)).to eq(1)
        expect(Rails.cache.read(channel_failure_key)).to eq(1)
        expect(Rails.cache.read(attempt_key)).to eq(1)
      end
    end

    it 'stores failure event with error details' do
      freeze_time do
        timestamp = Time.current
        described_class.record_failure(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority,
          attempt: 2,
          error: error_message,
          duration: 0.025
        )

        event_key = "#{described_class::CACHE_KEYS[:failure]}:events:#{timestamp.to_f}"
        event_data = Rails.cache.read(event_key)

        expect(event_data).to include(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority.to_s,
          attempt: 2,
          error: error_message,
          duration: 0.025,
          timestamp: timestamp.to_f
        )
      end
    end

    it 'logs structured failure event' do
      allow(Rails.logger).to receive(:warn)

      described_class.record_failure(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority,
        attempt: 2,
        error: error_message,
        duration: 0.025
      )

      expect(Rails.logger).to have_received(:warn).with(
        match(/BROADCAST_ANALYTICS.*Failure.*SyncStatusChannel.*SyncSession#123.*Priority: medium.*Attempt: 2.*Error: Connection timeout.*Duration: 0\.025s/)
      )
    end
  end

  describe '.record_queued' do
    it 'records queued broadcast event' do
      freeze_time do
        described_class.record_queued(
          channel: channel_name,
          target_type: target_type,
          target_id: target_id,
          priority: priority
        )

        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        queued_count_key = "#{described_class::CACHE_KEYS[:queued]}:count:#{hour_key}"
        channel_queued_key = "#{described_class::CACHE_KEYS[:queued]}:#{channel_name}:#{hour_key}"

        expect(Rails.cache.read(queued_count_key)).to eq(1)
        expect(Rails.cache.read(channel_queued_key)).to eq(1)
      end
    end

    it 'logs queued event' do
      allow(Rails.logger).to receive(:debug)

      described_class.record_queued(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: priority
      )

      expect(Rails.logger).to have_received(:debug).with(
        match(/BROADCAST_ANALYTICS.*Queued.*SyncStatusChannel.*SyncSession#123.*Priority: medium/)
      )
    end
  end

  describe '.get_metrics' do
    before do
      freeze_time do
        # Record some test data
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id + 1,
          priority: priority, attempt: 1, duration: 0.2
        )
        described_class.record_failure(
          channel: channel_name, target_type: target_type, target_id: target_id + 2,
          priority: priority, attempt: 1, error: 'Test error', duration: 0.05
        )
        described_class.record_queued(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority
        )
      end
    end

    it 'calculates metrics for given time window' do
      metrics = described_class.get_metrics(time_window: 1.hour)

      expect(metrics).to include(
        success_count: 2,
        failure_count: 1,
        queued_count: 1,
        total_events: 3,
        success_rate: 66.67,
        failure_rate: 33.33
      )
    end

    it 'caches metrics to avoid recalculation' do
      # First call should calculate
      expect(described_class).to receive(:calculate_metrics).and_call_original
      first_result = described_class.get_metrics(time_window: 1.hour)

      # Second call should use cache
      expect(described_class).not_to receive(:calculate_metrics)
      second_result = described_class.get_metrics(time_window: 1.hour)

      expect(first_result).to eq(second_result)
    end

    it 'handles zero events gracefully' do
      Rails.cache.clear
      
      metrics = described_class.get_metrics(time_window: 1.hour)

      expect(metrics).to include(
        success_count: 0,
        failure_count: 0,
        total_events: 0,
        success_rate: 0,
        failure_rate: 0
      )
    end
  end

  describe '.get_channel_metrics' do
    before do
      freeze_time do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.15
        )
        described_class.record_failure(
          channel: channel_name, target_type: target_type, target_id: target_id + 1,
          priority: priority, attempt: 1, error: 'Test error', duration: 0.25
        )
      end
    end

    it 'returns channel-specific metrics' do
      metrics = described_class.get_channel_metrics(channel_name, time_window: 1.hour)

      expect(metrics).to include(
        channel: channel_name,
        success_count: 1,
        failure_count: 1
      )
    end

    it 'caches channel metrics' do
      expect(described_class).to receive(:calculate_channel_metrics).and_call_original
      first_result = described_class.get_channel_metrics(channel_name, time_window: 1.hour)

      expect(described_class).not_to receive(:calculate_channel_metrics)
      second_result = described_class.get_channel_metrics(channel_name, time_window: 1.hour)

      expect(first_result).to eq(second_result)
    end
  end

  describe '.get_dashboard_metrics' do
    it 'returns comprehensive dashboard data' do
      dashboard_metrics = described_class.get_dashboard_metrics

      expect(dashboard_metrics).to include(
        :current,
        :trend,
        :channels,
        :priorities,
        :recent_failures
      )

      expect(dashboard_metrics[:current]).to include(
        :success_rate,
        :failure_rate,
        :average_duration,
        :total_broadcasts
      )

      expect(dashboard_metrics[:trend]).to include(
        :success_rate_24h,
        :failure_rate_24h,
        :average_duration_24h,
        :total_broadcasts_24h
      )
    end
  end

  describe 'counter incrementation' do
    it 'handles multiple increments for same hour' do
      freeze_time do
        3.times do
          described_class.record_success(
            channel: channel_name, target_type: target_type, target_id: target_id,
            priority: priority, attempt: 1, duration: 0.1
          )
        end

        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        success_count_key = "#{described_class::CACHE_KEYS[:success]}:count:#{hour_key}"

        expect(Rails.cache.read(success_count_key)).to eq(3)
      end
    end

    it 'creates separate counters for different hours' do
      # Record success in current hour
      freeze_time do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )

        current_hour_key = "#{described_class::CACHE_KEYS[:success]}:count:#{Time.current.strftime('%Y-%m-%d-%H')}"
        expect(Rails.cache.read(current_hour_key)).to eq(1)
      end

      # Record success in next hour
      travel(1.hour) do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )

        next_hour_key = "#{described_class::CACHE_KEYS[:success]}:count:#{Time.current.strftime('%Y-%m-%d-%H')}"
        expect(Rails.cache.read(next_hour_key)).to eq(1)
      end
    end
  end

  describe 'duration statistics' do
    it 'tracks min, max, sum, and count for durations' do
      freeze_time do
        # Record multiple durations
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id + 1,
          priority: priority, attempt: 1, duration: 0.3
        )
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id + 2,
          priority: priority, attempt: 1, duration: 0.2
        )

        hour_key = Time.current.strftime('%Y-%m-%d-%H')
        duration_key = "duration_stats:#{channel_name}:#{hour_key}"
        stats = Rails.cache.read(duration_key)

        expect(stats).to include(
          count: 3,
          min: 0.1,
          max: 0.3
        )
        expect(stats[:sum]).to be_within(0.0001).of(0.6)
      end
    end
  end

  describe 'time window calculations' do
    before do
      # Clear any existing cache data
      Rails.cache.clear
      
      # Setup data across different time periods
      baseline_time = Time.current
      
      # Record event at baseline time
      travel_to(baseline_time) do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )
      end

      # Record event 1 hour in the future from baseline
      travel_to(baseline_time + 1.hour) do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id + 1,
          priority: priority, attempt: 1, duration: 0.2
        )
      end

      # Record event 25 hours in the future from baseline (outside 24-hour window)
      travel_to(baseline_time + 25.hours) do
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id + 2,
          priority: priority, attempt: 1, duration: 0.3
        )
      end
    end

    it 'includes events within time window' do
      baseline_time = Time.current
      travel_to(baseline_time + 2.hours) do
        metrics = described_class.get_metrics(time_window: 3.hours)
        expect(metrics[:success_count]).to eq(2) # Should include both events within 3 hours
      end
    end

    it 'excludes events outside time window' do
      baseline_time = Time.current
      travel_to(baseline_time + 3.hours) do
        metrics = described_class.get_metrics(time_window: 1.hour)
        expect(metrics[:success_count]).to eq(0) # No events in last hour (all events are 2+ hours old)
      end
    end
  end

  describe 'error handling' do
    it 'handles cache errors gracefully' do
      allow(Rails.cache).to receive(:write).and_raise(StandardError, 'Cache error')
      
      expect {
        described_class.record_success(
          channel: channel_name, target_type: target_type, target_id: target_id,
          priority: priority, attempt: 1, duration: 0.1
        )
      }.not_to raise_error
    end

    it 'handles missing cache data gracefully' do
      # Clear cache to simulate missing data
      Rails.cache.clear
      
      metrics = described_class.get_metrics(time_window: 1.hour)
      
      expect(metrics).to include(
        success_count: 0,
        failure_count: 0,
        total_events: 0
      )
    end
  end

  describe '.cleanup_old_data' do
    it 'logs cleanup completion' do
      allow(Rails.logger).to receive(:info)
      
      described_class.cleanup_old_data(older_than: 1.week)
      
      expect(Rails.logger).to have_received(:info).with(
        match(/BROADCAST_ANALYTICS.*Cleanup completed for data older than/)
      )
    end
  end
end