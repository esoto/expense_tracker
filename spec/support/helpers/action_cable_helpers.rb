# ActionCable Testing Helpers
# These helpers provide utilities for testing WebSocket connections and real-time features

module ActionCableHelpers
  # Subscribe to a channel for testing
  def subscribe_to_channel(channel_class, params = {})
    @subscription = subscribe(channel_class, params)
  end

  # Unsubscribe from all test channels
  def unsubscribe_from_all
    unsubscribe_from_all_channels if respond_to?(:unsubscribe_from_all_channels)
  end

  # Wait for a broadcast to occur
  def wait_for_broadcast(channel_class, data = {}, timeout: 5.seconds)
    start_time = Time.current

    loop do
      break if broadcasts(channel_class).any? { |broadcast| broadcast_matches?(broadcast, data) }

      if Time.current - start_time > timeout
        raise "Expected broadcast not received within #{timeout} seconds"
      end

      sleep 0.1
    end
  end

  # Check if broadcast data matches expected data
  def broadcast_matches?(broadcast, expected_data)
    return true if expected_data.empty?

    expected_data.all? do |key, value|
      broadcast[key] == value
    end
  end

  # Clear all broadcasts for testing
  def clear_broadcasts
    ActionCable.server.pubsub.clear if ActionCable.server.pubsub.respond_to?(:clear)
  end

  # Get the last broadcast for a channel
  def last_broadcast(channel_class)
    broadcasts(channel_class).last
  end

  # Count broadcasts for a channel
  def broadcast_count(channel_class)
    broadcasts(channel_class).count
  end

  # Custom matchers for ActionCable testing
  RSpec::Matchers.define :have_broadcasted_to_channel do |channel_class|
    chain :with_data do |expected_data|
      @expected_data = expected_data
    end

    match do |actual|
      @actual_broadcasts = broadcasts(channel_class)

      if @expected_data
        @actual_broadcasts.any? { |broadcast| broadcast_matches?(broadcast, @expected_data) }
      else
        @actual_broadcasts.any?
      end
    end

    failure_message do
      if @expected_data
        "Expected broadcast to #{channel_class} with data #{@expected_data}, but got: #{@actual_broadcasts}"
      else
        "Expected broadcast to #{channel_class}, but no broadcasts found"
      end
    end

    failure_message_when_negated do
      "Expected no broadcast to #{channel_class}, but got: #{@actual_broadcasts}"
    end
  end

  # Matcher for specific sync session broadcasts
  RSpec::Matchers.define :have_broadcasted_progress_update do |sync_session|
    chain :with_progress do |expected_progress|
      @expected_progress = expected_progress
    end

    chain :with_type do |expected_type|
      @expected_type = expected_type
    end

    match do |actual|
      broadcasts = broadcasts_for(sync_session)

      broadcasts.any? do |broadcast|
        type_matches = @expected_type ? broadcast[:type] == @expected_type : true
        progress_matches = @expected_progress ? broadcast[:progress_percentage] == @expected_progress : true

        type_matches && progress_matches
      end
    end

    failure_message do
      broadcasts = broadcasts_for(sync_session)
      "Expected progress broadcast for session #{sync_session.id} with type: #{@expected_type}, progress: #{@expected_progress}, but got: #{broadcasts}"
    end

    private

    def broadcasts_for(sync_session)
      ActionCable.server.pubsub.broadcasts_for(sync_session) || []
    end
  end
end

# Include in channel specs
RSpec.configure do |config|
  config.include ActionCableHelpers, type: :channel
  config.include ActionCableHelpers, type: :system

  # Clean up ActionCable connections after each test
  config.after(:each, type: :channel) do
    unsubscribe_from_all
    clear_broadcasts
  end
end
