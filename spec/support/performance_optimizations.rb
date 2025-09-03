# frozen_string_literal: true

# Performance optimizations for test suite
# Disables expensive operations that aren't needed for most tests

RSpec.configure do |config|
  # Global stubs for broadcasting operations
  config.before(:each) do |example|
    # Skip this setup for tests that explicitly need broadcasting or are testing broadcasting
    unless example.metadata[:needs_broadcasting] ||
           example.file_path.include?('sync_status_channel_spec') ||
           example.file_path.include?('broadcast_analytics_spec')
      # Stub SyncStatusChannel broadcasts
      allow(SyncStatusChannel).to receive(:broadcast_status).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_completion).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_failure).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_progress).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_account_progress).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_account_update).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_activity).and_return(nil)
      allow(SyncStatusChannel).to receive(:broadcast_with_reliability).and_return(nil)

      # Stub Turbo broadcasts on SyncSession
      allow_any_instance_of(SyncSession).to receive(:broadcast_replace_to).and_return(nil)
      allow_any_instance_of(SyncSession).to receive(:broadcast_update_to).and_return(nil)
      allow_any_instance_of(SyncSession).to receive(:broadcast_append_to).and_return(nil)
      allow_any_instance_of(SyncSession).to receive(:broadcast_prepend_to).and_return(nil)

      # Stub BroadcastReliabilityService
      if defined?(BroadcastReliabilityService)
        allow(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(nil)
      end

      # Stub Infrastructure::BroadcastService if it exists
      if defined?(Services::Infrastructure::BroadcastService)
        allow(Services::Infrastructure::BroadcastService).to receive(:broadcast).and_return(nil) if Services::Infrastructure::BroadcastService.respond_to?(:broadcast)
      end
    end

    # Skip cache clearing for most tests
    unless example.metadata[:needs_cache_clear]
      allow(Rails.cache).to receive(:clear).and_return(nil)
    end

    # Optimize ActiveRecord for tests
    unless example.metadata[:needs_callbacks]
      # This is safe because we're in a transaction that will be rolled back
      ActiveRecord::Base.logger = nil if example.metadata[:silent_ar]
    end
  end

  # Restore AR logger after silent tests
  config.after(:each) do |example|
    if example.metadata[:silent_ar]
      ActiveRecord::Base.logger = Logger.new(STDOUT) if Rails.env.development?
    end
  end

  # Use truncation strategy only for tests that explicitly need it
  # (tests that need to test after_commit hooks)
  config.before(:each, :needs_commit) do
    DatabaseCleaner.strategy = :truncation if defined?(DatabaseCleaner)
  end

  config.after(:each, :needs_commit) do
    DatabaseCleaner.clean if defined?(DatabaseCleaner)
    DatabaseCleaner.strategy = :transaction if defined?(DatabaseCleaner)
  end
end

# Monkey-patch FactoryBot to prefer build_stubbed for performance
module FactoryBotPerformance
  # Helper method to use in tests for better performance
  def build_stubbed_with_id(factory, traits = {})
    record = build_stubbed(factory, traits)
    # Simulate an ID without hitting the database
    record.id ||= rand(100000..999999)
    record
  end

  # Fast creation for when you need associations but not persistence
  def build_with_associations(factory, traits = {})
    # Build the main record without saving
    record = build(factory, traits)

    # Stub any associations that would normally be created
    record.association_names.each do |assoc|
      if record.send(assoc).nil?
        record.send("#{assoc}=", build_stubbed(assoc))
      end
    end

    record
  end
end

RSpec.configure do |config|
  config.include FactoryBotPerformance
end

# Performance monitoring for slow tests
if ENV['MONITOR_SLOW_TESTS']
  RSpec.configure do |config|
    config.around(:each) do |example|
      start_time = Time.current
      example.run
      duration = Time.current - start_time

      if duration > 0.5 # Flag tests taking more than 500ms
        puts "\n⚠️  Slow test detected (#{duration.round(2)}s): #{example.full_description}"
      end
    end
  end
end
