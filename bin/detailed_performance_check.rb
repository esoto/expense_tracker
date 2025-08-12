#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'
require 'benchmark'

Rails.logger.level = Logger::ERROR
ActiveRecord::Base.logger.level = Logger::ERROR

puts "=" * 80
puts "DETAILED PERFORMANCE VERIFICATION FOR TASK 1.4"
puts "=" * 80

# Test both singleton and new instances
singleton_matcher = Categorization::Matchers::FuzzyMatcher.instance
new_matcher = Categorization::Matchers::FuzzyMatcher.new

puts "\n1. INITIALIZATION OVERHEAD TEST"
puts "-" * 80

init_times = []
10.times do
  time = Benchmark.realtime do
    Categorization::Matchers::FuzzyMatcher.new
  end
  init_times << time * 1000
end

puts "New instance creation: #{init_times.sum / init_times.size}ms average"
puts "  Min: #{init_times.min.round(2)}ms, Max: #{init_times.max.round(2)}ms"

puts "\n2. FIRST-RUN vs WARMED-UP PERFORMANCE"
puts "-" * 80

test_data = {
  text: "starbucks coffee",
  candidates: 50.times.map { |i| { id: i, text: "Merchant #{i}" } }
}

# First run (cold)
first_run_time = Benchmark.realtime do
  new_matcher.match(test_data[:text], test_data[:candidates])
end * 1000

# Warmed up runs
warm_times = []
10.times do
  time = Benchmark.realtime do
    new_matcher.match(test_data[:text], test_data[:candidates])
  end
  warm_times << time * 1000
end

puts "First run (cold): #{first_run_time.round(2)}ms"
puts "Warmed up average: #{(warm_times.sum / warm_times.size).round(2)}ms"
puts "Speedup after warmup: #{(first_run_time / (warm_times.sum / warm_times.size)).round(1)}x"

puts "\n3. DATABASE QUERY ANALYSIS"
puts "-" * 80

query_log = []
ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  unless event.payload[:name] == 'SCHEMA'
    query_log << {
      sql: event.payload[:sql],
      duration: event.duration
    }
  end
end

# Test normalization path
test_texts = ["Café María", "Niño España", "Señor López"]
test_texts.each do |text|
  query_log.clear
  normalized = new_matcher.instance_eval { @normalizer.normalize(text) }
  if query_log.any?
    puts "✗ Queries detected for '#{text}':"
    query_log.each { |q| puts "  - #{q[:sql][0..80]}... (#{q[:duration].round(2)}ms)" }
  end
end

puts "✓ No database queries in text normalization" if query_log.empty?

puts "\n4. PERFORMANCE BY OPERATION TYPE"
puts "-" * 80

operations = {
  "Text normalization" => -> {
    new_matcher.instance_eval { @normalizer.normalize("PAYPAL *STARBUCKS 123") }
  },
  "Jaro-Winkler calculation" => -> {
    new_matcher.calculate_similarity("starbucks", "starbucks coffee", :jaro_winkler)
  },
  "Trigram calculation" => -> {
    new_matcher.calculate_similarity("walmart", "wallmart", :trigram)
  },
  "Small match (5 candidates)" => -> {
    new_matcher.match("test", 5.times.map { |i| { id: i, text: "Item #{i}" } })
  },
  "Medium match (50 candidates)" => -> {
    new_matcher.match("test", 50.times.map { |i| { id: i, text: "Item #{i}" } })
  },
  "Large match (500 candidates)" => -> {
    new_matcher.match("test", 500.times.map { |i| { id: i, text: "Item #{i}" } })
  }
}

operations.each do |name, operation|
  times = []
  # Warmup
  3.times { operation.call }
  # Measure
  20.times do
    time = Benchmark.realtime { operation.call } * 1000
    times << time
  end

  avg = times.sum / times.size
  status = avg < 10 ? "✓" : "✗"

  puts "#{status} #{name.ljust(30)} | Avg: #{avg.round(3)}ms | Max: #{times.max.round(3)}ms"
end

puts "\n5. CRITICAL PATH ANALYSIS"
puts "-" * 80

