# frozen_string_literal: true

module TimeHelpers
  # Freezes time for the duration of the block
  def freeze_time(&block)
    if block_given?
      travel_to(Time.current, &block)
    else
      travel_to(Time.current)
    end
  end

  # Travel to a specific time
  def travel_to_time(time, &block)
    travel_to(time, &block)
  end

  # Travel back to the original time
  def travel_back_to_original_time
    travel_back
  end
end

# Include the helpers in RSpec
RSpec.configure do |config|
  config.include TimeHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  # Ensure time is reset after each test
  config.after(:each) do
    travel_back if respond_to?(:travel_back)
  end
end
