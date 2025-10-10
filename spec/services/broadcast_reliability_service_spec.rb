# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::BroadcastReliabilityService, type: :service, integration: true do
  let(:sync_session) { create(:sync_session) }
  let(:test_data) { { status: 'processing', processed: 10, total: 100 } }

  before do
    # Clear analytics before each test
    allow(BroadcastAnalytics).to receive(:record_success)
    allow(BroadcastAnalytics).to receive(:record_failure)
    allow(BroadcastAnalytics).to receive(:record_queued)

    # Disable security validation by default for tests (individual tests can override)
    allow(BroadcastFeatureFlags).to receive(:enabled?)
      .with(:broadcast_validation)
      .and_return(false)
    allow(BroadcastFeatureFlags).to receive(:enabled?)
      .with(:enhanced_rate_limiting)
      .and_return(false)

    # Mock sleep to prevent actual delays in tests
    allow(Kernel).to receive(:sleep)
  end

  describe '.broadcast_with_retry', integration: true do
    context 'when broadcast succeeds on first attempt' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to).with(sync_session, test_data)
      end

      it 'broadcasts successfully and records success' do
        result = described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be true
        expect(SyncStatusChannel).to have_received(:broadcast_to).with(sync_session, test_data)
        expect(BroadcastAnalytics).to have_received(:record_success).with(
          channel: 'SyncStatusChannel',
          target_type: 'SyncSession',
          target_id: sync_session.id,
          priority: :medium,
          attempt: 1,
          duration: be_a(Float)
        )
      end
    end

    context 'when broadcast fails but succeeds on retry' do
      before do
        call_count = 0
        allow(SyncStatusChannel).to receive(:broadcast_to) do |target, data|
          call_count += 1
          if call_count == 1
            raise StandardError, "Connection timeout"
          end
          # Success on second attempt
        end
      end

      it 'retries and eventually succeeds' do
        result = described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be true
        expect(SyncStatusChannel).to have_received(:broadcast_to).twice

        # Should record failure for first attempt
        expect(BroadcastAnalytics).to have_received(:record_failure).with(
          channel: 'SyncStatusChannel',
          target_type: 'SyncSession',
          target_id: sync_session.id,
          priority: :medium,
          attempt: 1,
          error: "Broadcast failed: Connection timeout",
          duration: be_a(Float)
        )

        # Should record success for second attempt
        expect(BroadcastAnalytics).to have_received(:record_success).with(
          channel: 'SyncStatusChannel',
          target_type: 'SyncSession',
          target_id: sync_session.id,
          priority: :medium,
          attempt: 2,
          duration: be_a(Float)
        )
      end
    end

    context 'when broadcast fails all retry attempts' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to).and_raise(StandardError, "Persistent failure")
        allow(BroadcastErrorHandler).to receive(:handle_final_failure)
      end

      it 'exhausts retries and handles final failure' do
        result = described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be false

        # Should attempt the maximum number of retries for medium priority (3)
        expect(SyncStatusChannel).to have_received(:broadcast_to).exactly(3).times

        # Should record failures for all attempts
        expect(BroadcastAnalytics).to have_received(:record_failure).exactly(3).times

        # Should handle final failure
        expect(BroadcastErrorHandler).to have_received(:handle_final_failure).with(
          SyncStatusChannel, sync_session, test_data, :medium, be_a(StandardError)
        )
      end
    end

    context 'with different priority levels' do
      it 'uses correct retry counts for critical priority' do
        allow(SyncStatusChannel).to receive(:broadcast_to).and_raise(StandardError, "Always fails")
        allow(BroadcastErrorHandler).to receive(:handle_final_failure)

        described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :critical
        )

        # Critical priority should have 5 retry attempts
        expect(SyncStatusChannel).to have_received(:broadcast_to).exactly(5).times
      end

      it 'uses correct retry counts for low priority' do
        allow(SyncStatusChannel).to receive(:broadcast_to).and_raise(StandardError, "Always fails")
        allow(BroadcastErrorHandler).to receive(:handle_final_failure)

        described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :low
        )

        # Low priority should have 2 retry attempts
        expect(SyncStatusChannel).to have_received(:broadcast_to).exactly(2).times
      end
    end

    context 'with invalid priority' do
      it 'raises InvalidPriorityError' do
        expect {
          result = described_class.broadcast_with_retry(
            channel: SyncStatusChannel,
            target: sync_session,
            data: test_data,
            priority: :invalid
          )
          puts "UNEXPECTED: Got result: #{result.inspect}" if result
        }.to raise_error(BroadcastReliabilityService::InvalidPriorityError)
      end
    end

    context 'with string channel name' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to).with(sync_session, test_data)
      end

      it 'converts string to class and broadcasts' do
        result = described_class.broadcast_with_retry(
          channel: 'SyncStatusChannel',
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be true
        expect(SyncStatusChannel).to have_received(:broadcast_to).with(sync_session, test_data)
      end
    end
  end

  describe '.queue_broadcast', integration: true do
    let(:broadcast_job_double) { double('BroadcastJob') }

    before do
      allow(BroadcastJob).to receive(:enqueue_broadcast)
    end

    it 'enqueues broadcast job with correct parameters' do
      described_class.queue_broadcast(
        channel: 'SyncStatusChannel',
        target_id: sync_session.id,
        target_type: 'SyncSession',
        data: test_data,
        priority: :high
      )

      expect(BroadcastJob).to have_received(:enqueue_broadcast).with(
        channel_name: 'SyncStatusChannel',
        target_id: sync_session.id,
        target_type: 'SyncSession',
        data: test_data,
        priority: :high
      )
    end

    it 'uses default priority when not specified' do
      described_class.queue_broadcast(
        channel: 'SyncStatusChannel',
        target_id: sync_session.id,
        target_type: 'SyncSession',
        data: test_data
      )

      expect(BroadcastJob).to have_received(:enqueue_broadcast).with(
        channel_name: 'SyncStatusChannel',
        target_id: sync_session.id,
        target_type: 'SyncSession',
        data: test_data,
        priority: :medium
      )
    end

    it 'validates priority before queuing' do
      expect {
        described_class.queue_broadcast(
          channel: 'SyncStatusChannel',
          target_id: sync_session.id,
          target_type: 'SyncSession',
          data: test_data,
          priority: :invalid
        )
      }.to raise_error(BroadcastReliabilityService::InvalidPriorityError)
    end
  end

  describe '.priority_config', integration: true do
    it 'returns correct configuration for each priority level' do
      critical_config = described_class.priority_config(:critical)
      expect(critical_config).to include(
        max_retries: 5,
        backoff_base: 0.5,
        queue: 'critical'
      )

      high_config = described_class.priority_config(:high)
      expect(high_config).to include(
        max_retries: 4,
        backoff_base: 1.0,
        queue: 'high'
      )

      medium_config = described_class.priority_config(:medium)
      expect(medium_config).to include(
        max_retries: 3,
        backoff_base: 2.0,
        queue: 'default'
      )

      low_config = described_class.priority_config(:low)
      expect(low_config).to include(
        max_retries: 2,
        backoff_base: 4.0,
        queue: 'low'
      )
    end

    it 'raises error for invalid priority' do
      expect {
        described_class.priority_config(:invalid)
      }.to raise_error(BroadcastReliabilityService::InvalidPriorityError)
    end
  end

  describe 'exponential backoff', integration: true do
    let(:service) { described_class }

    it 'calculates correct backoff delays' do
      # Access private method for testing
      base = 1.0

      delay1 = service.send(:calculate_backoff_delay, base, 1)
      delay2 = service.send(:calculate_backoff_delay, base, 2)
      delay3 = service.send(:calculate_backoff_delay, base, 3)

      # First attempt: base * 2^0 = 1.0 + jitter
      expect(delay1).to be_between(1.0, 1.5)

      # Second attempt: base * 2^1 = 2.0 + jitter
      expect(delay2).to be_between(2.0, 3.0)

      # Third attempt: base * 2^2 = 4.0 + jitter
      expect(delay3).to be_between(4.0, 6.0)
    end
  end

  describe 'error handling', integration: true do
    context 'when broadcast raises BroadcastError' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to).and_raise(
          BroadcastReliabilityService::BroadcastError, "Channel error"
        )
        allow(BroadcastErrorHandler).to receive(:handle_final_failure)
      end

      it 'handles BroadcastError appropriately' do
        result = described_class.broadcast_with_retry(
          channel: SyncStatusChannel,
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be false
        expect(BroadcastAnalytics).to have_received(:record_failure).with(
          hash_including(error: "Broadcast failed: Channel error")
        ).exactly(3).times
      end
    end

    context 'when channel constantize fails' do
      before do
        # Disable security validation for this test to test retry behavior
        allow(BroadcastFeatureFlags).to receive(:enabled?)
          .with(:broadcast_validation)
          .and_return(false)
      end

      it 'returns false after retries for invalid channel name' do
        allow(BroadcastAnalytics).to receive(:record_failure)
        allow(BroadcastErrorHandler).to receive(:handle_final_failure)

        result = described_class.broadcast_with_retry(
          channel: 'InvalidChannel',
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be false
        expect(BroadcastAnalytics).to have_received(:record_failure).exactly(3).times
        expect(BroadcastErrorHandler).to have_received(:handle_final_failure)
      end
    end

    context 'when security validation is enabled' do
      before do
        allow(BroadcastFeatureFlags).to receive(:enabled?)
          .with(:broadcast_validation)
          .and_return(true)
      end

      it 'rejects invalid channel names before retry attempts' do
        allow(BroadcastAnalytics).to receive(:record_failure)

        result = described_class.broadcast_with_retry(
          channel: 'InvalidChannel',
          target: sync_session,
          data: test_data,
          priority: :medium
        )

        expect(result).to be false
        # Should not attempt retries when validation fails
        expect(BroadcastAnalytics).not_to have_received(:record_failure)
      end
    end
  end

  describe 'thread safety', integration: true do
    it 'handles concurrent broadcasts safely' do
      allow(SyncStatusChannel).to receive(:broadcast_to)

      # Create multiple threads that broadcast concurrently
      threads = 10.times.map do |i|
        Thread.new do
          described_class.broadcast_with_retry(
            channel: SyncStatusChannel,
            target: sync_session,
            data: { message: "concurrent_#{i}" },
            priority: :medium
          )
        end
      end

      results = threads.map(&:value)

      # All broadcasts should succeed
      expect(results).to all(be true)
      expect(SyncStatusChannel).to have_received(:broadcast_to).exactly(10).times
    end
  end
end