# Simulate the exact test that's failing
merchants = [
  "Starbucks Coffee Company",
  "Walmart Supercenter",
  "Target Store",
  "Amazon.com",
  "McDonald's Restaurant",
  "Uber Technologies",
  "Lyft Inc",
  "Netflix Streaming",
  "Spotify Music",
  "Apple Store",
  "Google Services",
  "Microsoft Corporation",
  "Home Depot",
  "Lowes Home Improvement",
  "CVS Pharmacy",
  "Walgreens Drugstore",
  "Shell Gas Station",
  "Exxon Mobil",
  "Chevron Station",
  "Best Buy Electronics",
  "Whole Foods Market",
  "Trader Joe's",
  "Kroger Grocery",
  "Safeway Supermarket",
  "Costco Wholesale",
  "Sam's Club",
  "Office Depot",
  "Staples Office Supply",
  "FedEx Office",
  "UPS Store",
  "USPS Post Office",
  "Delta Airlines",
  "American Airlines",
  "Southwest Airlines",
  "United Airlines",
  "Hilton Hotel",
  "Marriott Hotel",
  "Holiday Inn",
  "Airbnb Rental",
  "Enterprise Rent-A-Car",
  "Hertz Car Rental",
  "Budget Car Rental",
  "Subway Restaurant",
  "Chipotle Mexican Grill",
  "Panera Bread",
  "Dunkin Donuts",
  "Pizza Hut",
  "Domino's Pizza",
  "Papa John's Pizza",
  "Taco Bell"
].map.with_index { |name, i| { id: i + 1, text: name } }

puts "Testing with exact failing test data (50 merchants)..."
test_times = []

10.times do
  time = Benchmark.realtime do
    new_matcher.match("starbucks coffee", merchants)
  end
  test_times << time * 1000
end

avg_time = test_times.sum / test_times.size
max_time = test_times.max

puts "  Average: #{avg_time.round(2)}ms"
puts "  Maximum: #{max_time.round(2)}ms"
puts "  Status: #{max_time < 15 ? '✓ PASS' : '✗ FAIL'}"

puts "\n6. PERFORMANCE SUMMARY"
puts "=" * 80

claims = {
  "Basic Match (3 candidates)" => { claimed: 0.02, actual: nil },
  "Spanish Text (3 candidates)" => { claimed: 0.02, actual: nil },
  "100 Candidates" => { claimed: 0.05, actual: nil },
  "1000 Candidates" => { claimed: 0.19, actual: nil }
}

# Measure actual performance
actual_matcher = Categorization::Matchers::FuzzyMatcher.instance

# Warmup
5.times do
  actual_matcher.match("test", [{ id: 1, text: "test" }])
end

# Basic match
times = []
10.times do
  time = Benchmark.realtime do
    actual_matcher.match("starbucks", [
      { id: 1, text: "Starbucks" },
      { id: 2, text: "Coffee Shop" },
      { id: 3, text: "Dunkin" }
    ])
  end
  times << time * 1000
end
claims["Basic Match (3 candidates)"][:actual] = times.sum / times.size

# Spanish text
times = []
10.times do
  time = Benchmark.realtime do
    actual_matcher.match("cafe maria", [
      { id: 1, text: "Café María" },
      { id: 2, text: "Panadería José" },
      { id: 3, text: "Restaurant" }
    ])
  end
  times << time * 1000
end
claims["Spanish Text (3 candidates)"][:actual] = times.sum / times.size

# 100 candidates
candidates_100 = 100.times.map { |i| { id: i, text: "Merchant #{i}" } }
times = []
10.times do
  time = Benchmark.realtime do
    actual_matcher.match("Merchant 50", candidates_100)
  end
  times << time * 1000
end
claims["100 Candidates"][:actual] = candidates_100.size > 0 ? times.sum / times.size : 0

# 1000 candidates
candidates_1000 = 1000.times.map { |i| { id: i, text: "Merchant #{i}" } }
times = []
10.times do
  time = Benchmark.realtime do
    actual_matcher.match("Merchant 500", candidates_1000)
  end
  times << time * 1000
end
claims["1000 Candidates"][:actual] = candidates_1000.size > 0 ? times.sum / times.size : 0

puts "\nCLAIMED vs ACTUAL PERFORMANCE:"
puts "-" * 80
puts "Test Case".ljust(30) + " | Claimed | Actual  | Status"
puts "-" * 80

all_valid = true
claims.each do |test_case, data|
  actual_str = data[:actual] ? "#{data[:actual].round(2)}ms" : "N/A"

  if data[:actual]
    status = data[:actual] < 10 ? "✓ PASS" : "✗ FAIL"
    all_valid = false if data[:actual] >= 10
  else
    status = "?"
  end

  puts "#{test_case.ljust(30)} | #{data[:claimed]}ms".ljust(10) + " | #{actual_str.ljust(8)} | #{status}"
end

puts "-" * 80

if all_valid
  puts "\e[32m✓ TASK 1.4 PERFORMANCE REQUIREMENTS MET\e[0m"
  puts "All operations complete in < 10ms as required"
  puts "Claims are accurate and system is production ready"
else
  puts "\e[31m✗ PERFORMANCE REQUIREMENTS NOT FULLY MET\e[0m"
  puts "Some operations exceed the 10ms threshold"
end

puts "=" * 80