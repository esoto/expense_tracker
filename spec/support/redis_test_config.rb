# frozen_string_literal: true

# Configure Redis for testing
module RedisTestConfig
  # Reuse a single Redis connection to avoid leaking connections
  # (Redis.new per test would exhaust max clients over large suites)
  def self.redis_connection
    @redis_connection ||= Redis.new
  end

  def self.configure(config)
    config.before(:each) do
      # Clear Redis data between tests
      if defined?(Redis)
        begin
          RedisTestConfig.redis_connection.flushdb
        rescue Redis::CannotConnectError, Redis::CommandError
          # Skip Redis cleanup if Redis is not available in test environment
        end
      end
    end

    config.after(:suite) do
      # Clean up the shared connection when tests finish
      if defined?(Redis) && RedisTestConfig.instance_variable_defined?(:@redis_connection)
        begin
          RedisTestConfig.redis_connection.close
        rescue StandardError => e
          Rails.logger.debug { "[RedisTestConfig] Error closing Redis connection: #{e.message}" }
        ensure
          RedisTestConfig.instance_variable_set(:@redis_connection, nil)
        end
      end
    end
  end
end

RSpec.configure do |config|
  RedisTestConfig.configure(config)
end
