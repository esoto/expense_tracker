#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'
require 'benchmark'

# Disable logging for cleaner output
Rails.logger.level = Logger::ERROR
ActiveRecord::Base.logger.level = Logger::ERROR

puts "=" * 80
puts "FuzzyMatcher Performance Verification"
puts "=" * 80

# Initialize the matcher
matcher = Categorization::Matchers::FuzzyMatcher.instance

# Test data
test_cases = {
  "Basic Match" => {
    text: "starbucks coffee",
    candidates: [
      { id: 1, text: "Starbucks Coffee Company" },
      { id: 2, text: "Coffee Bean" },
      { id: 3, text: "Dunkin Donuts" }
    ]
  },
  "Spanish Text" => {
    text: "cafe maria",
    candidates: [
      { id: 1, text: "Café María" },
      { id: 2, text: "Panadería José" },
      { id: 3, text: "Restaurant El Niño" }
    ]
  },
  "Noisy Transaction" => {
    text: "PAYPAL *STARBUCKS 402935",
    candidates: [
      { id: 1, text: "Starbucks" },
      { id: 2, text: "PayPal" },
      { id: 3, text: "Amazon" }
    ]
  },
  "100 Candidates" => {
    text: "Merchant 50",
    candidates: (1..100).map { |i| { id: i, text: "Merchant #{i}" } }
  },
  "1000 Candidates" => {
    text: "Merchant 500",
    candidates: (1..1000).map { |i| { id: i, text: "Merchant #{i}" } }
  }
}

# Run benchmarks
results = {}

puts "\nRunning performance tests..."
puts "-" * 80

test_cases.each do |name, test|
  times = []
  # Warm up
  3.times { matcher.match(test[:text], test[:candidates]) }
  # Actual measurements
  10.times do
    time = Benchmark.realtime do
      matcher.match(test[:text], test[:candidates])
    end
    times << time * 1000 # Convert to ms
  end

  avg_time = times.sum / times.size
  max_time = times.max
  min_time = times.min

  results[name] = {
    avg: avg_time,
    max: max_time,
    min: min_time
  }

  status = avg_time < 10 ? "✓ PASS" : "✗ FAIL"
  puts "#{name.ljust(25)} | Avg: #{avg_time.round(2)}ms | Max: #{max_time.round(2)}ms | #{status}"
end

puts "-" * 80

# Check for database queries
puts "\nVerifying database query elimination..."
puts "-" * 80

# Monitor queries during normalization
query_count = 0
ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  unless event.payload[:name] == 'SCHEMA'
    query_count += 1
    puts "  DETECTED DB QUERY: #{event.payload[:sql][0..100]}..."
  end
end

# Test normalization hot path
test_text = "Café María España"
normalized = nil

5.times do
  query_count = 0
  normalized = matcher.instance_eval do
    @normalizer.normalize(test_text)
  end
end

if query_count == 0
  puts "✓ No database queries in normalization hot path"
else
  puts "✗ Found #{query_count} database queries in hot path!"
end

# Test similarity calculation
query_count = 0
5.times do
  matcher.calculate_similarity("starbucks", "starbucks coffee")
end

if query_count == 0
  puts "✓ No database queries in similarity calculation"
else
  puts "✗ Found #{query_count} database queries in similarity calculation!"
end

puts "-" * 80

# Summary
puts "\nPerformance Summary:"
puts "-" * 80
puts "Target: < 10ms per operation"
puts ""

all_pass = true
results.each do |name, times|
  pass = times[:avg] < 10
  all_pass = false unless pass

  status = pass ? "✓" : "✗"
  color = pass ? "\e[32m" : "\e[31m"
  reset = "\e[0m"

  puts "#{color}#{status} #{name.ljust(25)}#{reset} | Avg: #{times[:avg].round(2)}ms | Max: #{times[:max].round(2)}ms"
end

puts "-" * 80

if all_pass
  puts "\e[32m✓ ALL PERFORMANCE TESTS PASS\e[0m"
  puts "System meets < 10ms target requirement"
else
  puts "\e[31m✗ PERFORMANCE TESTS FAILED\e[0m"
  puts "System does not meet performance requirements"
end

puts "=" * 80