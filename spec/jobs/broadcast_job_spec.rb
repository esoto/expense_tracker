# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastJob, type: :job do
  let(:sync_session) { create(:sync_session) }
  let(:channel_name) { 'SyncStatusChannel' }
  let(:target_type) { 'SyncSession' }
  let(:target_id) { sync_session.id }
  let(:data) { { status: 'processing', processed: 10, total: 100 } }
  let(:priority) { 'medium' }

  describe '#perform' do
    context 'when broadcast succeeds' do
      before do
        allow(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)
      end

      it 'performs broadcast successfully' do
        expect {
          described_class.new.perform(channel_name, target_id, target_type, data, priority)
        }.not_to raise_error

        expect(BroadcastReliabilityService).to have_received(:broadcast_with_retry).with(
          channel: channel_name,
          target: sync_session,
          data: data,
          priority: :medium
        )
      end

      it 'logs successful completion' do
        allow(Rails.logger).to receive(:info)

        described_class.new.perform(channel_name, target_id, target_type, data, priority)

        expect(Rails.logger).to have_received(:info).with(
          match(/BROADCAST_JOB.*Completed.*SyncStatusChannel.*SyncSession##{target_id}.*Priority: medium/)
        )
      end
    end

    context 'when broadcast fails' do
      before do
        allow(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(false)
      end

      it 'logs failure warning' do
        allow(Rails.logger).to receive(:warn)

        described_class.new.perform(channel_name, target_id, target_type, data, priority)

        expect(Rails.logger).to have_received(:warn).with(
          match(/BROADCAST_JOB.*Failed after retries.*SyncStatusChannel.*SyncSession##{target_id}/)
        )
      end
    end

    context 'when target record is not found' do
      let(:invalid_target_id) { 99999 }

      before do
        allow(BroadcastAnalytics).to receive(:record_failure)
        allow(FailedBroadcastStore).to receive(:create!)
      end

      it 'handles RecordNotFound gracefully' do
        expect {
          described_class.new.perform(channel_name, invalid_target_id, target_type, data, priority)
        }.not_to raise_error
      end

      it 'records failure in analytics' do
        described_class.new.perform(channel_name, invalid_target_id, target_type, data, priority)

        expect(BroadcastAnalytics).to have_received(:record_failure).with(
          channel: channel_name,
          target_type: target_type,
          target_id: invalid_target_id,
          priority: priority,
          attempt: 1,
          error: match(/Target not found/),
          duration: be_a(Float)
        )
      end

      it 'creates failed broadcast store record' do
        described_class.new.perform(channel_name, invalid_target_id, target_type, data, priority)

        expect(FailedBroadcastStore).to have_received(:create!).with(
          channel_name: channel_name,
          target_type: target_type,
          target_id: invalid_target_id,
          data: data,
          priority: priority,
          error_type: 'record_not_found',
          error_message: match(/Couldn't find/),
          failed_at: be_within(1.second).of(Time.current),
          retry_count: 0
        )
      end

      it 'logs error message' do
        allow(Rails.logger).to receive(:error)

        described_class.new.perform(channel_name, invalid_target_id, target_type, data, priority)

        expect(Rails.logger).to have_received(:error).with(
          match(/BROADCAST_JOB.*Target not found.*#{target_type}##{invalid_target_id}/)
        )
      end
    end

    context 'when unexpected error occurs' do
      let(:error_message) { 'Unexpected system error' }

      before do
        allow(SyncSession).to receive(:find).and_raise(StandardError, error_message)
        allow(BroadcastAnalytics).to receive(:record_failure)
        allow(FailedBroadcastStore).to receive(:create!)
        allow(Rails.logger).to receive(:error)
      end

      it 'records failure and re-raises error' do
        expect {
          described_class.new.perform(channel_name, target_id, target_type, data, priority)
        }.to raise_error(StandardError, error_message)

        expect(BroadcastAnalytics).to have_received(:record_failure)
        expect(FailedBroadcastStore).to have_received(:create!)
      end

      it 'creates failed broadcast store with job_error type' do
        expect {
          described_class.new.perform(channel_name, target_id, target_type, data, priority)
        }.to raise_error(StandardError)

        expect(FailedBroadcastStore).to have_received(:create!).with(
          hash_including(
            error_type: 'job_error',
            error_message: error_message
          )
        )
      end

      it 'logs error with backtrace' do
        expect {
          described_class.new.perform(channel_name, target_id, target_type, data, priority)
        }.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error).at_least(:once)
      end
    end

    context 'with default priority' do
      it 'uses medium priority when not specified' do
        allow(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)

        described_class.new.perform(channel_name, target_id, target_type, data)

        expect(BroadcastReliabilityService).to have_received(:broadcast_with_retry).with(
          hash_including(priority: :medium)
        )
      end
    end
  end

  describe '.enqueue_broadcast' do
    let(:job_double) { double('Job') }

    before do
      allow(described_class).to receive(:set).and_return(job_double)
      allow(job_double).to receive(:perform_later)
      allow(BroadcastAnalytics).to receive(:record_queued)
    end

    it 'enqueues job with correct queue based on priority' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :high
      )

      expect(described_class).to have_received(:set).with(queue: 'high')
      expect(job_double).to have_received(:perform_later).with(
        channel_name, target_id, target_type, data, 'high'
      )
    end

    it 'uses default queue for medium priority' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :medium
      )

      expect(described_class).to have_received(:set).with(queue: 'default')
    end

    it 'uses critical queue for critical priority' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :critical
      )

      expect(described_class).to have_received(:set).with(queue: 'critical')
    end

    it 'uses low queue for low priority' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :low
      )

      expect(described_class).to have_received(:set).with(queue: 'low')
    end

    it 'records queued broadcast in analytics' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :high
      )

      expect(BroadcastAnalytics).to have_received(:record_queued).with(
        channel: channel_name,
        target_type: target_type,
        target_id: target_id,
        priority: :high
      )
    end

    it 'handles unknown priority gracefully' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :unknown
      )

      expect(described_class).to have_received(:set).with(queue: 'default')
    end

    it 'uses default priority when not specified' do
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data
      )

      expect(described_class).to have_received(:set).with(queue: 'default')
    end
  end

  describe '.stats' do
    let(:critical_queue) { double('Queue', size: 2) }
    let(:high_queue) { double('Queue', size: 5) }
    let(:default_queue) { double('Queue', size: 10) }
    let(:low_queue) { double('Queue', size: 3) }

    before do
      # Stub Sidekiq module and Queue class properly
      sidekiq_module = Module.new
      queue_class = Class.new do
        def initialize(name)
          @name = name
        end
      end
      
      stub_const('Sidekiq', sidekiq_module)
      stub_const('Sidekiq::Queue', queue_class)
      
      allow(Sidekiq::Queue).to receive(:new).with('critical').and_return(critical_queue)
      allow(Sidekiq::Queue).to receive(:new).with('high').and_return(high_queue)
      allow(Sidekiq::Queue).to receive(:new).with('default').and_return(default_queue)
      allow(Sidekiq::Queue).to receive(:new).with('low').and_return(low_queue)
    end

    it 'returns comprehensive job statistics' do
      stats = described_class.stats

      expect(stats).to include(
        total_enqueued: 20, # 2 + 5 + 10 + 3
        queue_sizes: {
          critical: 2,
          high: 5,
          default: 10,
          low: 3
        },
        processing_times: {
          critical: 0.05,
          high: 0.08,
          default: 0.12,
          low: 0.15
        }
      )
    end
  end

  describe 'queue configuration' do
    it 'has correct queue mapping' do
      expect(described_class::QUEUE_MAPPING).to eq(
        critical: 'critical',
        high: 'high',
        medium: 'default',
        low: 'low'
      )
    end
  end

  describe 'job configuration' do
    it 'uses ApplicationJob as base class' do
      expect(described_class).to be < ApplicationJob
    end

    it 'discards on standard errors (handled by BroadcastReliabilityService)' do
      expect(described_class.rescue_handlers).to be_present
    end
  end

  describe 'integration test' do
    it 'performs end-to-end broadcast job successfully' do
      # Simulate real broadcast
      allow(SyncStatusChannel).to receive(:broadcast_to)
      allow(Rails.logger).to receive(:info)

      # Enqueue and perform job
      described_class.enqueue_broadcast(
        channel_name: channel_name,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: :high
      )

      # Manually perform the job (instead of waiting for Sidekiq)
      job = described_class.new
      job.perform(channel_name, target_id, target_type, data, 'high')

      # Verify the broadcast was called
      expect(SyncStatusChannel).to have_received(:broadcast_to).with(sync_session, data)
    end
  end
end