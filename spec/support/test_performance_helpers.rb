# frozen_string_literal: true

module TestPerformanceHelpers
  # Replace sleep with immediate execution for thread testing
  def wait_for_thread_start(&block)
    # Instead of sleeping, use a condition variable or just yield
    yield if block_given?
  end

  # Use test doubles for time-based operations
  def stub_timer_thread(collector)
    thread = instance_double(Thread, alive?: true, name: "test_thread", join: nil, terminate: nil)
    allow(collector).to receive(:start_timer_thread).and_return(thread)
    collector.instance_variable_set(:@timer_thread, thread)
    thread
  end

  # Factory optimization helpers
  def build_stubbed_with_id(factory, id: nil, **attrs)
    obj = build_stubbed(factory, **attrs)
    obj.define_singleton_method(:id) { id || rand(1000..9999) }
    obj.define_singleton_method(:persisted?) { true }
    obj
  end

  # Batch operations helper
  def create_list_in_batch(factory, count, **attrs)
    # Use insert_all for bulk inserts when possible
    model_class = factory.to_s.classify.constantize

    records = count.times.map do |i|
      attributes_for(factory, **attrs).merge(
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    model_class.insert_all(records)
    model_class.last(count)
  end
end

RSpec.configure do |config|
  config.include TestPerformanceHelpers
end
