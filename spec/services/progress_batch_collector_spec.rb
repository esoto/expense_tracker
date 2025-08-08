# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProgressBatchCollector, type: :service do
  let(:sync_session) { create(:sync_session) }
  let(:config) do
    {
      batch_interval: 1.second,
      batch_size: 5,
      critical_immediate: true,
      max_memory_updates: 20,
      cleanup_interval: 5.seconds
    }
  end

  subject { described_class.new(sync_session, config: config) }

  before do
    allow(BroadcastReliabilityService).to receive(:broadcast_with_retry)
  end

  after do
    # Clean up to prevent thread leaks
    subject.stop if subject.active?
  end

  describe '#initialize' do
    it 'initializes with correct configuration' do
      collector = described_class.new(sync_session, config: config)
      
      expect(collector.sync_session).to eq(sync_session)
      expect(collector.config).to include(config)
      expect(collector.active?).to be true
      expect(collector.update_count.value).to eq(0)
    end

    it 'starts background timer thread' do
      collector = described_class.new(sync_session, config: config)
      
      # Give time for thread to start
      sleep(0.1)
      
      expect(collector.instance_variable_get(:@timer_thread)).to be_alive
      
      collector.stop
    end

    it 'sets up object finalizer for cleanup' do
      expect(ObjectSpace).to receive(:define_finalizer)
      described_class.new(sync_session, config: config).stop
    end
  end

  describe '#add_progress_update' do
    it 'adds progress update to batch' do
      subject.add_progress_update(processed: 10, total: 100, detected: 2)
      
      expect(subject.batch_data).not_to be_empty
      expect(subject.update_count.value).to eq(1)
    end

    it 'includes timestamp in update data' do
      freeze_time do
        subject.add_progress_update(processed: 10, total: 100)
        
        update = subject.batch_data[:progress]
        expect(update[:timestamp]).to eq(Time.current.to_f)
      end
    end

    it 'flushes batch when progress reaches milestone' do
      allow(subject).to receive(:should_flush_for_progress?).and_return(true)
      expect(subject).to receive(:flush_batch_async)
      
      subject.add_progress_update(processed: 50, total: 100)
    end

    it 'does not add updates when collector is stopped' do
      subject.stop
      
      subject.add_progress_update(processed: 10, total: 100)
      
      expect(subject.batch_data).to be_empty
    end
  end

  describe '#add_account_update' do
    it 'adds account-specific update to batch' do
      subject.add_account_update(
        account_id: 123,
        status: 'processing',
        processed: 10,
        total: 50,
        detected: 2
      )
      
      expect(subject.batch_data['account_123']).to include(
        type: 'account_update',
        account_id: 123,
        status: 'processing',
        processed: 10,
        total: 50,
        detected: 2
      )
    end
  end

  describe '#add_critical_update' do
    context 'when critical_immediate is enabled' do
      it 'broadcasts critical messages immediately' do
        expect(subject).to receive(:broadcast_critical_update).with(
          hash_including(
            type: 'error',
            message: 'Connection failed',
            critical: true
          )
        )
        
        subject.add_critical_update(
          type: 'error',
          message: 'Connection failed',
          data: { code: 500 }
        )
      end
    end

    context 'when critical_immediate is disabled' do
      let(:config) { super().merge(critical_immediate: false) }

      it 'adds critical update to batch instead of broadcasting immediately' do
        expect(subject).not_to receive(:broadcast_critical_update)
        expect(subject).to receive(:flush_batch_async)
        
        subject.add_critical_update(
          type: 'error', 
          message: 'Connection failed'
        )
        
        expect(subject.batch_data[:critical]).to include(
          type: 'error',
          message: 'Connection failed',
          critical: true
        )
      end
    end

    it 'recognizes critical message types' do
      described_class::CRITICAL_MESSAGE_TYPES.each do |critical_type|
        expect(subject).to receive(:broadcast_critical_update)
        
        subject.add_critical_update(
          type: critical_type,
          message: 'Critical message'
        )
      end
    end
  end

  describe '#add_activity_update' do
    it 'adds activity update to batch' do
      subject.add_activity_update(
        activity_type: 'email_fetch',
        message: 'Fetched 10 emails',
        metadata: { duration: 1.5 }
      )
      
      expect(subject.batch_data[:activity]).to include(
        type: 'activity',
        activity_type: 'email_fetch',
        message: 'Fetched 10 emails',
        metadata: { duration: 1.5 }
      )
    end
  end

  describe '#flush_batch' do
    before do
      subject.add_progress_update(processed: 10, total: 100)
      subject.add_account_update(account_id: 1, status: 'processing', processed: 5, total: 25)
    end

    it 'flushes all pending updates' do
      expect(subject).to receive(:broadcast_batch).with(hash_including(
        :progress,
        'account_1'
      ))
      
      subject.flush_batch
      
      expect(subject.batch_data).to be_empty
    end

    it 'updates last_batch_time' do
      freeze_time do
        subject.flush_batch
        expect(subject.last_batch_time).to be_within(1.second).of(Time.current)
      end
    end

    it 'handles broadcast errors gracefully' do
      allow(subject).to receive(:broadcast_batch).and_raise(StandardError, "Broadcast failed")
      
      # Should restore failed batch data
      expect(subject).to receive(:restore_failed_batch)
      
      subject.flush_batch
    end

    it 'does nothing when batch is empty and not forced' do
      subject.instance_variable_get(:@batch_data).clear
      
      expect(subject).not_to receive(:broadcast_batch)
      
      subject.flush_batch(force: false)
    end

    it 'processes empty batch when forced' do
      subject.instance_variable_get(:@batch_data).clear
      
      expect(subject).to receive(:broadcast_batch).with({})
      
      subject.flush_batch(force: true)
    end
  end

  describe '#stop' do
    it 'stops the collector and flushes remaining updates' do
      subject.add_progress_update(processed: 10, total: 100)
      
      expect(subject).to receive(:flush_batch).with(force: true)
      expect(subject).to receive(:stop_timer_thread)
      
      subject.stop
      
      expect(subject.active?).to be false
      expect(subject.batch_data).to be_empty
    end

    it 'marks shutdown as complete' do
      subject.stop
      
      shutdown_promise = subject.instance_variable_get(:@shutdown_complete)
      expect(shutdown_promise.value).to be true
    end
  end

  describe 'thread management' do
    it 'creates named timer thread' do
      collector = described_class.new(sync_session, config: config)
      sleep(0.1) # Allow thread to start
      
      timer_thread = collector.instance_variable_get(:@timer_thread)
      expect(timer_thread.name).to eq("batch_collector_#{sync_session.id}")
      
      collector.stop
    end

    it 'stops timer thread gracefully' do
      collector = described_class.new(sync_session, config: config)
      sleep(0.1) # Allow thread to start
      
      timer_thread = collector.instance_variable_get(:@timer_thread)
      expect(timer_thread).to be_alive
      
      collector.stop
      
      expect(timer_thread).not_to be_alive
    end

    it 'handles thread termination timeout' do
      collector = described_class.new(sync_session, config: config)
      timer_thread = collector.instance_variable_get(:@timer_thread)
      
      # Mock thread that doesn't respond to join
      allow(timer_thread).to receive(:join).and_return(nil)
      allow(timer_thread).to receive(:alive?).and_return(true, false)
      expect(timer_thread).to receive(:terminate)
      
      collector.stop
    end
  end

  describe 'memory management' do
    it 'enforces max memory limit' do
      config_with_low_limit = config.merge(max_memory_updates: 3)
      collector = described_class.new(sync_session, config: config_with_low_limit)
      
      # Add updates up to limit
      3.times { |i| collector.add_progress_update(processed: i, total: 100) }
      
      # Adding one more should trigger flush
      expect(collector).to receive(:flush_batch_async)
      
      collector.add_progress_update(processed: 4, total: 100)
      
      collector.stop
    end

    it 'clears batch data on stop to prevent memory leaks' do
      subject.add_progress_update(processed: 10, total: 100)
      expect(subject.batch_data).not_to be_empty
      
      subject.stop
      
      expect(subject.batch_data).to be_empty
    end
  end

  describe 'batch size triggering' do
    it 'flushes when batch size limit is reached' do
      expect(subject).to receive(:flush_batch_async)
      
      # Add updates up to batch size limit (5 in test config)
      5.times { |i| subject.add_progress_update(processed: i, total: 100) }
    end
  end

  describe 'time-based flushing' do
    it 'flushes batch based on time interval' do
      subject.add_progress_update(processed: 10, total: 100)
      
      # Fast-forward time past batch interval
      travel(config[:batch_interval] + 0.5.seconds) do
        expect(subject.send(:time_for_batch_flush?)).to be true
      end
    end
  end

  describe '#stats' do
    it 'returns collector statistics' do
      subject.add_progress_update(processed: 10, total: 100)
      subject.add_account_update(account_id: 1, status: 'processing', processed: 5, total: 25)
      
      stats = subject.stats
      
      expect(stats).to include(
        sync_session_id: sync_session.id,
        pending_updates: 2,
        total_updates_processed: 2,
        running: true,
        config: hash_including(config)
      )
    end
  end

  describe 'finalizer cleanup' do
    it 'creates proper finalizer proc' do
      timer_thread = double('Thread', alive?: true)
      shutdown_promise = double('Promise', fulfilled?: false)
      
      allow(timer_thread).to receive(:terminate)
      allow(shutdown_promise).to receive(:set).with(true)
      
      finalizer = described_class.finalizer(timer_thread, shutdown_promise)
      
      expect(finalizer).to be_a(Proc)
      
      # Execute finalizer
      finalizer.call
      
      expect(timer_thread).to have_received(:terminate)
      expect(shutdown_promise).to have_received(:set).with(true)
    end

    it 'handles errors in finalizer gracefully' do
      timer_thread = double('Thread')
      shutdown_promise = double('Promise')
      
      allow(timer_thread).to receive(:alive?).and_raise(StandardError, "Thread error")
      allow(Rails).to receive(:logger).and_return(double(error: nil))
      
      finalizer = described_class.finalizer(timer_thread, shutdown_promise)
      
      expect { finalizer.call }.not_to raise_error
    end
  end

  describe 'broadcast grouping' do
    before do
      # Add mixed update types
      subject.add_progress_update(processed: 10, total: 100)
      subject.add_progress_update(processed: 20, total: 100) 
      subject.add_account_update(account_id: 1, status: 'processing', processed: 5, total: 25)
      subject.add_activity_update(activity_type: 'fetch', message: 'Done')
    end

    it 'groups updates by type for efficient broadcasting' do
      grouped = subject.send(:group_updates_by_type, subject.batch_data)
      
      expect(grouped.keys).to include('progress_update', 'account_update', 'activity')
      expect(grouped['progress_update']).to have_exactly(2).items
      expect(grouped['account_update']).to have_exactly(1).item
      expect(grouped['activity']).to have_exactly(1).item
    end

    it 'broadcasts progress updates as batches with latest data' do
      expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).with(
        channel: SyncStatusChannel,
        target: sync_session,
        data: hash_including(
          type: 'progress_batch',
          batch_size: 2,
          latest: hash_including(processed: 20)
        ),
        priority: :medium
      )
      
      subject.flush_batch
    end
  end

  describe 'thread safety' do
    it 'handles concurrent updates safely' do
      threads = 10.times.map do |i|
        Thread.new do
          subject.add_progress_update(processed: i, total: 100)
        end
      end

      threads.each(&:join)

      expect(subject.update_count.value).to eq(10)
      expect(subject.batch_data.size).to eq(1) # Should be deduplicated by key
    end
  end
end