# frozen_string_literal: true

require "concurrent"

module Categorization
  # Thread-safe concurrent processor for batch operations
  # Implements Rails best practices for concurrent processing
  class ConcurrentProcessor
    include ActiveSupport::Benchmarkable

    attr_reader :logger, :executor

    # Initialize with configuration
    #
    # @param max_threads [Integer] Maximum number of threads (default: based on pool size)
    # @param queue_size [Integer] Size of the work queue (default: 100)
    # @param logger [Logger] Logger instance
    def initialize(max_threads: nil, queue_size: 100, logger: Rails.logger)
      @logger = logger

      # Calculate optimal thread count based on database pool
      pool_size = ActiveRecord::Base.connection_pool.size
      @max_threads = max_threads || [ pool_size - 1, 4 ].min
      @max_threads = [ @max_threads, 1 ].max

      # Create a thread pool executor with bounded queue
      # This prevents memory issues with large batches
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: @max_threads,
        max_queue: queue_size,
        fallback_policy: :caller_runs, # Execute in calling thread if queue is full
        idletime: 60 # Keep threads alive for 60 seconds
      )

      # Track active operations for graceful shutdown
      @active_operations = Concurrent::AtomicFixnum.new(0)
      @shutdown = Concurrent::AtomicBoolean.new(false)
    end

    # Process items concurrently with proper Rails integration
    #
    # @param items [Array] Items to process
    # @param options [Hash] Processing options
    # @yield [item] Block to process each item
    # @return [Array] Results in the same order as input
    def process_batch(items, options = {}, &block)
      return [] if items.blank?

      # Check if we're shutting down
      raise "Processor is shutting down" if @shutdown.value

      benchmark "concurrent_batch_processing" do
        results = Concurrent::Map.new
        futures = []

        items.each_with_index do |item, index|
          future = Concurrent::Future.execute(executor: @executor) do
            @active_operations.increment

            begin
              # Wrap in Rails executor for proper isolation
              Rails.application.executor.wrap do
                # Ensure database connection for this thread
                ActiveRecord::Base.connection_pool.with_connection do
                  # Process the item
                  result = yield(item)
                  results[index] = result
                  result
                end
              end
            rescue StandardError => e
              @logger.error "[ConcurrentProcessor] Error processing item: #{e.message}"
              @logger.debug e.backtrace.first(5).join("\n")

              # Store error result
              error_result = if defined?(CategorizationResult)
                CategorizationResult.error("Processing failed: #{e.message}")
              else
                { error: e.message }
              end

              results[index] = error_result
              error_result
            ensure
              @active_operations.decrement
            end
          end

          futures << future
        end

        # Wait for all futures with timeout
        timeout = options[:timeout] || 30.seconds
        start_time = Time.current

        futures.each do |future|
          remaining_time = timeout - (Time.current - start_time)

          if remaining_time > 0
            future.wait(remaining_time)
          else
            @logger.warn "[ConcurrentProcessor] Timeout waiting for futures"
            break
          end
        end

        # Cancel any incomplete futures
        futures.each do |future|
          future.cancel unless future.fulfilled?
        end

        # Return results in original order
        items.size.times.map { |i| results[i] }
      end
    end

    # Process with rate limiting to avoid overwhelming the system
    #
    # @param items [Array] Items to process
    # @param rate_limit [Integer] Maximum items per second
    # @yield [item] Block to process each item
    # @return [Array] Results
    def process_with_rate_limit(items, rate_limit: 10, &block)
      return [] if items.blank?

      # Calculate delay between items
      delay = 1.0 / rate_limit
      results = []

      items.each_slice(@max_threads) do |batch|
        batch_results = process_batch(batch, &block)
        results.concat(batch_results)

        # Rate limiting delay
        sleep(delay * batch.size) if delay > 0
      end

      results
    end

    # Gracefully shutdown the processor
    def shutdown(timeout: 5.seconds)
      @shutdown.make_true

      # Wait for active operations to complete
      start_time = Time.current
      while @active_operations.value > 0 && (Time.current - start_time) < timeout
        sleep 0.1
      end

      # Shutdown the executor
      @executor.shutdown
      @executor.wait_for_termination(timeout)

      if @executor.running?
        @logger.warn "[ConcurrentProcessor] Force killing executor after timeout"
        @executor.kill
      end
    end

    # Get current status
    def status
      {
        running: !@shutdown.value,
        active_operations: @active_operations.value,
        pool_size: @executor.max_length,
        queue_length: @executor.queue_length,
        completed_tasks: @executor.completed_task_count
      }
    end

    # Check if processor is healthy
    def healthy?
      !@shutdown.value && @executor.running?
    end
  end
end
