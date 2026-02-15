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
        rescue Redis::CannotConnectError,
               Redis::ConnectionError,
               Redis::TimeoutError
          # Reset connection so a fresh one is created next time
          RedisTestConfig.instance_variable_set(:@redis_connection, nil)
        rescue Redis::CommandError => e
          Rails.logger.debug { "[RedisTestConfig] Unexpected Redis error during flushdb: #{e.message}" }
        end
      end
    end

    config.after(:suite) do
      if defined?(Redis) && RedisTestConfig.instance_variable_defined?(:@redis_connection)
        begin
          connection = RedisTestConfig.redis_connection
          if connection.respond_to?(:disconnect!)
            connection.disconnect!
          elsif connection.respond_to?(:close)
            connection.close
          end
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
