# Test Tier Configuration
# Defines the three-tier testing strategy with appropriate tags and settings

RSpec.configure do |config|
  # TAG DEFINITIONS
  # ===============

  # Test Speed Tags
  config.define_derived_metadata(file_path: %r{/spec/unit/}) do |metadata|
    metadata[:unit] = true
    metadata[:fast] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
    metadata[:medium] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/performance/}) do |metadata|
    metadata[:performance] = true
    metadata[:slow] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/system/}) do |metadata|
    metadata[:system] = true
    metadata[:slow] = true
  end

  # PERFORMANCE OPTIMIZATIONS
  # =========================

  # Unit Test Optimizations
  config.when_first_matching_example_defined(:unit) do
    # Use transactional fixtures for speed
    config.use_transactional_fixtures = true

    # Disable external service calls
    WebMock.disable_net_connect!(allow_localhost: false) if defined?(WebMock)

    # Use null cache store
    Rails.cache = ActiveSupport::Cache::NullStore.new if defined?(Rails)
  end

  # Integration Test Settings
  config.when_first_matching_example_defined(:integration) do
    # Use transactional fixtures with some exceptions
    config.use_transactional_fixtures = true

    # Allow localhost connections for integration tests
    WebMock.disable_net_connect!(allow_localhost: true) if defined?(WebMock)

    # Use memory cache store
    Rails.cache = ActiveSupport::Cache::MemoryStore.new if defined?(Rails)
  end

  # Performance Test Settings
  config.when_first_matching_example_defined(:performance) do
    # Disable transactional fixtures for accurate measurements
    config.use_transactional_fixtures = false

    # Use database cleaner
    config.before(:suite) do
      DatabaseCleaner.strategy = :truncation
    end

    config.around(:each) do |example|
      DatabaseCleaner.cleaning do
        example.run
      end
    end

    # Enable GC profiling
    GC::Profiler.enable

    # Set up performance helpers
    config.include PerformanceHelpers
  end

  # System Test Settings
  config.when_first_matching_example_defined(:system) do
    # Configure Capybara
    config.use_transactional_fixtures = false

    config.before(:suite) do
      DatabaseCleaner.strategy = :truncation
    end

    config.around(:each) do |example|
      DatabaseCleaner.cleaning do
        example.run
      end
    end
  end

  # FILTERING AND EXCLUSIONS
  # ========================

  # Exclude slow tests by default in development
  unless ENV['RUN_ALL_TESTS'] || ENV['CI']
    config.filter_run_excluding :slow
    config.filter_run_excluding :performance

    # Run only tagged tests if specified
    if ENV['TEST_TIER']
      config.filter_run ENV['TEST_TIER'].to_sym => true
    end
  end

  # Focus filtering
  config.filter_run_when_matching :focus

  # REPORTING
  # =========

  # Profile slowest tests only for non-unit tests
  config.profile_examples = 10 unless config.files_to_run.any? { |f| f.include?('/unit/') }

  # Use progress formatter for unit tests, documentation for others
  config.formatter = if config.files_to_run.any? { |f| f.include?('/unit/') }
                       'progress'
  else
                       'documentation'
  end

  # HOOKS
  # =====

  config.before(:suite) do
    # Print test tier information
    tier = ENV['TEST_TIER'] || 'all'
    puts "\n" + "="*60
    puts "Running #{tier.upcase} tests"
    puts "="*60 + "\n"
  end

  config.after(:suite) do
    # Print performance summary for performance tests
    if config.files_to_run.any? { |f| f.include?('/performance/') }
      PerformanceReporter.print_summary
    end
  end
end

# Performance Helpers Module
module PerformanceHelpers
  def measure_time(description = nil, &block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed = end_time - start_time

    if description
      puts "#{description}: #{(elapsed * 1000).round(2)}ms"
    end

    { result: result, time: elapsed }
  end

  def measure_memory(&block)
    GC.start
    before = ObjectSpace.memsize_of_all

    result = yield

    GC.start
    after = ObjectSpace.memsize_of_all

    { result: result, memory_delta: after - before }
  end

  def assert_performance(target_ms:, &block)
    measurement = measure_time(&block)

    expect(measurement[:time] * 1000).to be < target_ms

    measurement[:result]
  end
end

# Performance Reporter
class PerformanceReporter
  class << self
    def print_summary
      # This would aggregate and print performance metrics
      puts "\n" + "="*60
      puts "PERFORMANCE TEST SUMMARY"
      puts "="*60
      # Implementation would go here
    end
  end
end
