# frozen_string_literal: true

# Conservative performance optimizations for specs
# Focus on safe, reliable optimizations that don't break tests
module ConservativeJobOptimizations
  # Apply database optimizations
  def self.configure_database(config)
    # Already configured in rails_helper.rb - don't duplicate
  end

  # Optimize factory usage
  def self.configure_factories(config)
    # Already configured in rails_helper.rb - don't duplicate
  end

  # Optimize time-related operations - only when requested
  def self.configure_time_helpers(config)
    config.around(:each, :freeze_time) do |example|
      # Use travel_to for consistent time in tests
      travel_to(Time.zone.parse('2025-01-15 12:00:00')) do
        example.run
      end
    end
  end

  # Apply all optimizations
  def self.apply(config)
    configure_time_helpers(config)
    # Removed duplicate configurations that are in rails_helper
  end
end

# Apply optimizations to RSpec
RSpec.configure do |config|
  ConservativeJobOptimizations.apply(config) if Rails.env.test?
end