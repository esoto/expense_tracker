#!/usr/bin/env ruby

require_relative 'config/environment'

# Create minimal test data
sync_session = SyncSession.first || FactoryBot.create(:sync_session)
test_data = { status: 'processing', processed: 10, total: 100 }

# Mock the dependencies
class MockChannel
  def self.broadcast_to(target, data)
    puts "Broadcast called: #{target.inspect} with #{data.inspect}"
    true
  end
  
  def self.name
    'MockChannel'
  end
end

# Mock feature flags
allow_any_instance_of(Object).to receive(:BroadcastFeatureFlags) do
  double(enabled?: false)
end

begin
  puts "Testing broadcast_with_retry..."
  
  result = BroadcastReliabilityService.broadcast_with_retry(
    channel: MockChannel,
    target: sync_session,
    data: test_data,
    priority: :medium
  )
  
  puts "Result: #{result.inspect}"
  puts "Result class: #{result.class}"
  
rescue Exception => e
  puts "Exception caught: #{e.class}: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.join("\n")
end