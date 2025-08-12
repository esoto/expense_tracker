# frozen_string_literal: true

# Configure Redis for testing
module RedisTestConfig
  def self.configure(config)
    config.before(:each) do
      # Clear Redis data between tests
      if defined?(Redis)
        begin
          Redis.new.flushdb
        rescue Redis::CannotConnectError
          # Skip Redis cleanup if Redis is not available in test environment
        end
      end
    end
  end
end

RSpec.configure do |config|
  RedisTestConfig.configure(config)
end
