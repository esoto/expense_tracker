# frozen_string_literal: true

# Performance budget configuration for test suites
# Automatically fails tests that exceed their time budget
module PerformanceBudget
  # Time budgets per test type (in seconds)
  BUDGETS = {
    unit: 0.02,        # Unit tests should be very fast
    contract: 0.05,    # Contract tests can be slightly slower
    integration: 2.0,  # Integration tests can take more time
    system: 5.0       # System tests are allowed the most time
  }.freeze

  # Override for specific slow tests that are known to take longer
  EXCEPTIONS = {
    # Example: 'SomeClass#some_slow_method' => 0.1
  }.freeze

  class << self
    def enforce!(example, type = :unit)
      return unless enforce_budgets?
      return unless example.execution_result

      execution_time = example.execution_result.run_time
      return unless execution_time

      budget = budget_for(example, type)

      if execution_time > budget
        warn_or_fail(example, execution_time, budget, type)
      end
    end

    def budget_for(example, type)
      # Check for specific exceptions first
      test_name = "#{example.metadata[:described_class]}##{example.metadata[:description]}"
      EXCEPTIONS[test_name] || BUDGETS[type] || BUDGETS[:unit]
    end

    private

    def enforce_budgets?
      # Only enforce in CI or when explicitly enabled
      ENV['ENFORCE_TEST_PERFORMANCE'] == 'true' || ENV['CI'] == 'true'
    end

    def warn_or_fail(example, execution_time, budget, type)
      message = format_violation_message(example, execution_time, budget, type)

      if strict_mode?
        example.pending(message)
        raise RSpec::Expectations::ExpectationNotMetError, message
      else
        warn "\n⚠️  PERFORMANCE WARNING: #{message}"
      end
    end

    def strict_mode?
      ENV['STRICT_PERFORMANCE'] == 'true'
    end

    def format_violation_message(example, execution_time, budget, type)
      test_name = example.full_description

      <<~MESSAGE
        Test exceeded performance budget!
        Test: #{test_name}
        Type: #{type}
        Budget: #{budget}s
        Actual: #{execution_time.round(3)}s
        Exceeded by: #{(execution_time - budget).round(3)}s (#{((execution_time / budget - 1) * 100).round(1)}% over)
      MESSAGE
    end
  end
end

# Hook into RSpec to automatically check performance budgets
RSpec.configure do |config|
  config.around(:each) do |example|
    # Determine test type from metadata
    type = if example.metadata[:type]
             example.metadata[:type]
    elsif example.metadata[:unit]
             :unit
    elsif example.metadata[:contract]
             :contract
    elsif example.metadata[:integration]
             :integration
    elsif example.metadata[:system]
             :system
    else
             :unit # Default to unit test budget
    end

    # Run the test
    example.run

    # Check performance budget
    PerformanceBudget.enforce!(example, type) if example.execution_result
  end

  # Add helpers for marking test types
  config.define_derived_metadata(file_path: /spec\/unit/) do |metadata|
    metadata[:unit] = true unless metadata[:type]
  end

  config.define_derived_metadata(file_path: /spec\/contract/) do |metadata|
    metadata[:contract] = true unless metadata[:type]
  end

  config.define_derived_metadata(file_path: /spec\/integration/) do |metadata|
    metadata[:integration] = true unless metadata[:type]
  end

  config.define_derived_metadata(file_path: /spec\/system/) do |metadata|
    metadata[:system] = true unless metadata[:type]
  end
end
