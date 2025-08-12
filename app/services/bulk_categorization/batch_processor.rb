# frozen_string_literal: true

module BulkCategorization
  # Batch processor for memory-efficient bulk operations
  # Processes large datasets in configurable batch sizes to avoid memory issues
  class BatchProcessor
    BATCH_SIZE = 100
    MAX_MEMORY_MB = 512 # Maximum memory usage in MB

    attr_reader :total_processed, :errors, :batch_results

    def initialize(options = {})
      @batch_size = options[:batch_size] || BATCH_SIZE
      @max_memory = options[:max_memory_mb] || MAX_MEMORY_MB
      @total_processed = 0
      @errors = []
      @batch_results = []
      @start_time = Time.current
    end

    # Process expenses in batches
    def process_expenses(scope, &block)
      Rails.logger.info "Starting batch processing of #{scope.count} expenses"

      scope.find_in_batches(batch_size: @batch_size) do |batch|
        # Check memory usage before processing batch
        check_memory_usage

        # Process batch with error handling
        result = process_batch(batch, &block)
        @batch_results << result

        # Update progress
        @total_processed += batch.size
        log_progress

        # Garbage collection hint after each batch
        GC.start if @total_processed % (batch_size * 5) == 0
      end

      finalize_processing
    end

    # Process with streaming for real-time updates
    def process_with_streaming(scope, user_id, &block)
      channel = "user_#{user_id}_bulk_processing"

      scope.find_in_batches(batch_size: @batch_size).with_index do |batch, index|
        check_memory_usage

        result = process_batch(batch, &block)
        @batch_results << result
        @total_processed += batch.size

        # Stream progress update
        broadcast_progress(channel, index, batch.size)

        # Yield to allow other processes
        sleep(0.01) if index % 10 == 0
      end

      broadcast_completion(channel)
      finalize_processing
    end

    private

    def process_batch(batch)
      ActiveRecord::Base.transaction do
        yield(batch) if block_given?
        { batch_size: batch.size, success: true }
      end
    rescue StandardError => e
      log_batch_error(e, batch.size)
      { batch_size: batch.size, success: false, error: e.message }
    end

    def check_memory_usage
      memory_usage = current_memory_usage_mb

      if memory_usage > @max_memory
        Rails.logger.warn "Memory usage (#{memory_usage}MB) exceeds limit (#{@max_memory}MB)"

        # Force garbage collection
        GC.start(full_mark: true, immediate_sweep: true)

        # Wait a moment for GC to complete
        sleep(0.1)

        # Check again
        new_usage = current_memory_usage_mb
        if new_usage > @max_memory
          raise "Memory limit exceeded: #{new_usage}MB / #{@max_memory}MB"
        end
      end
    end

    def current_memory_usage_mb
      # Get current process memory usage
      if defined?(GetProcessMem)
        GetProcessMem.new.mb
      else
        # Fallback for systems without GetProcessMem
        `ps -o rss= -p #{Process.pid}`.to_i / 1024
      end
    end

    def log_progress
      elapsed = Time.current - @start_time
      rate = @total_processed / elapsed.to_f

      Rails.logger.info(
        {
          event: "batch_processing_progress",
          total_processed: @total_processed,
          errors: @errors.count,
          elapsed_seconds: elapsed.to_i,
          rate_per_second: rate.round(2),
          memory_mb: current_memory_usage_mb
        }.to_json
      )
    end

    def log_batch_error(error, batch_size)
      @errors << {
        message: error.message,
        batch_size: batch_size,
        timestamp: Time.current
      }

      Rails.logger.error(
        {
          event: "batch_processing_error",
          error: error.message,
          error_class: error.class.name,
          batch_size: batch_size,
          backtrace: error.backtrace&.first(3)
        }.to_json
      )
    end

    def broadcast_progress(channel, batch_index, batch_size)
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: "batch_progress",
        partial: "bulk_categorizations/batch_progress",
        locals: {
          batch_index: batch_index,
          total_processed: @total_processed,
          batch_size: batch_size,
          errors_count: @errors.count
        }
      )
    end

    def broadcast_completion(channel)
      Turbo::StreamsChannel.broadcast_append_to(
        channel,
        target: "notifications",
        partial: "shared/notification",
        locals: {
          message: "Batch processing completed: #{@total_processed} items processed",
          type: @errors.any? ? :warning : :success
        }
      )
    end

    def finalize_processing
      elapsed = Time.current - @start_time

      {
        success: @errors.empty?,
        total_processed: @total_processed,
        errors: @errors,
        batch_results: @batch_results,
        elapsed_seconds: elapsed.to_i,
        average_rate: (@total_processed / elapsed.to_f).round(2),
        final_memory_mb: current_memory_usage_mb
      }
    end
  end
end
