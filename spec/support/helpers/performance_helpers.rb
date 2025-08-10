# Performance Testing Helpers
# Provides utilities for benchmarking and performance testing

module PerformanceHelpers
  extend ActiveSupport::Concern

  # Memory measurement utilities
  def measure_memory_usage(&block)
    GC.start # Start with clean slate
    GC.disable # Prevent GC during measurement

    before_memory = memory_usage_mb
    result = block.call
    after_memory = memory_usage_mb

    GC.enable

    {
      result: result,
      memory_used: after_memory - before_memory,
      before: before_memory,
      after: after_memory
    }
  end

  def memory_usage_mb
    gc_stat = GC.stat
    pages = gc_stat[:heap_allocated_pages] || 0
    slots = gc_stat[:heap_allocated_slots] || gc_stat[:heap_live_slots] || 0
    (pages * slots * 40.0) / (1024 * 1024)
  end

  # Time measurement utilities
  def measure_execution_time(&block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = block.call
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    {
      result: result,
      execution_time: end_time - start_time
    }
  end

  # Database query counting
  def count_database_queries(&block)
    query_count = 0
    query_time = 0

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, start, finish, _, _|
      query_count += 1
      query_time += finish - start
    end

    result = block.call

    ActiveSupport::Notifications.unsubscribe(subscriber)

    {
      result: result,
      query_count: query_count,
      query_time: query_time
    }
  end

  # Combined performance measurement
  def measure_performance(&block)
    memory_stats = measure_memory_usage do
      time_stats = measure_execution_time do
        count_database_queries(&block)
      end
      time_stats
    end

    {
      result: memory_stats[:result][:result][:result],
      execution_time: memory_stats[:result][:execution_time],
      memory_used: memory_stats[:memory_used],
      query_count: memory_stats[:result][:result][:query_count],
      query_time: memory_stats[:result][:result][:query_time]
    }
  end

  # Performance threshold validation
  def assert_performance_within(expected_time: nil, expected_memory: nil, expected_queries: nil, &block)
    stats = measure_performance(&block)

    if expected_time
      expect(stats[:execution_time]).to be < expected_time,
        "Expected execution time to be under #{expected_time}s, but was #{stats[:execution_time]}s"
    end

    if expected_memory
      expect(stats[:memory_used]).to be < expected_memory,
        "Expected memory usage to be under #{expected_memory}MB, but was #{stats[:memory_used]}MB"
    end

    if expected_queries
      expect(stats[:query_count]).to be <= expected_queries,
        "Expected query count to be under #{expected_queries}, but was #{stats[:query_count]}"
    end

    stats[:result]
  end

  # Stress testing utilities
  def stress_test(iterations: 100, concurrency: 1, &block)
    results = []
    errors = []

    if concurrency > 1
      # Concurrent stress test
      threads = concurrency.times.map do |thread_id|
        Thread.new do
          thread_results = []
          thread_errors = []

          iterations.times do |i|
            begin
              stats = measure_performance(&block)
              thread_results << stats.merge(iteration: i, thread: thread_id)
            rescue StandardError => e
              thread_errors << { error: e, iteration: i, thread: thread_id }
            end
          end

          { results: thread_results, errors: thread_errors }
        end
      end

      thread_data = threads.map(&:value)
      results = thread_data.flat_map { |data| data[:results] }
      errors = thread_data.flat_map { |data| data[:errors] }
    else
      # Sequential stress test
      iterations.times do |i|
        begin
          stats = measure_performance(&block)
          results << stats.merge(iteration: i)
        rescue StandardError => e
          errors << { error: e, iteration: i }
        end
      end
    end

    {
      results: results,
      errors: errors,
      summary: analyze_stress_results(results),
      error_rate: errors.length.to_f / (iterations * concurrency)
    }
  end

  def analyze_stress_results(results)
    return {} if results.empty?

    execution_times = results.map { |r| r[:execution_time] }
    memory_usage = results.map { |r| r[:memory_used] }
    query_counts = results.map { |r| r[:query_count] }

    {
      execution_time: {
        min: execution_times.min,
        max: execution_times.max,
        avg: execution_times.sum / execution_times.length,
        median: execution_times.sort[execution_times.length / 2]
      },
      memory_usage: {
        min: memory_usage.min,
        max: memory_usage.max,
        avg: memory_usage.sum / memory_usage.length
      },
      query_count: {
        min: query_counts.min,
        max: query_counts.max,
        avg: query_counts.sum / query_counts.length
      },
      total_iterations: results.length
    }
  end

  # Performance regression detection
  def benchmark_against_baseline(baseline_key, &block)
    current_stats = measure_performance(&block)
    baseline = load_baseline(baseline_key)

    if baseline
      regression_analysis = {
        execution_time_change: percentage_change(baseline[:execution_time], current_stats[:execution_time]),
        memory_usage_change: percentage_change(baseline[:memory_used], current_stats[:memory_used]),
        query_count_change: percentage_change(baseline[:query_count], current_stats[:query_count])
      }

      # Store current as new baseline if significantly better
      if regression_analysis.values.all? { |change| change < 10 } # Less than 10% regression
        store_baseline(baseline_key, current_stats)
      end

      current_stats.merge(regression_analysis: regression_analysis)
    else
      # First run, establish baseline
      store_baseline(baseline_key, current_stats)
      current_stats
    end
  end

  private

  def percentage_change(baseline, current)
    return 0 if baseline.zero?
    ((current - baseline) / baseline) * 100
  end

  def baseline_file_path(key)
    Rails.root.join("tmp", "performance_baselines", "#{key}.json")
  end

  def load_baseline(key)
    file_path = baseline_file_path(key)
    return nil unless File.exist?(file_path)

    JSON.parse(File.read(file_path), symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  def store_baseline(key, stats)
    file_path = baseline_file_path(key)
    FileUtils.mkdir_p(File.dirname(file_path))

    File.write(file_path, JSON.pretty_generate(stats))
  end
end

# Performance matchers for RSpec
RSpec::Matchers.define :perform_under do |expected_time|
  supports_block_expectations

  match do |block|
    @actual_time = Benchmark.realtime(&block)
    @actual_time <= expected_time
  end

  failure_message do
    "Expected block to execute in under #{expected_time} seconds, but took #{@actual_time} seconds"
  end

  chain :seconds do
    # No-op for readability
  end
end

RSpec::Matchers.define :perform_allocation do |expected_memory|
  supports_block_expectations

  match do |block|
    memory_before = GC.stat[:heap_allocated_pages]
    block.call
    memory_after = GC.stat[:heap_allocated_pages]

    @actual_allocation = (memory_after - memory_before) * 4096 # Convert pages to bytes
    @actual_allocation <= expected_memory
  end

  failure_message do
    "Expected block to allocate under #{expected_memory} bytes, but allocated #{@actual_allocation} bytes"
  end

  chain :bytes do
    # No-op for readability
  end

  chain :kilobytes do
    @expected_memory = expected_memory * 1024
  end

  chain :megabytes do
    @expected_memory = expected_memory * 1024 * 1024
  end

  def or_less
    self
  end
end

RSpec::Matchers.define :execute_queries do |expected_count|
  supports_block_expectations

  match do |block|
    query_count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do
      query_count += 1
    end

    block.call

    ActiveSupport::Notifications.unsubscribe(subscriber)
    @actual_count = query_count

    case @comparison
    when :less_than, :under
      @actual_count < expected_count
    when :less_than_or_equal, :at_most
      @actual_count <= expected_count
    when :exactly
      @actual_count == expected_count
    else
      @actual_count <= expected_count
    end
  end

  failure_message do
    case @comparison
    when :less_than, :under
      "Expected fewer than #{expected_count} queries, but executed #{@actual_count}"
    when :exactly
      "Expected exactly #{expected_count} queries, but executed #{@actual_count}"
    else
      "Expected at most #{expected_count} queries, but executed #{@actual_count}"
    end
  end

  chain :or_fewer do
    @comparison = :less_than_or_equal
  end

  chain :or_less do
    @comparison = :less_than_or_equal
  end

  chain :exactly do
    @comparison = :exactly
  end
end

# Include performance helpers in relevant test types
RSpec.configure do |config|
  config.include PerformanceHelpers, type: :performance
  config.include PerformanceHelpers, type: :service

  # Set up performance test environment
  config.before(:suite) do
    # Ensure consistent performance testing environment
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end

  config.around(:each, type: :performance) do |example|
    # Isolate performance tests
    GC.start
    example.run
    GC.start
  end
end
