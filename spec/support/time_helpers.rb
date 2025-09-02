# frozen_string_literal: true

# Time helpers for fast test execution
# These helpers replace actual sleep calls with time mocking
module TimeHelpers
  # Simulates time passing without actual sleep
  # @param duration [Numeric, ActiveSupport::Duration] Amount of time to advance
  def travel(duration)
    new_time = Time.current + duration
    allow(Time).to receive(:current).and_return(new_time)
    allow(Time).to receive(:now).and_return(new_time)
  end

  # Simulates time passing in a block context
  # @param duration [Numeric, ActiveSupport::Duration] Amount of time to advance
  def travel_for(duration)
    original_time = Time.current
    new_time = original_time + duration

    allow(Time).to receive(:current).and_return(new_time)
    allow(Time).to receive(:now).and_return(new_time)

    yield if block_given?

    # Reset time
    allow(Time).to receive(:current).and_call_original
    allow(Time).to receive(:now).and_call_original
  end

  # Freezes time at a specific point
  # @param time [Time] The time to freeze at (default: current time)
  def freeze_time(time = Time.current)
    allow(Time).to receive(:current).and_return(time)
    allow(Time).to receive(:now).and_return(time)
  end

  # Resets all time mocking
  def unfreeze_time
    allow(Time).to receive(:current).and_call_original
    allow(Time).to receive(:now).and_call_original
  end

  # Simulates concurrent time passage for thread tests
  # Each thread gets its own simulated time progression
  def simulate_concurrent_time(base_time = Time.current, &block)
    thread_times = {}

    allow(Time).to receive(:current) do
      thread_id = Thread.current.object_id
      thread_times[thread_id] ||= base_time
      thread_times[thread_id]
    end

    allow(Time).to receive(:now) do
      thread_id = Thread.current.object_id
      thread_times[thread_id] ||= base_time
      thread_times[thread_id]
    end

    # Helper to advance time for current thread
    define_singleton_method :advance_thread_time do |duration|
      thread_id = Thread.current.object_id
      thread_times[thread_id] = (thread_times[thread_id] || base_time) + duration
    end

    yield if block_given?
  ensure
    unfreeze_time
  end
end

# Configure RSpec to include TimeHelpers
RSpec.configure do |config|
  config.include TimeHelpers

  # Auto-reset time mocking after each test
  config.after(:each) do
    unfreeze_time if defined?(unfreeze_time)
  end
end
