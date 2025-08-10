# frozen_string_literal: true

# Performance optimizations for FactoryBot
module FactoryOptimizations
  # Use build_stubbed for objects that don't need database persistence
  def build_stubbed_with_associations(factory_name, **attributes)
    obj = build_stubbed(factory_name, **attributes)

    # Add ID if not present
    obj.define_singleton_method(:id) { @id ||= rand(1000..9999) } unless obj.respond_to?(:id)
    obj.define_singleton_method(:persisted?) { true }
    obj.define_singleton_method(:new_record?) { false }

    obj
  end

  # Batch create records for better performance
  def create_list_optimized(factory_name, count, **attributes)
    return [] if count <= 0

    # For small counts, use regular create_list
    return create_list(factory_name, count, **attributes) if count <= 5

    # For larger counts, use insert_all for performance
    model_class = factory_name.to_s.classify.constantize

    # Generate attributes for all records
    records_attrs = count.times.map do
      attrs = attributes_for(factory_name, **attributes)
      attrs[:created_at] = Time.current
      attrs[:updated_at] = Time.current
      attrs
    end

    # Bulk insert
    result = model_class.insert_all(records_attrs, returning: %w[id])

    # Return AR objects
    model_class.where(id: result.rows.flatten)
  end

  # Cache expensive factory builds
  def cached_factory(factory_name, cache_key = nil)
    cache_key ||= "factory_#{factory_name}"

    Thread.current[cache_key] ||= create(factory_name)
  end

  # Clear factory cache between tests
  def clear_factory_cache!
    Thread.current.keys.grep(/^factory_/).each do |key|
      Thread.current[key] = nil
    end
  end
end

RSpec.configure do |config|
  config.include FactoryOptimizations

  config.before(:each) do
    clear_factory_cache!
  end

  # Only stub saves when explicitly marked as safe to do so
  config.before(:each, type: :model) do |example|
    if example.metadata[:stub_safe]
      # Only stub for tests that explicitly opt-in
      allow_any_instance_of(ActiveRecord::Base).to receive(:save).and_return(true)
      allow_any_instance_of(ActiveRecord::Base).to receive(:save!).and_return(true)
    end
  end
end

# Optimize specific factories
FactoryBot.define do
  # Add sequence caching for frequently used sequences
  sequence :cached_email do |n|
    Thread.current[:email_counter] ||= 0
    Thread.current[:email_counter] += 1
    "user#{Thread.current[:email_counter]}@example.com"
  end
end if defined?(FactoryBot)
