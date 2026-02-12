# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Services::Categorization::Orchestrator Debug", type: :service, integration: true do
  describe "Debug orchestrator creation", integration: true do
    it "creates test orchestrator successfully" do
      begin
        orchestrator = Services::Categorization::OrchestratorFactory.create_test

        puts "\n=== Orchestrator Debug Info ==="
        puts "Orchestrator class: #{orchestrator.class}"
        puts "Pattern cache: #{orchestrator.pattern_cache.class}"
        puts "Matcher: #{orchestrator.matcher.class}"
        puts "Confidence calculator: #{orchestrator.confidence_calculator.class}"
        puts "Pattern learner: #{orchestrator.pattern_learner.class}"
        puts "Performance tracker: #{orchestrator.performance_tracker.class}"

        # Create test data
        category = create(:category, name: "Test Category")
        pattern = create(:categorization_pattern,
                        pattern_type: "merchant",
                        pattern_value: "test merchant",
                        category: category,
                        confidence_weight: 2.0)

        expense = create(:expense,
                        merchant_name: "Test Merchant",
                        description: "Test purchase",
                        amount: 100.00)

        puts "\n=== Test Data ==="
        puts "Category: #{category.inspect}"
        puts "Pattern: #{pattern.inspect}"
        puts "Expense: #{expense.inspect}"

        # Try to categorize
        puts "\n=== Starting Categorization ==="
        result = orchestrator.categorize(expense)

        puts "\n=== Result ==="
        puts "Result class: #{result.class}"
        puts "Successful?: #{result.successful?}"
        puts "Category: #{result.category&.name}"
        puts "Confidence: #{result.confidence}"
        puts "Error: #{result.error}" if result.error
        puts "Method: #{result.method}"
        puts "Processing time: #{result.processing_time_ms}ms"

        # If there's an error, try to get more details
        if result.error
          puts "\n=== Error Details ==="

          # Try direct pattern cache query
          puts "Direct pattern query:"
          patterns = orchestrator.pattern_cache.get_patterns_for_expense(expense)
          puts "  Found #{patterns.size} patterns"
          patterns.each { |p| puts "  - #{p.inspect}" }
        end

      rescue => e
        puts "\n=== Exception Caught ==="
        puts "Error: #{e.class} - #{e.message}"
        puts "Backtrace:"
        puts e.backtrace.first(10).join("\n")
        raise e
      end
    end
  end
end
