#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'config/environment'
require 'benchmark'

# Create test data
email_account = EmailAccount.find_or_create_by!(
  email: "test@example.com"
) do |account|
  account.provider = "gmail"
  account.bank_name = "Test Bank"
end

expense = Expense.create!(
  email_account: email_account,
  merchant_name: "Amazon Store",
  amount: 100.0,
  description: "Online purchase",
  transaction_date: Time.current
)

category = Category.find_or_create_by!(name: "Shopping")

pattern = CategorizationPattern.create!(
  category: category,
  pattern_type: "merchant",
  pattern_value: "amazon_test_#{SecureRandom.hex(4)}",
  usage_count: 100,
  success_count: 90,
  success_rate: 0.9,
  metadata: {
    "amount_stats" => {
      "count" => 100,
      "mean" => 95.0,
      "std_dev" => 25.0
    }
  }
)

calculator = Categorization::ConfidenceCalculator.new

# Warm up
puts "Warming up..."
5.times { calculator.calculate(expense, pattern, 0.85) }

# Benchmark
puts "Running benchmark (100 iterations)..."
times = []
100.times do
  time = Benchmark.realtime { calculator.calculate(expense, pattern, 0.85) }
  times << time * 1000 # Convert to ms
end

puts "\nPerformance Results:"
puts "  Average: #{(times.sum / times.size).round(3)} ms"
puts "  Min: #{times.min.round(3)} ms"
puts "  Max: #{times.max.round(3)} ms"
puts "  P95: #{times.sort[(times.size * 0.95).to_i].round(3)} ms"
puts "  P99: #{times.sort[(times.size * 0.99).to_i].round(3)} ms"

# Check if under 1ms target
under_1ms = times.select { |t| t < 1.0 }.size
puts "  Under 1ms: #{under_1ms}/#{times.size} (#{(under_1ms.to_f / times.size * 100).round(2)}%)"

# Get detailed metrics
puts "\nDetailed Metrics:"
pp calculator.detailed_metrics

# Cleanup
expense.destroy!
pattern.destroy!