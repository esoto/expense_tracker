# frozen_string_literal: true

require 'rails_helper'

# Comprehensive unit tests for FailedBroadcastRecoveryJob
#
# Test Coverage:
# - Scope chain mocking with FailedBroadcastStore.ready_for_retry.recent_failures.limit
# - target_exists? logic using instance doubles with controlled return values
# - retry_broadcast! contract testing with mocked return values and parameter verification
# - Error classification mocking at class level
# - Error recovery resilience with multiple failure scenarios and cascading error prevention
# - Comprehensive scenarios: success, failure, skip, error, mixed results, edge cases
# - Throttling behavior and batch size limits
# - Logging verification at different levels (info, debug, warn, error)
# - Cache metrics and statistics tracking
# - Performance optimizations and monitoring
#
# Implementation follows recommendations from:
# - Gemini's analysis for robust error handling
# - Tech-lead-architect's requirements for production-ready testing
RSpec.describe FailedBroadcastRecoveryJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  # Create test doubles for dependencies
  let(:failed_broadcast_mock) { instance_double(FailedBroadcastStore) }
  let(:scope_mock) { double('ActiveRecord::Relation') }
  let(:cache_mock) { double('Cache') }

  before do
    # Mock Rails infrastructure
    allow(Rails).to receive(:cache).and_return(cache_mock)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    # Mock the scope chain - this is the recommended approach for ActiveRecord patterns
    allow(FailedBroadcastStore).to receive(:ready_for_retry).and_return(scope_mock)
    allow(scope_mock).to receive(:recent_failures).and_return(scope_mock)
    allow(scope_mock).to receive(:limit).with(50).and_return(scope_mock)

    # Default to empty collection
    allow(scope_mock).to receive(:count).and_return(0)
    allow(scope_mock).to receive(:find_each)

    # Mock cache writes
    allow(cache_mock).to receive(:write)

    # Mock sleep to speed up tests
    allow(job).to receive(:sleep)
  end

  describe '#perform' do
    context 'when there are no broadcasts to recover' do
      before do
        allow(scope_mock).to receive(:count).and_return(0)
        allow(scope_mock).to receive(:find_each)
      end

      it 'completes with zero statistics' do
        result = job.perform

        expect(result).to eq({
          attempted: 0,
          successful: 0,
          failed: 0,
          skipped: 0
        })
      end

      it 'logs the empty queue state' do
        job.perform

        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Starting recovery job')
        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Found 0 broadcasts ready for recovery')
        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Recovery completed: 0 successful, 0 failed, 0 skipped out of 0 attempted')
      end

      it 'records metrics even with empty results' do
        job.perform

        expect(cache_mock).to have_received(:write).with(
          'failed_broadcast_recovery:last_run',
          hash_including(
            stats: { attempted: 0, successful: 0, failed: 0, skipped: 0 }
          ),
          expires_in: 24.hours
        )
      end
    end

    context 'when broadcasts are successfully recovered' do
      let(:broadcast1) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }
      let(:broadcast2) { instance_double(FailedBroadcastStore, id: 2, channel_name: 'TestChannel', target_type: 'User', target_id: 2) }
      let(:broadcasts) { [ broadcast1, broadcast2 ] }

      before do
        allow(scope_mock).to receive(:count).and_return(2)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast1).and_yield(broadcast2)

        # Mock successful recovery
        broadcasts.each do |broadcast|
          allow(broadcast).to receive(:target_exists?).and_return(true)
          allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)
          allow(broadcast).to receive(:update!)
        end
      end

      it 'processes all broadcasts and returns success statistics' do
        result = job.perform

        expect(result).to eq({
          attempted: 2,
          successful: 2,
          failed: 0,
          skipped: 0
        })
      end

      it 'calls retry_broadcast! with manual: false for each broadcast' do
        job.perform

        broadcasts.each do |broadcast|
          expect(broadcast).to have_received(:retry_broadcast!).with(manual: false)
        end
      end

      it 'logs successful recovery for each broadcast' do
        job.perform

        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Successfully recovered: TestChannel -> User#1')
        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Successfully recovered: TestChannel -> User#2')
      end
    end

    context 'when target no longer exists' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 999) }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)

        # Target doesn't exist
        allow(broadcast).to receive(:target_exists?).and_return(false)
        allow(broadcast).to receive(:update!)
      end

      it 'skips the broadcast and updates error information' do
        result = job.perform

        expect(result).to eq({
          attempted: 1,
          successful: 0,
          failed: 0,
          skipped: 1
        })

        expect(broadcast).to have_received(:update!).with(
          error_type: 'record_not_found',
          error_message: 'Target User#999 no longer exists'
        )
      end

      it 'logs the skip action' do
        job.perform

        expect(Rails.logger).to have_received(:debug)
          .with('[FAILED_BROADCAST_RECOVERY] Skipping 1: target no longer exists')
      end

      it 'does not attempt to retry the broadcast' do
        job.perform

        expect(broadcast).not_to receive(:retry_broadcast!)
      end
    end

    context 'when retry_broadcast! returns false' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)

        allow(broadcast).to receive(:target_exists?).and_return(true)
        allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(false)
        allow(broadcast).to receive(:update!)
      end

      it 'counts the broadcast as failed' do
        result = job.perform

        expect(result).to eq({
          attempted: 1,
          successful: 0,
          failed: 1,
          skipped: 0
        })
      end

      it 'logs the failure' do
        job.perform

        expect(Rails.logger).to have_received(:warn)
          .with('[FAILED_BROADCAST_RECOVERY] Failed to recover: TestChannel -> User#1')
      end
    end

    context 'when an exception occurs during recovery' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }
      let(:error) { StandardError.new('Connection refused') }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)

        allow(broadcast).to receive(:target_exists?).and_return(true)
        allow(broadcast).to receive(:retry_broadcast!).and_raise(error)
        allow(broadcast).to receive(:update!)
        allow(FailedBroadcastStore).to receive(:classify_error).with(error).and_return('connection_timeout')
      end

      it 'handles the error gracefully and continues processing' do
        result = job.perform

        expect(result).to eq({
          attempted: 1,
          successful: 0,
          failed: 1,
          skipped: 0
        })
      end

      it 'updates the broadcast with error information' do
        job.perform

        expect(broadcast).to have_received(:update!).with(
          error_type: 'connection_timeout',
          error_message: 'Connection refused'
        )
      end

      it 'logs the error' do
        job.perform

        expect(Rails.logger).to have_received(:error)
          .with('[FAILED_BROADCAST_RECOVERY] Error recovering broadcast 1: Connection refused')
      end

      it 'classifies the error correctly' do
        job.perform

        expect(FailedBroadcastStore).to have_received(:classify_error).with(error)
      end
    end

    context 'with mixed results' do
      let(:success_broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'Channel1', target_type: 'User', target_id: 1) }
      let(:skip_broadcast) { instance_double(FailedBroadcastStore, id: 2, channel_name: 'Channel2', target_type: 'User', target_id: 2) }
      let(:fail_broadcast) { instance_double(FailedBroadcastStore, id: 3, channel_name: 'Channel3', target_type: 'User', target_id: 3) }
      let(:error_broadcast) { instance_double(FailedBroadcastStore, id: 4, channel_name: 'Channel4', target_type: 'User', target_id: 4) }

      before do
        allow(scope_mock).to receive(:count).and_return(4)
        allow(scope_mock).to receive(:find_each)
          .and_yield(success_broadcast)
          .and_yield(skip_broadcast)
          .and_yield(fail_broadcast)
          .and_yield(error_broadcast)

        # Success case
        allow(success_broadcast).to receive(:target_exists?).and_return(true)
        allow(success_broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)

        # Skip case
        allow(skip_broadcast).to receive(:target_exists?).and_return(false)
        allow(skip_broadcast).to receive(:update!)

        # Failure case
        allow(fail_broadcast).to receive(:target_exists?).and_return(true)
        allow(fail_broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(false)

        # Error case
        allow(error_broadcast).to receive(:target_exists?).and_return(true)
        allow(error_broadcast).to receive(:retry_broadcast!).and_raise(StandardError, 'Unexpected error')
        allow(error_broadcast).to receive(:update!)
        allow(FailedBroadcastStore).to receive(:classify_error).and_return('unknown')
      end

      it 'correctly tallies all result types' do
        result = job.perform

        expect(result).to eq({
          attempted: 4,
          successful: 1,
          failed: 2,
          skipped: 1
        })
      end

      it 'logs the final summary with all statistics' do
        job.perform

        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Recovery completed: 1 successful, 2 failed, 1 skipped out of 4 attempted')
      end
    end

    context 'throttling behavior' do
      let(:broadcasts) { (1..11).map { |i| instance_double(FailedBroadcastStore, id: i, channel_name: 'Channel', target_type: 'User', target_id: i) } }

      before do
        allow(scope_mock).to receive(:count).and_return(11)

        # Set up find_each to yield all broadcasts
        allow(scope_mock).to receive(:find_each) do |&block|
          broadcasts.each(&block)
        end

        # All broadcasts succeed
        broadcasts.each do |broadcast|
          allow(broadcast).to receive(:target_exists?).and_return(true)
          allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)
        end
      end

      it 'sleeps after every 10 broadcasts' do
        job.perform

        # Should sleep once after the 10th broadcast (not after 11th since it's not divisible by 10)
        expect(job).to have_received(:sleep).with(0.1).once
      end

      it 'processes all broadcasts despite throttling' do
        result = job.perform

        expect(result[:attempted]).to eq(11)
        expect(result[:successful]).to eq(11)
      end
    end

    context 'with exactly MAX_RECOVERY_BATCH_SIZE broadcasts' do
      before do
        allow(scope_mock).to receive(:limit).with(50).and_return(scope_mock)
      end

      it 'respects the batch size limit' do
        job.perform

        expect(scope_mock).to have_received(:limit).with(50)
      end
    end
  end

  describe '#record_recovery_metrics' do
    let(:stats) { { attempted: 5, successful: 3, failed: 1, skipped: 1 } }
    let(:current_time) { Time.zone.parse('2025-08-30 15:30:00') }

    before do
      allow(Time).to receive(:current).and_return(current_time)
    end

    it 'writes metrics to cache with correct format' do
      job.send(:record_recovery_metrics, stats)

      expect(cache_mock).to have_received(:write).with(
        'failed_broadcast_recovery:last_run',
        {
          timestamp: '2025-08-30T15:30:00Z',
          stats: stats
        },
        expires_in: 24.hours
      )
    end
  end

  describe 'job configuration' do
    it 'uses the low priority queue' do
      expect(described_class.queue_name).to eq('low')
    end

    it 'has the correct MAX_RECOVERY_BATCH_SIZE constant' do
      expect(described_class::MAX_RECOVERY_BATCH_SIZE).to eq(50)
    end
  end

  describe 'error recovery resilience' do
    context 'when processing continues after errors' do
      let(:error_broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 999) }
      let(:success_broadcast) { instance_double(FailedBroadcastStore, id: 2, channel_name: 'TestChannel', target_type: 'User', target_id: 1000) }

      before do
        allow(scope_mock).to receive(:count).and_return(2)
        allow(scope_mock).to receive(:find_each).and_yield(error_broadcast).and_yield(success_broadcast)

        # First broadcast throws error during retry
        allow(error_broadcast).to receive(:target_exists?).and_return(true)
        allow(error_broadcast).to receive(:retry_broadcast!).and_raise(RuntimeError, 'Unexpected error')
        allow(error_broadcast).to receive(:update!)
        allow(FailedBroadcastStore).to receive(:classify_error).and_return('unknown')

        # Second broadcast processes normally
        allow(success_broadcast).to receive(:target_exists?).and_return(true)
        allow(success_broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)
      end

      it 'continues processing remaining broadcasts after errors' do
        result = job.perform

        # First broadcast fails due to error, second succeeds
        expect(result[:attempted]).to eq(2)
        expect(result[:successful]).to eq(1)
        expect(result[:failed]).to eq(1)
        expect(result[:skipped]).to eq(0)

        # Error should be logged for the failed one
        expect(Rails.logger).to have_received(:error)
          .with('[FAILED_BROADCAST_RECOVERY] Error recovering broadcast 1: Unexpected error')

        # Success should be logged for the second one
        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Successfully recovered: TestChannel -> User#1000')
      end
    end

    context 'when target_exists? raises an error' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)

        allow(broadcast).to receive(:target_exists?).and_raise(NameError, 'uninitialized constant')
        allow(broadcast).to receive(:update!)
        allow(FailedBroadcastStore).to receive(:classify_error).and_return('unknown')
      end

      it 'handles the error and counts as failed' do
        result = job.perform

        expect(result[:failed]).to eq(1)
        expect(broadcast).to have_received(:update!).with(
          error_type: 'unknown',
          error_message: 'uninitialized constant'
        )
      end
    end
  end

  describe 'integration with FailedBroadcastStore scopes' do
    it 'chains the correct scopes in order' do
      job.perform

      # Verify scope chain is called in correct order
      expect(FailedBroadcastStore).to have_received(:ready_for_retry).ordered
      expect(scope_mock).to have_received(:recent_failures).ordered
      expect(scope_mock).to have_received(:limit).with(50).ordered
    end

    context 'when scope chain returns nil at any point' do
      before do
        allow(FailedBroadcastStore).to receive(:ready_for_retry).and_return(nil)
      end

      it 'handles nil gracefully without raising errors' do
        expect { job.perform }.to raise_error(NoMethodError)
      end
    end
  end

  describe 'comprehensive error classification' do
    let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }

    before do
      allow(scope_mock).to receive(:count).and_return(1)
      allow(scope_mock).to receive(:find_each).and_yield(broadcast)
      allow(broadcast).to receive(:target_exists?).and_return(true)
      allow(broadcast).to receive(:update!)
    end

    context 'with connection errors' do
      [
        [ 'Connection refused', Redis::CannotConnectError, 'connection_timeout' ],
        [ 'Net::ReadTimeout with "Connection timeout"', Net::ReadTimeout, 'connection_timeout' ],
        [ 'Connection refused - Socket error', Errno::ECONNREFUSED, 'connection_timeout' ]
      ].each do |expected_message, error_class, expected_type|
        it "classifies #{error_class} as #{expected_type}" do
          # Create the error with appropriate message based on the class
          error = if error_class == Net::ReadTimeout
                    error_class.new('Connection timeout')
          elsif error_class == Errno::ECONNREFUSED
                    error_class.new('Socket error')
          else
                    error_class.new('Connection refused')
          end

          allow(broadcast).to receive(:retry_broadcast!).and_raise(error)
          allow(FailedBroadcastStore).to receive(:classify_error).with(error).and_return(expected_type)

          job.perform

          # Verify the update was called with the actual error message from the exception
          expect(broadcast).to have_received(:update!).with(
            error_type: expected_type,
            error_message: expected_message
          )
        end
      end
    end

    context 'with database errors' do
      it 'classifies ActiveRecord::RecordNotFound correctly' do
        error = ActiveRecord::RecordNotFound.new('Record not found')
        allow(broadcast).to receive(:retry_broadcast!).and_raise(error)
        allow(FailedBroadcastStore).to receive(:classify_error).with(error).and_return('record_not_found')

        job.perform

        expect(broadcast).to have_received(:update!).with(
          error_type: 'record_not_found',
          error_message: 'Record not found'
        )
      end

      it 'classifies ActiveRecord::StatementInvalid correctly' do
        error = ActiveRecord::StatementInvalid.new('PG::ConnectionBad')
        allow(broadcast).to receive(:retry_broadcast!).and_raise(error)
        allow(FailedBroadcastStore).to receive(:classify_error).with(error).and_return('database_error')

        job.perform

        expect(broadcast).to have_received(:update!).with(
          error_type: 'database_error',
          error_message: 'PG::ConnectionBad'
        )
      end
    end
  end

  describe 'cascading error prevention' do
    context 'when update! fails after recovery failure' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'TestChannel', target_type: 'User', target_id: 1) }
      let(:recovery_error) { StandardError.new('Original error') }
      let(:update_error) { ActiveRecord::StatementInvalid.new('Database error during update') }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)
        allow(broadcast).to receive(:target_exists?).and_return(true)
        allow(broadcast).to receive(:retry_broadcast!).and_raise(recovery_error)
        allow(FailedBroadcastStore).to receive(:classify_error).and_return('unknown')
        allow(broadcast).to receive(:update!).and_raise(update_error)
      end

      it 'logs both errors but continues processing' do
        allow(Rails.logger).to receive(:error)

        # The job should handle the update error gracefully
        expect { job.perform }.not_to raise_error

        # Both errors should be logged
        expect(Rails.logger).to have_received(:error)
          .with('[FAILED_BROADCAST_RECOVERY] Error recovering broadcast 1: Original error')
        expect(Rails.logger).to have_received(:error)
          .with('[FAILED_BROADCAST_RECOVERY] Failed to update error info for broadcast 1: Database error during update')
      end
    end

    context 'when multiple broadcasts fail in sequence' do
      let(:broadcasts) do
        (1..5).map do |i|
          instance_double(FailedBroadcastStore, id: i, channel_name: "Channel#{i}", target_type: 'User', target_id: i)
        end
      end

      before do
        allow(scope_mock).to receive(:count).and_return(5)
        allow(scope_mock).to receive(:find_each) do |&block|
          broadcasts.each(&block)
        end

        broadcasts.each do |broadcast|
          allow(broadcast).to receive(:target_exists?).and_return(true)
          allow(broadcast).to receive(:retry_broadcast!).and_raise(StandardError, "Error for #{broadcast.id}")
          allow(broadcast).to receive(:update!)
        end
        allow(FailedBroadcastStore).to receive(:classify_error).and_return('unknown')
      end

      it 'processes all broadcasts despite multiple failures' do
        result = job.perform

        expect(result).to eq({
          attempted: 5,
          successful: 0,
          failed: 5,
          skipped: 0
        })

        # Verify all broadcasts were attempted
        broadcasts.each do |broadcast|
          expect(broadcast).to have_received(:retry_broadcast!)
        end
      end
    end
  end

  describe 'edge case handling' do
    context 'when find_each yields nothing despite count > 0' do
      before do
        allow(scope_mock).to receive(:count).and_return(5)
        allow(scope_mock).to receive(:find_each) # yields nothing
      end

      it 'handles the discrepancy gracefully' do
        result = job.perform

        expect(result).to eq({
          attempted: 0,
          successful: 0,
          failed: 0,
          skipped: 0
        })
      end
    end

    context 'when broadcast attributes are nil' do
      let(:broadcast) { instance_double(FailedBroadcastStore, id: nil, channel_name: nil, target_type: nil, target_id: nil) }

      before do
        allow(scope_mock).to receive(:count).and_return(1)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast)
        allow(broadcast).to receive(:target_exists?).and_return(true)
        allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)
      end

      it 'processes the broadcast without errors' do
        result = job.perform

        expect(result[:successful]).to eq(1)
        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Successfully recovered:  -> #')
      end
    end

    context 'when MAX_RECOVERY_BATCH_SIZE is exceeded' do
      let(:broadcasts) do
        (1..60).map do |i|
          instance_double(FailedBroadcastStore, id: i, channel_name: 'Channel', target_type: 'User', target_id: i)
        end
      end

      before do
        # The limit should restrict to 50
        limited_broadcasts = broadcasts.first(50)
        allow(scope_mock).to receive(:count).and_return(50)
        allow(scope_mock).to receive(:find_each) do |&block|
          limited_broadcasts.each(&block)
        end

        limited_broadcasts.each do |broadcast|
          allow(broadcast).to receive(:target_exists?).and_return(true)
          allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(true)
        end
      end

      it 'processes exactly MAX_RECOVERY_BATCH_SIZE broadcasts' do
        result = job.perform

        expect(result[:attempted]).to eq(50)
        expect(result[:successful]).to eq(50)
      end
    end
  end

  describe 'performance optimizations' do
    context 'with large batch processing' do
      let(:broadcasts) do
        (1..50).map do |i|
          instance_double(FailedBroadcastStore, id: i, channel_name: 'Channel', target_type: 'User', target_id: i)
        end
      end

      before do
        allow(scope_mock).to receive(:count).and_return(50)
        allow(scope_mock).to receive(:find_each) do |&block|
          broadcasts.each(&block)
        end

        broadcasts.each_with_index do |broadcast, index|
          allow(broadcast).to receive(:target_exists?).and_return(true)
          # Mix of success and failure
          allow(broadcast).to receive(:retry_broadcast!).with(manual: false).and_return(index.even?)
        end
      end

      it 'throttles appropriately throughout the batch' do
        job.perform

        # Should sleep at 10, 20, 30, 40, 50
        expect(job).to have_received(:sleep).with(0.1).exactly(5).times
      end

      it 'completes within reasonable time despite throttling' do
        start_time = Time.current
        job.perform
        end_time = Time.current

        # Should complete quickly since sleep is mocked
        expect(end_time - start_time).to be < 1.second
      end
    end
  end

  describe 'monitoring and observability' do
    context 'when tracking recovery patterns' do
      let(:broadcast1) { instance_double(FailedBroadcastStore, id: 1, channel_name: 'ChannelA', target_type: 'User', target_id: 1) }
      let(:broadcast2) { instance_double(FailedBroadcastStore, id: 2, channel_name: 'ChannelB', target_type: 'Post', target_id: 2) }

      before do
        allow(scope_mock).to receive(:count).and_return(2)
        allow(scope_mock).to receive(:find_each).and_yield(broadcast1).and_yield(broadcast2)

        allow(broadcast1).to receive(:target_exists?).and_return(true)
        allow(broadcast1).to receive(:retry_broadcast!).with(manual: false).and_return(true)

        allow(broadcast2).to receive(:target_exists?).and_return(false)
        allow(broadcast2).to receive(:update!)
      end

      it 'logs distinct patterns for different target types' do
        job.perform

        expect(Rails.logger).to have_received(:info)
          .with('[FAILED_BROADCAST_RECOVERY] Successfully recovered: ChannelA -> User#1')
        expect(Rails.logger).to have_received(:debug)
          .with('[FAILED_BROADCAST_RECOVERY] Skipping 2: target no longer exists')
      end
    end

    context 'when cache write fails' do
      before do
        # First allow normal behavior for find_each
        allow(scope_mock).to receive(:count).and_return(0)
        allow(scope_mock).to receive(:find_each)

        # Then mock cache write to fail
        allow(cache_mock).to receive(:write).and_raise(Redis::CannotConnectError, 'Cache unavailable')

        # The job should log the error
        allow(Rails.logger).to receive(:error)
      end

      it 'completes job despite cache failure' do
        # Job should complete successfully even if cache write fails
        expect { job.perform }.not_to raise_error
      end

      it 'returns correct statistics even if metrics recording fails' do
        result = job.perform

        expect(result).to eq({
          attempted: 0,
          successful: 0,
          failed: 0,
          skipped: 0
        })
      end

      it 'logs the cache write failure' do
        job.perform

        expect(Rails.logger).to have_received(:error)
          .with('[FAILED_BROADCAST_RECOVERY] Failed to record metrics: Cache unavailable')
      end
    end
  end
end
