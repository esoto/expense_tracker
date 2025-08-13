#!/usr/bin/env ruby
# frozen_string_literal: true

# This script verifies that the categorization engine tests pass both
# individually and when run together, confirming proper test isolation

require "open3"
require "json"

def run_test(test_file, test_line = nil)
  cmd = if test_line
    "bundle exec rspec #{test_file}:#{test_line} --format json"
  else
    "bundle exec rspec #{test_file} --format json"
  end

  stdout, stderr, status = Open3.capture3(cmd)

  begin
    result = JSON.parse(stdout)
    {
      success: status.success?,
      examples: result["summary"]["example_count"],
      failures: result["summary"]["failure_count"],
      pending: result["summary"]["pending_count"],
      cmd: cmd
    }
  rescue JSON::ParserError
    {
      success: false,
      error: "Failed to parse JSON output",
      cmd: cmd,
      stderr: stderr
    }
  end
end

puts "=" * 80
puts "Verifying Test Isolation for Categorization::Engine"
puts "=" * 80
puts

test_file = "spec/services/categorization/engine_spec.rb"

# Key tests that were previously failing due to singleton issues
critical_tests = [
  { line: 56, description: "prioritizes user preferences" },
  { line: 97, description: "finds and uses matching patterns" },
  { line: 145, description: "returns no_match result" },
  { line: 198, description: "updates expense when confidence is high" },
  { line: 347, description: "processes multiple expenses" },
  { line: 473, description: "handles concurrent categorizations" }
]

puts "Step 1: Running critical tests individually..."
puts "-" * 40

individual_results = []
critical_tests.each do |test|
  print "Testing line #{test[:line]} (#{test[:description]})... "
  result = run_test(test_file, test[:line])

  if result[:success] && result[:failures] == 0
    puts "✓ PASSED"
    individual_results << { test: test, passed: true }
  else
    puts "✗ FAILED"
    individual_results << { test: test, passed: false, result: result }
  end
end

puts
puts "Step 2: Running all engine tests together..."
puts "-" * 40

full_result = run_test(test_file)
if full_result[:success] && full_result[:failures] == 0
  puts "✓ Full suite PASSED (#{full_result[:examples]} examples, #{full_result[:pending]} pending)"
else
  puts "✗ Full suite FAILED (#{full_result[:failures]} failures out of #{full_result[:examples]} examples)"
end

puts
puts "Step 3: Running engine tests multiple times to check for state pollution..."
puts "-" * 40

3.times do |i|
  print "Run #{i + 1}... "
  result = run_test(test_file)

  if result[:success] && result[:failures] == 0
    puts "✓ PASSED"
  else
    puts "✗ FAILED (#{result[:failures]} failures)"
  end
end

puts
puts "=" * 80
puts "SUMMARY"
puts "=" * 80

all_individual_passed = individual_results.all? { |r| r[:passed] }
if all_individual_passed && full_result[:success]
  puts "✓ SUCCESS: All tests pass both individually and when run together!"
  puts "✓ The dependency injection refactoring has successfully resolved test isolation issues."
  exit 0
else
  puts "✗ FAILURE: Some tests are still failing."

  if !all_individual_passed
    puts "\nFailed individual tests:"
    individual_results.select { |r| !r[:passed] }.each do |r|
      puts "  - Line #{r[:test][:line]}: #{r[:test][:description]}"
    end
  end

  if !full_result[:success]
    puts "\nFull suite had #{full_result[:failures]} failures"
  end

  exit 1
end
