#!/usr/bin/env ruby
# Performance test script to verify test suite improvements

require 'benchmark'
require 'open3'

puts "=" * 60
puts "Rails Test Suite Performance Analysis"
puts "=" * 60
puts

tests = [
  { name: "Models", path: "spec/models", expected_time: 20 },
  { name: "Services", path: "spec/services", expected_time: 90 },
  { name: "Controllers", path: "spec/controllers", expected_time: 45 }
]

results = []
total_time = 0

tests.each do |test|
  puts "Testing: #{test[:name]}"
  puts "-" * 40

  start_time = Time.now

  # Run the test with a timeout
  cmd = "bundle exec rspec #{test[:path]} --format progress 2>&1"
  output, status = Open3.capture2(cmd)

  elapsed = Time.now - start_time
  total_time += elapsed

  # Count examples and failures
  examples_match = output.match(/(\d+) examples?/)
  failures_match = output.match(/(\d+) failures?/)

  examples = examples_match ? examples_match[1].to_i : 0
  failures = failures_match ? failures_match[1].to_i : 0

  result = {
    name: test[:name],
    elapsed: elapsed,
    expected: test[:expected_time],
    examples: examples,
    failures: failures,
    passed: status.success? && failures == 0,
    performance_ok: elapsed <= test[:expected_time]
  }

  results << result

  puts "✓ Examples: #{examples}"
  puts "✓ Failures: #{failures}"
  puts "✓ Time: #{elapsed.round(2)}s (expected: <#{test[:expected_time]}s)"
  puts "✓ Status: #{result[:performance_ok] ? '✅ PASS' : '❌ SLOW'}"
  puts
end

puts "=" * 60
puts "SUMMARY"
puts "=" * 60
puts

results.each do |r|
  status = r[:performance_ok] ? "✅" : "❌"
  puts "#{status} #{r[:name].ljust(20)} #{r[:elapsed].round(2)}s / #{r[:expected]}s (#{r[:examples]} examples)"
end

puts
puts "Total time: #{total_time.round(2)}s"

# Performance verdict
all_passed = results.all? { |r| r[:performance_ok] }
if all_passed
  puts "🎉 All performance targets met!"
else
  slow_tests = results.reject { |r| r[:performance_ok] }
  puts "⚠️  #{slow_tests.size} test suite(s) running slower than expected:"
  slow_tests.each do |t|
    slowdown = ((t[:elapsed] / t[:expected]) - 1) * 100
    puts "  - #{t[:name]}: #{slowdown.round(0)}% slower than target"
  end
end
