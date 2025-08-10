# frozen_string_literal: true

# Configure Redis for testing with fakeredis
require 'fakeredis' if Gem.loaded_specs.key?('fakeredis')
require 'fakeredis/rspec' if defined?(FakeRedis)

module RedisTestConfig
  def self.configure(config)
    config.before(:each) do
      # Clear Redis data between tests when using FakeRedis
      # Using Redis.new instead of deprecated Redis.current
      if defined?(Redis) && defined?(FakeRedis)
        Redis.new.flushdb rescue nil
      end
    end
  end
end

RSpec.configure do |config|
  RedisTestConfig.configure(config)
end