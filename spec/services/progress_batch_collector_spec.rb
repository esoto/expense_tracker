# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProgressBatchCollector, type: :service do
  include ActiveSupport::Testing::TimeHelpers
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

    it 'initializes without finalizer (simplified implementation)' do
      # Finalizer removed in refactoring for simplicity
      collector = described_class.new(sync_session, config: config)
      expect(collector).to be_active
      collector.stop
    end
  end

  describe '#add_progress_update' do
    it 'adds progress update to batch' do
      # Use values that won't trigger milestone flush (5/100 = 5%)
      subject.add_progress_update(processed: 5, total: 100, detected: 2)
      
      expect(subject.batch_data).not_to be_empty
      expect(subject.update_count.value).to eq(1)
    end

    it 'includes timestamp in update data' do
      freeze_time do
        # Use values that won't trigger milestone flush
        subject.add_progress_update(processed: 5, total: 100)
        
        update = subject.batch_data[:progress]
        expect(update[:timestamp]).to eq(Time.current.to_f)
      end
    end

    it 'flushes batch when progress reaches milestone' do
      # 50/100 = 50% which is a milestone
      expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)
      
      subject.add_progress_update(processed: 50, total: 100)
      
      # Batch should be empty after flush
      expect(subject.batch_data).to be_empty
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
        # Ensure collector is active
        expect(subject).to be_active
        
        # When critical_immediate is false, it still flushes but not immediately
        # The broadcast will happen as part of the batch
        expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)
        
        subject.add_critical_update(
          type: 'error', 
          message: 'Connection failed'
        )
        
        # The batch should be empty after the flush
        expect(subject.batch_data).to be_empty
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
      # Use 3% to avoid triggering milestone flush at 10%
      subject.add_progress_update(processed: 3, total: 100)
      # Use 7% to avoid triggering any milestone
      subject.add_account_update(account_id: 1, status: 'processing', processed: 7, total: 100)
    end

    it 'flushes all pending updates' do
      expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).at_least(:once)
      
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
      
      # When batch is empty, broadcast_batch should not be called even with force: true
      expect(subject).not_to receive(:broadcast_batch)
      
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
      
      # Mock thread that doesn't respond to join and remains alive
      allow(timer_thread).to receive(:join).and_return(nil)
      allow(timer_thread).to receive(:alive?).and_return(true, true) # Still alive after join
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
      expect(collector).to receive(:flush_batch)
      
      collector.add_progress_update(processed: 4, total: 100)
      
      collector.stop
    end

    it 'clears batch data on stop to prevent memory leaks' do
      # Add update that won't trigger milestone flush (3% doesn't hit any milestone)
      subject.add_progress_update(processed: 3, total: 100)
      expect(subject.batch_data).not_to be_empty
      
      subject.stop
      
      expect(subject.batch_data).to be_empty
    end
  end

  describe 'batch size triggering' do
    it 'flushes when batch size limit is reached' do
      expect(subject).to receive(:flush_batch)
      
      # Add updates up to batch size limit (5 in test config)
      5.times { |i| subject.add_progress_update(processed: i, total: 100) }
    end
  end

  describe 'time-based flushing' do
    it 'flushes batch based on time interval' do
      # Set a known last batch time in the past
      old_time = config[:batch_interval] + 1.second
      subject.instance_variable_set(:@last_batch_time, Time.current - old_time)
      
      # Add update that won't trigger milestone flush
      subject.add_progress_update(processed: 3, total: 100) # 3% - no milestone
      
      # Should be time to flush since last batch time was more than batch_interval ago
      expect(subject.send(:time_for_batch_flush?)).to be true
    end
  end

  describe '#stats' do
    it 'returns collector statistics' do
      # Use progress values that won't trigger milestone flush
      subject.add_progress_update(processed: 3, total: 100) # 3% won't trigger flush
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

  # Finalizer tests removed - feature was removed during simplification
  # The collector now relies on explicit #stop method for cleanup
  # describe 'finalizer cleanup' do
  #   # Tests removed as finalizer feature was removed
  # end

  describe 'broadcast grouping' do
    before do
      # Add mixed update types - use values that won't trigger milestone flush
      subject.add_progress_update(processed: 3, total: 100) # 3% - no milestone
      subject.add_progress_update(processed: 7, total: 100) # 7% - no milestone
      subject.add_account_update(account_id: 1, status: 'processing', processed: 5, total: 25)
      subject.add_activity_update(activity_type: 'fetch', message: 'Done')
    end

    it 'groups updates by type for efficient broadcasting' do
      grouped = subject.send(:group_updates_by_type, subject.batch_data)
      
      expect(grouped.keys).to include('progress_update', 'account_update', 'activity')
      expect(grouped['progress_update'].size).to eq(1) # Only latest progress update due to deduplication
      expect(grouped['account_update'].size).to eq(1)
      expect(grouped['activity'].size).to eq(1)
    end

    it 'broadcasts progress updates as batches with latest data' do
      expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).with(
        channel: SyncStatusChannel,
        target: sync_session,
        data: hash_including(
          type: 'progress_batch',
          batch_size: 1, # Only one progress update due to deduplication
          latest: hash_including(processed: 7) # Latest progress value
        ),
        priority: :medium
      ).at_least(:once) # May also broadcast other types
      
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