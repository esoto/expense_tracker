# frozen_string_literal: true

# Configure Redis for testing
module RedisTestConfig
  # Reuse a single Redis connection to avoid leaking connections
  # (Redis.new per test would exhaust max clients over large suites)
  def self.redis_connection
    @redis_connection ||= begin
      # Respect parallel test configuration: use the same DB as configured
      # in parallel_tests.rb to avoid cross-process interference
      db = if ENV["TEST_ENV_NUMBER"]&.match?(/\A\d+\z/)
        ENV["TEST_ENV_NUMBER"].to_i
      else
        0
      end
      Redis.new(db: db)
    end
  end

  def self.configure(config)
    config.before(:each) do
      # Clear Redis data between tests
      if defined?(Redis)
        begin
          RedisTestConfig.redis_connection.flushdb
        rescue Redis::CannotConnectError, Redis::CommandError
          # Skip Redis cleanup if Redis is not available in test environment
        rescue Redis::CommandError => e
          Rails.logger.debug { "[RedisTestConfig] Unexpected Redis error during flushdb: #{e.message}" }
        end
      end
    end

    config.after(:suite) do
      # Clean up the shared connection when tests finish
      if defined?(Redis) && RedisTestConfig.instance_variable_get(:@redis_connection)
        begin
          RedisTestConfig.redis_connection.close
        rescue StandardError => e
          Rails.logger.debug { "[RedisTestConfig] Error closing Redis connection: #{e.message}" }
        end
      end
    end

    config.after(:suite) do
      # Clean up the shared connection when tests finish
      if defined?(Redis) && RedisTestConfig.instance_variable_get(:@redis_connection)
        begin
          RedisTestConfig.redis_connection.close
        rescue StandardError
          # Ignore close errors
        end
      end
    end
  end
end

RSpec.configure do |config|
  RedisTestConfig.configure(config)
end
