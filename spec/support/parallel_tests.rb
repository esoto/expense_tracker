# frozen_string_literal: true

# Configuration for parallel test execution
# To use: bundle exec parallel_rspec spec/

if ENV['TEST_ENV_NUMBER']
  # Running in parallel

  # Configure database for parallel tests
  module ParallelTestsConfiguration
    def self.configure_database
      test_number = ENV['TEST_ENV_NUMBER']

      # Skip numeric database suffix for non-numeric test env numbers (e.g., "_worktree")
      # These use the base test database directly
      return unless test_number.match?(/\A\d+\z/)

      # Each parallel process gets its own database
      base_config = ActiveRecord::Base.configurations.configs_for(env_name: 'test').first.configuration_hash.dup
      base_config[:database] = "#{base_config[:database]}_#{test_number.to_i}"

      # Establish connection with the parallel database
      ActiveRecord::Base.establish_connection(
        base_config.merge(
          pool: 5,
          checkout_timeout: 1
        )
      )
    end

    def self.configure_redis
      # Each parallel process uses a different Redis database
      test_number = ENV['TEST_ENV_NUMBER']
      return unless test_number.match?(/\A\d+\z/)

      redis_db = test_number.to_i

      # Configure Redis to use different database numbers
      if defined?(Redis) && Redis.respond_to?(:current=)
        Redis.current = Redis.new(db: redis_db)
      end
    end

    def self.configure_cache
      # Each parallel process gets its own cache namespace
      test_number = ENV['TEST_ENV_NUMBER'].to_i

      Rails.cache = ActiveSupport::Cache::MemoryStore.new(
        namespace: "test_#{test_number}"
      )
    end

    def self.configure_solid_queue
      # Configure Solid Queue for parallel tests
      if defined?(SolidQueue)
        SolidQueue.logger.level = Logger::WARN
      end
    end
  end

  # Apply configurations
  RSpec.configure do |config|
    config.before(:suite) do
      ParallelTestsConfiguration.configure_database
      ParallelTestsConfiguration.configure_redis
      ParallelTestsConfiguration.configure_cache
      ParallelTestsConfiguration.configure_solid_queue
    end
  end
end

# Optimizations for both parallel and single-process testing
module TestPerformanceOptimizations
  # Group tests by type for better parallelization
  def self.group_specs_for_parallel_execution
    {
      models: Dir['spec/models/**/*_spec.rb'],
      controllers: Dir['spec/controllers/**/*_spec.rb'],
      services: Dir['spec/services/**/*_spec.rb'],
      jobs: Dir['spec/jobs/**/*_spec.rb'],
      requests: Dir['spec/requests/**/*_spec.rb'],
      others: Dir['spec/**/*_spec.rb'] -
              Dir['spec/{models,controllers,services,jobs,requests}/**/*_spec.rb']
    }
  end

  # Estimate test duration for load balancing
  def self.estimate_test_duration(file_path)
    case file_path
    when /sync_progress_updater_spec/
      3.0 # Known slow test
    when /progress_batch_collector_spec/
      2.0 # Thread-heavy test
    when /_service_spec/
      1.5 # Services tend to be slower
    when /_controller_spec/
      1.0 # Controllers are medium speed
    when /_model_spec/
      0.5 # Models are usually fast
    else
      0.8 # Default estimate
    end
  end

  # Balance test load across parallel processes
  def self.balance_test_load(test_files, num_processes)
    # Sort tests by estimated duration (longest first)
    sorted_tests = test_files.sort_by { |f| -estimate_test_duration(f) }

    # Distribute tests across processes using round-robin
    # with heaviest tests distributed first
    buckets = Array.new(num_processes) { [] }
    bucket_times = Array.new(num_processes, 0)

    sorted_tests.each do |test_file|
      # Find bucket with least total time
      min_bucket_index = bucket_times.index(bucket_times.min)

      # Add test to that bucket
      buckets[min_bucket_index] << test_file
      bucket_times[min_bucket_index] += estimate_test_duration(test_file)
    end

    buckets
  end
end

# Helper script for running parallel tests with optimal configuration
if __FILE__ == $0
  puts "Parallel Test Configuration:"
  puts "============================="
  puts "Detected #{Parallel.processor_count} processors"
  puts "Recommended: bundle exec parallel_rspec spec/ -n #{[ Parallel.processor_count - 1, 4 ].min}"
  puts ""
  puts "Test groups:"
  TestPerformanceOptimizations.group_specs_for_parallel_execution.each do |group, files|
    puts "  #{group}: #{files.count} files"
  end
end
