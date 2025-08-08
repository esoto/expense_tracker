# frozen_string_literal: true

require "concurrent"

# ProgressBatchCollector aggregates high-frequency progress updates to reduce
# ActionCable broadcast overhead. It collects updates and sends batched broadcasts
# based on configurable triggers (time intervals, update count, or critical messages).
#
# Key Features:
# - Time-based batching (every N seconds)
# - Count-based batching (every N updates)
# - Immediate broadcasting for critical messages
# - Intelligent deduplication of progress updates
# - Memory-efficient storage with automatic cleanup
# - Thread-safe operation for concurrent updates
#
# Usage:
#   # Initialize collector for a sync session
#   collector = ProgressBatchCollector.new(sync_session)
#
#   # Add progress updates (these will be batched)
#   collector.add_progress_update(processed: 150, total: 1000, detected: 25)
#   collector.add_account_update(account_id: 1, status: 'processing', processed: 50, total: 200)
#
#   # Send critical update immediately
#   collector.add_critical_update(type: 'error', message: 'Connection failed')
#
#   # Manually trigger batch send
#   collector.flush_batch
class ProgressBatchCollector
  include Concurrent::Async

  # Default configuration values
  DEFAULT_CONFIG = {
    batch_interval: 2.seconds,      # Maximum time between batches
    batch_size: 10,                 # Maximum updates per batch
    critical_immediate: true,       # Send critical updates immediately
    max_memory_updates: 100,        # Maximum updates to keep in memory
    cleanup_interval: 30.seconds    # Cleanup old batches interval
  }.freeze

  # Critical message types that bypass batching
  CRITICAL_MESSAGE_TYPES = %w[error failure completed connection_lost auth_failed].freeze

  attr_reader :sync_session, :config, :batch_data, :last_batch_time, :update_count

  def initialize(sync_session, config: {})
    @sync_session = sync_session
    @config = DEFAULT_CONFIG.merge(config)
    @batch_data = Concurrent::Hash.new
    @last_batch_time = Time.current
    @update_count = Concurrent::AtomicFixnum.new(0)
    @running = Concurrent::AtomicBoolean.new(true)
    @mutex = Mutex.new
    @timer_thread = nil
    @shutdown_complete = Concurrent::Promise.new

    # Set up finalizer for cleanup
    ObjectSpace.define_finalizer(self, self.class.finalizer(@timer_thread, @shutdown_complete))

    # Start background batch processing
    start_batch_timer

    Rails.logger.debug "[BATCH_COLLECTOR] Initialized for SyncSession##{sync_session.id}"
  end

  # Add a progress update to the batch
  # @param processed [Integer] Number of processed emails
  # @param total [Integer] Total number of emails
  # @param detected [Integer] Number of detected expenses
  # @param metadata [Hash] Additional metadata
  def add_progress_update(processed:, total:, detected: nil, metadata: {})
    return unless @running.value

    update_data = {
      type: "progress_update",
      processed: processed,
      total: total,
      detected: detected,
      metadata: metadata,
      timestamp: Time.current.to_f
    }

    add_to_batch(:progress, update_data)

    # Check if we should flush based on progress thresholds
    if should_flush_for_progress?(processed, total)
      async.flush_batch_async
    end
  end

  # Add an account-specific update to the batch
  # @param account_id [Integer] Account ID
  # @param status [String] Account status
  # @param processed [Integer] Processed emails for account
  # @param total [Integer] Total emails for account
  # @param detected [Integer] Detected expenses for account
  # @param metadata [Hash] Additional metadata
  def add_account_update(account_id:, status:, processed:, total:, detected: nil, metadata: {})
    return unless @running.value

    update_data = {
      type: "account_update",
      account_id: account_id,
      status: status,
      processed: processed,
      total: total,
      detected: detected,
      metadata: metadata,
      timestamp: Time.current.to_f
    }

    add_to_batch("account_#{account_id}", update_data)
  end

  # Add a critical update that should be sent immediately
  # @param type [String] Update type
  # @param message [String] Update message
  # @param data [Hash] Additional data
  def add_critical_update(type:, message:, data: {})
    return unless @running.value

    update_data = {
      type: type,
      message: message,
      data: data,
      timestamp: Time.current.to_f,
      critical: true
    }

    if @config[:critical_immediate] && is_critical_message?(type)
      # Send immediately for critical messages
      broadcast_critical_update(update_data)
    else
      add_to_batch(:critical, update_data)
      async.flush_batch_async
    end
  end

  # Add an activity update to the batch
  # @param activity_type [String] Type of activity
  # @param message [String] Activity message
  # @param metadata [Hash] Additional metadata
  def add_activity_update(activity_type:, message:, metadata: {})
    return unless @running.value

    update_data = {
      type: "activity",
      activity_type: activity_type,
      message: message,
      metadata: metadata,
      timestamp: Time.current.to_f
    }

    add_to_batch(:activity, update_data)
  end

  # Manually flush all pending updates
  # @param force [Boolean] Force flush even if batch is small
  def flush_batch(force: false)
    return if @batch_data.empty? && !force

    @mutex.synchronize do
      current_batch = extract_current_batch
      return if current_batch.empty?

      begin
        broadcast_batch(current_batch)
        @last_batch_time = Time.current

        Rails.logger.debug "[BATCH_COLLECTOR] Flushed batch with #{current_batch.size} updates for SyncSession##{sync_session.id}"
      rescue StandardError => e
        Rails.logger.error "[BATCH_COLLECTOR] Failed to flush batch: #{e.message}"
        # Re-add failed updates back to batch for retry
        restore_failed_batch(current_batch)
      end
    end
  end

  # Flush batch asynchronously
  def flush_batch_async
    flush_batch
  end

  # Stop the batch collector and flush any remaining updates
  def stop
    return unless @running.value

    @running.make_false

    # Flush any pending updates before stopping
    flush_batch(force: true)

    # Stop the timer thread gracefully
    stop_timer_thread

    # Clear batch data to free memory
    @batch_data.clear

    # Mark shutdown as complete
    @shutdown_complete.set(true)

    Rails.logger.debug "[BATCH_COLLECTOR] Stopped for SyncSession##{sync_session.id}"
  end

  # Get batch collector statistics
  # @return [Hash] Statistics about the collector
  def stats
    {
      sync_session_id: sync_session.id,
      pending_updates: @batch_data.size,
      total_updates_processed: @update_count.value,
      last_batch_time: @last_batch_time,
      running: @running.value,
      config: @config
    }
  end

  # Check if the collector is active
  # @return [Boolean] True if collector is running
  def active?
    @running.value
  end

  # Class method to create finalizer for memory cleanup
  # @param timer_thread [Thread] Timer thread to cleanup
  # @param shutdown_promise [Concurrent::Promise] Shutdown promise
  # @return [Proc] Finalizer proc
  def self.finalizer(timer_thread, shutdown_promise)
    proc do
      begin
        # Try to stop timer thread if it's still alive
        if timer_thread&.alive?
          timer_thread.terminate
        end

        # Mark shutdown as complete if not already done
        unless shutdown_promise.fulfilled?
          shutdown_promise.set(true)
        end
      rescue StandardError => e
        # Log errors but don't raise in finalizer
        Rails.logger.error "[BATCH_COLLECTOR] Finalizer error: #{e.message}" if defined?(Rails)
      end
    end
  end

  private

  # Add an update to the batch with deduplication
  # @param key [Symbol, String] Batch key for deduplication
  # @param data [Hash] Update data
  def add_to_batch(key, data)
    @mutex.synchronize do
      @batch_data[key] = data
      @update_count.increment

      # Prevent memory bloat by enforcing max batch size
      if @batch_data.size > @config[:max_memory_updates]
        Rails.logger.warn "[BATCH_COLLECTOR] Memory limit reached (#{@batch_data.size} updates), forcing flush"
        async.flush_batch_async
      end
    end

    # Check if we should flush based on batch size
    if @batch_data.size >= @config[:batch_size]
      async.flush_batch_async
    end
  end

  # Extract current batch data and clear the batch
  # @return [Hash] Current batch data
  def extract_current_batch
    current_batch = @batch_data.dup
    @batch_data.clear
    current_batch
  end

  # Restore failed batch data for retry
  # @param failed_batch [Hash] Batch that failed to send
  def restore_failed_batch(failed_batch)
    failed_batch.each do |key, data|
      @batch_data[key] = data
    end
  end

  # Broadcast a batch of updates
  # @param batch [Hash] Batch data to broadcast
  def broadcast_batch(batch)
    return if batch.empty?

    # Group updates by type for efficient broadcasting
    grouped_updates = group_updates_by_type(batch)

    grouped_updates.each do |update_type, updates|
      broadcast_grouped_updates(update_type, updates)
    end
  end

  # Broadcast a critical update immediately
  # @param update_data [Hash] Critical update data
  def broadcast_critical_update(update_data)
    begin
      BroadcastReliabilityService.broadcast_with_retry(
        channel: SyncStatusChannel,
        target: sync_session,
        data: update_data,
        priority: :critical
      )

      Rails.logger.info "[BATCH_COLLECTOR] Sent critical update: #{update_data[:type]} for SyncSession##{sync_session.id}"
    rescue StandardError => e
      Rails.logger.error "[BATCH_COLLECTOR] Failed to send critical update: #{e.message}"
    end
  end

  # Group batch updates by type for efficient processing
  # @param batch [Hash] Batch data
  # @return [Hash] Grouped updates
  def group_updates_by_type(batch)
    grouped = Hash.new { |h, k| h[k] = [] }

    batch.each_value do |update_data|
      update_type = update_data[:type]
      grouped[update_type] << update_data
    end

    grouped
  end

  # Broadcast grouped updates of the same type
  # @param update_type [String] Type of updates
  # @param updates [Array<Hash>] Array of update data
  def broadcast_grouped_updates(update_type, updates)
    case update_type
    when "progress_update"
      broadcast_progress_batch(updates)
    when "account_update"
      broadcast_account_batch(updates)
    when "activity"
      broadcast_activity_batch(updates)
    else
      # For other types, send individually
      updates.each { |update| broadcast_individual_update(update) }
    end
  end

  # Broadcast batched progress updates
  # @param updates [Array<Hash>] Progress updates
  def broadcast_progress_batch(updates)
    # Use the most recent progress update
    latest_update = updates.max_by { |u| u[:timestamp] }

    BroadcastReliabilityService.broadcast_with_retry(
      channel: SyncStatusChannel,
      target: sync_session,
      data: {
        type: "progress_batch",
        batch_size: updates.size,
        latest: latest_update,
        timestamp: Time.current.iso8601
      },
      priority: :medium
    )
  end

  # Broadcast batched account updates
  # @param updates [Array<Hash>] Account updates
  def broadcast_account_batch(updates)
    # Group by account_id and use latest update for each account
    account_updates = updates.group_by { |u| u[:account_id] }
                            .transform_values { |updates| updates.max_by { |u| u[:timestamp] } }

    account_updates.each do |account_id, update|
      BroadcastReliabilityService.broadcast_with_retry(
        channel: SyncStatusChannel,
        target: sync_session,
        data: update.merge(type: "account_update"),
        priority: :medium
      )
    end
  end

  # Broadcast batched activity updates
  # @param updates [Array<Hash>] Activity updates
  def broadcast_activity_batch(updates)
    BroadcastReliabilityService.broadcast_with_retry(
      channel: SyncStatusChannel,
      target: sync_session,
      data: {
        type: "activity_batch",
        activities: updates.map { |u| u.except(:type) },
        count: updates.size,
        timestamp: Time.current.iso8601
      },
      priority: :low
    )
  end

  # Broadcast an individual update
  # @param update [Hash] Update data
  def broadcast_individual_update(update)
    priority = update[:critical] ? :high : :medium

    BroadcastReliabilityService.broadcast_with_retry(
      channel: SyncStatusChannel,
      target: sync_session,
      data: update,
      priority: priority
    )
  end

  # Check if a message type is critical
  # @param message_type [String] Message type
  # @return [Boolean] True if critical
  def is_critical_message?(message_type)
    CRITICAL_MESSAGE_TYPES.include?(message_type.to_s)
  end

  # Check if we should flush based on progress milestones
  # @param processed [Integer] Processed count
  # @param total [Integer] Total count
  # @return [Boolean] True if should flush
  def should_flush_for_progress?(processed, total)
    return false if total <= 0

    progress_percentage = (processed.to_f / total * 100).round

    # Flush at certain progress milestones
    milestone_percentages = [ 10, 25, 50, 75, 90, 100 ]
    milestone_percentages.any? { |milestone| progress_percentage >= milestone }
  end

  # Start the background timer for batch processing
  def start_batch_timer
    return unless @config[:batch_interval] > 0

    @timer_thread = Thread.new do
      Thread.current.name = "batch_collector_#{sync_session.id}"

      begin
        while @running.value
          sleep(@config[:batch_interval])

          if @running.value && time_for_batch_flush?
            async.flush_batch_async
          end
        end
      rescue StandardError => e
        Rails.logger.error "[BATCH_COLLECTOR] Timer thread error: #{e.message}"
      ensure
        Rails.logger.debug "[BATCH_COLLECTOR] Timer thread exiting for SyncSession##{sync_session.id}"
      end
    end
  end

  # Stop the timer thread gracefully
  def stop_timer_thread
    return unless @timer_thread&.alive?

    begin
      # Give the thread time to finish current iteration
      @timer_thread.join(5.seconds)

      # Force terminate if still alive
      if @timer_thread.alive?
        Rails.logger.warn "[BATCH_COLLECTOR] Force terminating timer thread for SyncSession##{sync_session.id}"
        @timer_thread.terminate
      end
    rescue StandardError => e
      Rails.logger.error "[BATCH_COLLECTOR] Error stopping timer thread: #{e.message}"
    ensure
      @timer_thread = nil
    end
  end

  # Check if it's time to flush based on time interval
  # @return [Boolean] True if time to flush
  def time_for_batch_flush?
    Time.current - @last_batch_time >= @config[:batch_interval]
  end
end
