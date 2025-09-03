#!/usr/bin/env ruby
# Script to measure test performance improvements

require 'benchmark'
require 'json'

puts "=" * 60
puts "Test Performance Measurement Tool"
puts "=" * 60

test_groups = {
  "SyncSession" => "spec/models/sync_session_spec.rb",
  "ProcessEmailsJob" => "spec/jobs/process_emails_job_spec.rb",
  "Email::ProcessingService" => "spec/services/email/integration/processing_service_integration_spec.rb"
}

results = {}

test_groups.each do |name, path|
  print "\nTesting #{name}... "
  time = Benchmark.realtime do
    system("bundle exec rspec #{path} --format progress > /dev/null 2>&1")
  end

  results[name] = time.round(2)
  puts "#{time.round(2)} seconds"
end

puts "\n" + "=" * 60
puts "Performance Summary"
puts "=" * 60

expected_improvements = {
  "SyncSession" => { before: 21.28, target: 5.0 },
  "ProcessEmailsJob" => { before: 1.76, target: 0.5 },
  "Email::ProcessingService" => { before: 0.11, target: 0.05 }
}

total_improvement = 0
test_groups.keys.each do |name|
  current = results[name]
  expected = expected_improvements[name]
  before_time = expected[:before]
  improvement_pct = ((before_time - current) / before_time * 100).round(1)
  total_improvement += improvement_pct

  status = current <= expected[:target] ? "✅" : "⚠️"

  puts "#{status} #{name}:"
  puts "   Before: #{before_time}s"
  puts "   Current: #{current}s"
  puts "   Improvement: #{improvement_pct}%"
  puts "   Target: #{expected[:target]}s"
end

avg_improvement = (total_improvement / test_groups.size).round(1)
puts "\n📊 Average Improvement: #{avg_improvement}%"

# Save results to JSON for tracking
File.write('test_performance_results.json', JSON.pretty_generate({
  timestamp: Time.now.iso8601,
  results: results,
  average_improvement: avg_improvement
}))

puts "\nResults saved to test_performance_results.json"
