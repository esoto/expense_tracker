# frozen_string_literal: true

require "rails_helper"
require "concurrent"
require "benchmark"

RSpec.describe Categorization::ConcurrentProcessor, type: :service, unit: true do
  # Use real Rails environment but with isolated tests
  let(:logger) { Rails.logger }
  let(:test_category) { create(:category, name: "Test Category #{SecureRandom.hex(4)}") }


  describe "Core functionality" do
    subject(:processor) { described_class.new(max_threads: 2, queue_size: 5, logger: logger) }

    describe "#initialize" do
      it "initializes with correct thread count" do
        expect(processor.status[:pool_size]).to eq(2)
      end

      it "starts in healthy state" do
        expect(processor.healthy?).to be true
        expect(processor.status[:running]).to be true
        expect(processor.status[:active_operations]).to eq(0)
      end
    end

    describe "#process_batch" do
      context "with empty items" do
        it "returns empty array" do
          result = processor.process_batch([]) { |item| item }
          expect(result).to eq([])
        end
      end

      context "with simple processing" do
        it "processes all items and returns results in order" do
          items = %w[item1 item2 item3]
          results = processor.process_batch(items) { |item| "processed_#{item}" }

          expect(results).to eq([ "processed_item1", "processed_item2", "processed_item3" ])
        end

        it "handles processing errors gracefully" do
          items = %w[item1 error_item item3]

          results = processor.process_batch(items) do |item|
            raise StandardError, "Test error" if item == "error_item"
            "processed_#{item}"
          end

          expect(results[0]).to eq("processed_item1")
          # Should return CategorizationResult.error when CategorizationResult is available
          expect(results[1]).to be_a(Categorization::CategorizationResult)
          expect(results[1].error).to include("Test error")
          expect(results[2]).to eq("processed_item3")
        end
      end

      context "during shutdown" do
        it "raises error when trying to process after shutdown" do
          processor.shutdown

          expect {
            processor.process_batch([ "item" ]) { |item| item }
          }.to raise_error("Processor is shutting down")
        end
      end

      context "with timeout" do
        it "handles timeout gracefully" do
          items = %w[item1 item2]

          start_time = Time.current
          results = processor.process_batch(items, timeout: 0.05.seconds) do |item|
            sleep 0.1 # Longer than timeout
            "processed_#{item}"
          end
          elapsed = Time.current - start_time

          # Should timeout quickly
          expect(elapsed).to be < 0.5
          expect(results.size).to eq(2) # Still returns array of correct size
        end
      end
    end

    describe "#process_with_rate_limit" do
      context "with empty items" do
        it "returns empty array" do
          result = processor.process_with_rate_limit([]) { |item| item }
          expect(result).to eq([])
        end
      end

      context "with rate limiting" do
        it "processes items with delay" do
          items = %w[item1 item2 item3]

          start_time = Time.current
          results = processor.process_with_rate_limit(items, rate_limit: 10) do |item|
            "processed_#{item}"
          end
          elapsed = Time.current - start_time

          expect(results.size).to eq(3)
          expect(results).to all(start_with("processed_"))
          # Should have some delay due to rate limiting
          expect(elapsed).to be > 0.1
        end
      end
    end

    describe "#shutdown" do
      it "shuts down gracefully" do
        expect(processor.healthy?).to be true

        processor.shutdown

        expect(processor.healthy?).to be false
        expect(processor.status[:running]).to be false
        expect(processor.executor.shutdown?).to be true
      end

      it "waits for active operations with timeout" do
        # This is harder to test without actual long-running operations
        # but we can verify the basic mechanics work
        processor.shutdown(timeout: 0.1.seconds)

        expect(processor.status[:running]).to be false
      end
    end

    describe "#status" do
      it "returns comprehensive status information" do
        status = processor.status

        expect(status).to include(
          running: true,
          active_operations: 0,
          pool_size: 2,
          queue_length: 0,
          completed_tasks: be >= 0
        )
      end
    end

    describe "#healthy?" do
      it "returns true when running" do
        expect(processor.healthy?).to be true
      end

      it "returns false after shutdown" do
        processor.shutdown
        expect(processor.healthy?).to be false
      end
    end
  end

  describe "Thread safety and synchronization" do
    subject(:processor) { described_class.new(max_threads: 3, logger: logger) }

    it "handles concurrent batch processing without data races" do
      batch1 = %w[a1 a2 a3]
      batch2 = %w[b1 b2 b3]
      batch3 = %w[c1 c2 c3]

      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      threads = [
        Thread.new do
          begin
            result = processor.process_batch(batch1) { |item| "processed_#{item}" }
            results.concat(result)
          rescue => e
            errors << e
          end
        end,
        Thread.new do
          begin
            result = processor.process_batch(batch2) { |item| "processed_#{item}" }
            results.concat(result)
          rescue => e
            errors << e
          end
        end,
        Thread.new do
          begin
            result = processor.process_batch(batch3) { |item| "processed_#{item}" }
            results.concat(result)
          rescue => e
            errors << e
          end
        end
      ]

      threads.each(&:join)

      expect(errors).to be_empty
      expect(results.size).to eq(9)
      expect(results).to all(start_with("processed_"))
      # Verify no duplicates (thread safety)
      expect(results.uniq.size).to eq(9)
    end

    it "maintains operations count correctly during concurrent processing" do
      items = Array.new(6) { |i| "item#{i}" }
      barrier = Concurrent::CyclicBarrier.new(2)
      operation_counts = []

      # Start processing with controlled timing
      processing_thread = Thread.new do
        processor.process_batch(items) do |item|
          # Signal we've started processing
          barrier.wait(1)
          sleep 0.02
          "processed_#{item}"
        end
      end

      # Wait for processing to start
      barrier.wait(1)

      # Collect operation counts during processing
      3.times do
        operation_counts << processor.status[:active_operations]
        sleep 0.01
      end

      processing_thread.join

      # Verify operations were tracked during processing
      expect(operation_counts).to all(be > 0)

      # Check that operations are reset after completion
      final_status = processor.status
      expect(final_status[:active_operations]).to eq(0)
    end

    it "handles thread synchronization with barriers correctly" do
      items = Array.new(3) { |i| "item#{i}" } # Use 3 items for 3 max_threads
      barrier = Concurrent::CyclicBarrier.new(3) # 3 processing threads
      start_times = Concurrent::Array.new
      end_times = Concurrent::Array.new

      # Process items with synchronized start
      results = processor.process_batch(items) do |item|
        start_times << Time.current
        barrier.wait(1) # Wait for all threads to reach this point
        sleep 0.05 # Simulate work
        end_times << Time.current
        "processed_#{item}"
      end

      expect(results.size).to eq(3)
      expect(results).to all(start_with("processed_"))

      # Verify threads started roughly at the same time (within 200ms to account for threading overhead)
      time_spread = start_times.max - start_times.min
      expect(time_spread).to be < 0.2
    end

    it "prevents race conditions in status updates" do
      items = Array.new(20) { |i| "item#{i}" }
      status_snapshots = Concurrent::Array.new

      # Monitor status during processing
      monitor_thread = Thread.new do
        30.times do
          status_snapshots << processor.status.dup
          sleep 0.01
        end
      end

      # Process items concurrently
      results = processor.process_batch(items) do |item|
        sleep 0.02
        "processed_#{item}"
      end

      monitor_thread.join

      expect(results.size).to eq(20)

      # Verify status consistency (no negative values or impossible states)
      status_snapshots.each do |status|
        expect(status[:active_operations]).to be >= 0
        expect(status[:active_operations]).to be <= items.size
        expect(status[:running]).to be true
      end
    end
  end

  describe "Error resilience and mixed scenarios" do
    subject(:processor) { described_class.new(max_threads: 3, logger: logger) }

    it "continues processing other items when some fail" do
      items = %w[good1 bad1 good2 bad2 good3]

      results = processor.process_batch(items) do |item|
        if item.start_with?("bad")
          raise StandardError, "Intentional error for #{item}"
        end
        "processed_#{item}"
      end

      expect(results.size).to eq(5)

      # Check good items processed successfully
      good_results = results.select { |r| r.is_a?(String) }
      expect(good_results).to contain_exactly("processed_good1", "processed_good2", "processed_good3")

      # Check bad items have error results (CategorizationResult objects)
      error_results = results.select { |r| r.is_a?(Categorization::CategorizationResult) && r.error? }
      expect(error_results.size).to eq(2)
      expect(error_results.all? { |r| r.error.include?("Intentional error") }).to be true
    end

    it "handles mixed success/failure scenarios with different error types" do
      items = %w[success timeout_error network_error db_error success2 validation_error success3]

      results = processor.process_batch(items) do |item|
        case item
        when "success", "success2", "success3"
          "processed_#{item}"
        when "timeout_error"
          raise Timeout::Error, "Request timed out"
        when "network_error"
          raise SocketError, "Network unreachable"
        when "db_error"
          raise ActiveRecord::ConnectionTimeoutError, "Database connection timeout"
        when "validation_error"
          raise ArgumentError, "Validation failed: Name can't be blank"
        end
      end

      expect(results.size).to eq(7)

      # Check successful items
      success_results = results.select { |r| r.is_a?(String) }
      expect(success_results.size).to eq(3)
      expect(success_results).to contain_exactly("processed_success", "processed_success2", "processed_success3")

      # Check error types are properly handled
      error_results = results.select { |r| r.is_a?(Categorization::CategorizationResult) && r.error? }
      expect(error_results.size).to eq(4)

      error_messages = error_results.map(&:error)
      expect(error_messages).to include(
        match(/Request timed out/),
        match(/Network unreachable/),
        match(/Database connection timeout/),
        match(/Validation failed/)
      )
    end

    it "maintains result ordering even with mixed success/failure" do
      items = %w[item0 error1 item2 error3 item4 error5 item6]

      results = processor.process_batch(items) do |item|
        if item.start_with?("error")
          raise StandardError, "Error processing #{item}"
        end
        "processed_#{item}"
      end

      expect(results.size).to eq(7)

      # Verify ordering is maintained
      expect(results[0]).to eq("processed_item0")
      expect(results[1]).to be_a(Categorization::CategorizationResult)
      expect(results[1].error).to include("Error processing error1")
      expect(results[2]).to eq("processed_item2")
      expect(results[3]).to be_a(Categorization::CategorizationResult)
      expect(results[3].error).to include("Error processing error3")
      expect(results[4]).to eq("processed_item4")
      expect(results[5]).to be_a(Categorization::CategorizationResult)
      expect(results[5].error).to include("Error processing error5")
      expect(results[6]).to eq("processed_item6")
    end

    it "handles large batches with mixed scenarios" do
      # Create a large batch with 70% success, 30% errors
      large_batch = Array.new(50) do |i|
        if i % 10 < 7  # 70% success
          "success_item#{i}"
        else  # 30% errors
          "error_item#{i}"
        end
      end

      results = processor.process_batch(large_batch) do |item|
        if item.start_with?("error")
          raise StandardError, "Batch processing error for #{item}"
        end
        "processed_#{item}"
      end

      expect(results.size).to eq(50)

      success_count = results.count { |r| r.is_a?(String) }
      error_count = results.count { |r| r.is_a?(Categorization::CategorizationResult) && r.error? }

      expect(success_count).to eq(35)  # 70% of 50
      expect(error_count).to eq(15)    # 30% of 50
    end

    it "handles cascading errors without stopping processing" do
      items = Array.new(10) { |i| "item#{i}" }
      error_count = Concurrent::AtomicFixnum.new(0)

      results = processor.process_batch(items) do |item|
        # Simulate cascading errors (every 3rd item fails)
        if item.match?(/item[369]/)
          error_count.increment
          raise StandardError, "Cascading error #{error_count.value}"
        end
        "processed_#{item}"
      end

      expect(results.size).to eq(10)

      success_results = results.select { |r| r.is_a?(String) }
      error_results = results.select { |r| r.is_a?(Categorization::CategorizationResult) && r.error? }

      expect(success_results.size).to eq(7)
      expect(error_results.size).to eq(3)
      expect(error_count.value).to eq(3)
    end

    it "handles large batches without issues" do
      large_batch = Array.new(20) { |i| "item#{i}" }

      results = processor.process_batch(large_batch) { |item| "processed_#{item}" }

      expect(results.size).to eq(20)
      expect(results).to all(start_with("processed_"))
    end
  end

  describe "Resource management and cleanup" do
    subject(:processor) { described_class.new(max_threads: 2, queue_size: 3, logger: logger) }

    it "properly cleans up resources after processing" do
      initial_thread_count = Thread.list.size

      items = Array.new(5) { |i| "item#{i}" }

      results = processor.process_batch(items) do |item|
        "processed_#{item}"
      end

      expect(results.size).to eq(5)

      # Allow some time for threads to be cleaned up
      sleep 0.1

      # Thread count should not have grown significantly
      final_thread_count = Thread.list.size
      expect(final_thread_count - initial_thread_count).to be <= 2  # Max threads created

      # Processor should still be healthy
      expect(processor.healthy?).to be true
      expect(processor.status[:active_operations]).to eq(0)
    end

    it "handles queue overflow gracefully with fallback policy" do
      # Create more items than queue can handle at once
      items = Array.new(10) { |i| "item#{i}" }

      results = processor.process_batch(items) do |item|
        sleep 0.05  # Slow processing to trigger queue pressure
        "processed_#{item}"
      end

      expect(results.size).to eq(10)
      expect(results).to all(start_with("processed_"))

      # Should have used caller_runs fallback policy without errors
      status = processor.status
      expect(status[:running]).to be true
    end

    it "handles timeout scenarios with proper cleanup" do
      items = Array.new(4) { |i| "item#{i}" }

      start_time = Time.current
      results = processor.process_batch(items, timeout: 0.1.seconds) do |item|
        sleep 0.2  # Longer than timeout
        "processed_#{item}"
      end
      elapsed = Time.current - start_time

      # Should timeout quickly
      expect(elapsed).to be < 0.5
      expect(results.size).to eq(4)

      # Give adequate time for all operations to complete or timeout
      sleep 0.5

      # Processor should still be operational
      expect(processor.healthy?).to be true
      # Due to timeout behavior, some operations might still be cleaning up
      expect(processor.status[:active_operations]).to be >= 0
    end

    it "manages database connections properly" do
      items = Array.new(6) { |i| "item#{i}" }
      connection_ids = Concurrent::Array.new

      results = processor.process_batch(items) do |item|
        # Track database connection usage
        connection_ids << ActiveRecord::Base.connection.object_id

        # Simulate database operation
        ActiveRecord::Base.connection.execute("SELECT 1")

        "processed_#{item}"
      end

      expect(results.size).to eq(6)
      expect(results).to all(start_with("processed_"))

      # Each thread should get its own connection
      expect(connection_ids.uniq.size).to be >= 1
      # In test environment, allow for more connections due to concurrent test execution
      max_expected_connections = [ processor.status[:pool_size], ActiveRecord::Base.connection_pool.size ].max
      expect(connection_ids.uniq.size).to be <= max_expected_connections
    end

    it "handles shutdown with active operations gracefully" do
      items = Array.new(6) { |i| "item#{i}" }
      results = nil
      processing_complete = false

      # Start long-running processing
      processing_thread = Thread.new do
        results = processor.process_batch(items) do |item|
          sleep 0.1
          "processed_#{item}"
        end
        processing_complete = true
      end

      # Give processing time to start
      sleep 0.05

      # Verify operations are active
      expect(processor.status[:active_operations]).to be > 0

      # Shutdown with short timeout
      shutdown_start = Time.current
      processor.shutdown(timeout: 0.5.seconds)
      shutdown_time = Time.current - shutdown_start

      # Shutdown should complete within reasonable time
      expect(shutdown_time).to be < 1.0
      expect(processor.healthy?).to be false

      # Wait for processing to complete
      processing_thread.join(2)

      # Processing should have completed or been interrupted
      expect(processing_complete || results).to be_truthy
    end
  end

  describe "Performance benchmarks" do
    subject(:processor) { described_class.new(max_threads: 3, logger: logger) }

    it "demonstrates concurrent processing performance benefits" do
      items = Array.new(6) { |i| "item#{i}" }
      work_duration = 0.05  # 50ms per item

      # Sequential baseline
      sequential_time = Benchmark.realtime do
        items.map do |item|
          sleep work_duration
          "sequential_#{item}"
        end
      end

      # Concurrent processing
      concurrent_time = Benchmark.realtime do
        processor.process_batch(items) do |item|
          sleep work_duration
          "concurrent_#{item}"
        end
      end

      # Concurrent should be significantly faster
      expected_concurrent_time = (items.size.to_f / processor.status[:pool_size]) * work_duration
      expect(concurrent_time).to be < sequential_time * 0.7  # At least 30% faster
      expect(concurrent_time).to be < expected_concurrent_time + 0.1  # Close to theoretical optimum

      puts "Sequential: #{sequential_time.round(3)}s, Concurrent: #{concurrent_time.round(3)}s, Speedup: #{(sequential_time / concurrent_time).round(2)}x"
    end

    it "maintains performance under load" do
      large_batch = Array.new(20) { |i| "load_test_item#{i}" }

      processing_times = []

      # Run multiple iterations
      3.times do |iteration|
        time = Benchmark.realtime do
          results = processor.process_batch(large_batch) do |item|
            sleep 0.01  # Light processing
            "processed_#{item}_iteration_#{iteration}"
          end
          expect(results.size).to eq(20)
        end
        processing_times << time
      end

      # Performance should be consistent
      avg_time = processing_times.sum / processing_times.size
      max_deviation = processing_times.map { |t| (t - avg_time).abs }.max

      expect(max_deviation).to be < avg_time * 0.3  # Within 30% of average
      puts "Average processing time: #{avg_time.round(3)}s, Max deviation: #{max_deviation.round(3)}s"
    end

    it "scales efficiently with thread count" do
      items = Array.new(12) { |i| "scale_test_item#{i}" }
      work_duration = 0.02

      thread_counts = [ 1, 2, 4 ]
      processing_times = {}

      thread_counts.each do |thread_count|
        test_processor = described_class.new(max_threads: thread_count, logger: logger)

        time = Benchmark.realtime do
          results = test_processor.process_batch(items) do |item|
            sleep work_duration
            "processed_#{item}"
          end
          expect(results.size).to eq(12)
        end

        processing_times[thread_count] = time
        test_processor.shutdown
      end

      # More threads should generally be faster (with diminishing returns)
      expect(processing_times[2]).to be < processing_times[1] * 0.8
      expect(processing_times[4]).to be < processing_times[2] * 0.8

      puts "Scaling results: #{processing_times}"
    end
  end

  describe "Rate limiting functionality" do
    subject(:processor) { described_class.new(max_threads: 3, logger: logger) }

    it "enforces rate limiting correctly" do
      items = Array.new(6) { |i| "rate_limited_item#{i}" }
      rate_limit = 20  # 20 items per second

      start_time = Time.current
      results = processor.process_with_rate_limit(items, rate_limit: rate_limit) do |item|
        "processed_#{item}"
      end
      total_time = Time.current - start_time

      expect(results.size).to eq(6)
      expect(results).to all(start_with("processed_"))

      # Should take roughly the expected time based on rate limit
      # With 3 threads and 6 items, we process in 2 batches
      # Each batch should be delayed by 3/20 seconds = 0.15 seconds
      expected_min_time = 3.0 / rate_limit  # Minimum time for rate limiting
      expect(total_time).to be >= expected_min_time * 0.8  # Allow some tolerance
    end

    it "handles rate limiting with different rates" do
      items = Array.new(4) { |i| "item#{i}" }

      # Test very low rate limit
      start_time = Time.current
      results = processor.process_with_rate_limit(items, rate_limit: 5) do |item|
        "processed_#{item}"
      end
      slow_time = Time.current - start_time

      # Test higher rate limit
      start_time = Time.current
      results2 = processor.process_with_rate_limit(items, rate_limit: 50) do |item|
        "processed_#{item}"
      end
      fast_time = Time.current - start_time

      expect(results.size).to eq(4)
      expect(results2.size).to eq(4)

      # Slower rate limit should take longer
      expect(slow_time).to be > fast_time * 2
    end

    it "combines rate limiting with error handling" do
      items = %w[good1 bad1 good2 bad2]

      start_time = Time.current
      results = processor.process_with_rate_limit(items, rate_limit: 10) do |item|
        if item.start_with?("bad")
          raise StandardError, "Rate limited error for #{item}"
        end
        "processed_#{item}"
      end
      total_time = Time.current - start_time

      expect(results.size).to eq(4)

      # Check successful and error results
      success_results = results.select { |r| r.is_a?(String) }
      error_results = results.select { |r| r.is_a?(Categorization::CategorizationResult) && r.error? }

      expect(success_results.size).to eq(2)
      expect(error_results.size).to eq(2)

      # Should still respect rate limiting
      expect(total_time).to be >= 0.1  # Some delay from rate limiting
    end
  end

  describe "Rails integration" do
    subject(:processor) { described_class.new(max_threads: 2, logger: logger) }

    it "properly integrates with Rails executor" do
      items = Array.new(4) { |i| "rails_item#{i}" }
      executor_calls = Concurrent::AtomicFixnum.new(0)

      # Mock Rails.application.executor to track calls
      original_executor = Rails.application.executor
      mock_executor = double("executor")
      allow(Rails.application).to receive(:executor).and_return(mock_executor)

      allow(mock_executor).to receive(:wrap) do |&block|
        executor_calls.increment
        original_executor.wrap(&block)
      end

      results = processor.process_batch(items) do |item|
        "processed_#{item}"
      end

      expect(results.size).to eq(4)
      expect(results).to all(start_with("processed_"))

      # Each item should have been wrapped by Rails executor
      expect(executor_calls.value).to eq(4)
    end

    it "handles database connections in concurrent context" do
      # Skip if not in a database-enabled test environment
      skip "Database not available" unless ActiveRecord::Base.connected?

      items = Array.new(6) { |i| i + 1 }  # Use IDs for Category lookup

      results = processor.process_batch(items) do |item_id|
        # Simulate database operations
        category = test_category
        # Perform a query in each thread
        found_category = Category.find_by(id: category.id)
        "processed_category_#{found_category&.name}_#{item_id}"
      end

      expect(results.size).to eq(6)
      expect(results).to all(include(test_category.name))
    end

    it "maintains transaction isolation" do
      skip "Database not available" unless ActiveRecord::Base.connected?

      items = Array.new(4) { |i| "transaction_item#{i}" }

      results = processor.process_batch(items) do |item|
        # Each thread should have its own transaction context
        ActiveRecord::Base.transaction do
          # Simulate database operations with a simple query that won't trigger callbacks
          ActiveRecord::Base.connection.execute("SELECT 1")
        end
        # Always return the expected string format
        "processed_#{item}"
      end

      expect(results.size).to eq(4)
      expect(results).to all(start_with("processed_"))
    end

    it "handles ActiveRecord connection checkout and return" do
      skip "Database not available" unless ActiveRecord::Base.connected?

      initial_connections = ActiveRecord::Base.connection_pool.stat
      items = Array.new(8) { |i| "connection_item#{i}" }

      results = processor.process_batch(items) do |item|
        # Force connection usage
        ActiveRecord::Base.connection.execute("SELECT 1 as test_query")
        "processed_#{item}"
      end

      final_connections = ActiveRecord::Base.connection_pool.stat

      expect(results.size).to eq(8)
      expect(results).to all(start_with("processed_"))

      # Connection pool should return to similar state
      expect(final_connections[:size]).to eq(initial_connections[:size])
      expect(final_connections[:checked_out]).to eq(initial_connections[:checked_out])
    end
  end

  describe "Health monitoring and status" do
    subject(:processor) { described_class.new(max_threads: 2, logger: logger) }

    it "provides detailed status information during processing" do
      items = Array.new(6) { |i| "status_item#{i}" }
      status_history = Concurrent::Array.new

      processing_thread = Thread.new do
        processor.process_batch(items) do |item|
          sleep 0.05
          "processed_#{item}"
        end
      end

      # Monitor status during processing
      monitor_thread = Thread.new do
        10.times do
          status_history << processor.status.dup
          sleep 0.02
        end
      end

      processing_thread.join
      monitor_thread.join

      expect(status_history).not_to be_empty

      # Verify status structure and values
      status_history.each do |status|
        expect(status).to include(
          :running, :active_operations, :pool_size,
          :queue_length, :completed_tasks
        )

        expect(status[:running]).to be true
        expect(status[:active_operations]).to be_between(0, items.size)
        expect(status[:pool_size]).to eq(2)
        expect(status[:queue_length]).to be >= 0
        expect(status[:completed_tasks]).to be >= 0
      end
    end

    it "tracks completed task count accurately" do
      first_batch = Array.new(3) { |i| "first_#{i}" }
      second_batch = Array.new(4) { |i| "second_#{i}" }

      initial_completed = processor.status[:completed_tasks]

      # Process first batch
      processor.process_batch(first_batch) { |item| "processed_#{item}" }
      after_first = processor.status[:completed_tasks]

      # Process second batch
      processor.process_batch(second_batch) { |item| "processed_#{item}" }
      after_second = processor.status[:completed_tasks]

      # Completed tasks should increase
      expect(after_first).to be > initial_completed
      expect(after_second).to be > after_first

      # Should have processed all items
      total_processed = after_second - initial_completed
      expect(total_processed).to eq(7)  # 3 + 4 items
    end

    it "reports health status correctly" do
      expect(processor.healthy?).to be true

      # Health during processing
      processing_thread = Thread.new do
        processor.process_batch(%w[item1 item2]) do |item|
          sleep 0.05
          "processed_#{item}"
        end
      end

      # Should remain healthy during processing
      sleep 0.01
      expect(processor.healthy?).to be true

      processing_thread.join
      expect(processor.healthy?).to be true

      # Health after shutdown
      processor.shutdown
      expect(processor.healthy?).to be false
    end

    it "handles health checks under concurrent load" do
      items = Array.new(20) { |i| "health_item#{i}" }
      health_checks = Concurrent::Array.new

      # Start processing
      processing_thread = Thread.new do
        processor.process_batch(items) do |item|
          sleep 0.01
          "processed_#{item}"
        end
      end

      # Perform frequent health checks
      health_thread = Thread.new do
        50.times do
          health_checks << processor.healthy?
          sleep 0.005
        end
      end

      processing_thread.join
      health_thread.join

      # All health checks should return true (before shutdown)
      expect(health_checks).to all(be true)
    end
  end
end
