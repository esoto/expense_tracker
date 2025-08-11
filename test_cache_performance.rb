#!/usr/bin/env ruby
# Test pattern cache performance

cache = Categorization::PatternCache.instance
cat = Category.first || Category.create!(name: "Test")

# Create test patterns if needed
if CategorizationPattern.count < 10
  10.times do |i|
    CategorizationPattern.create!(
      category: cat,
      pattern_type: "merchant",
      pattern_value: "Test Merchant #{i}",
      active: true
    )
  end
end

# Warm cache
puts "Warming cache..."
cache.warm_cache

# Test performance
require "benchmark"
times = []
puts "Running performance test..."
100.times do
  pattern = CategorizationPattern.active.sample
  time = Benchmark.realtime { cache.get_pattern(pattern.id) }
  times << time * 1000 # Convert to ms
end

puts "\n=== Performance Results ==="
puts "Average time: #{(times.sum / times.size).round(3)}ms"
puts "Max time: #{times.max.round(3)}ms"
puts "Min time: #{times.min.round(3)}ms"
puts "P95: #{times.sort[(times.size * 0.95).to_i].round(3)}ms"

puts "\n=== Cache Metrics ==="
metrics = cache.metrics
puts "Hit rate: #{metrics[:hit_rate]}%"
puts "Memory hits: #{metrics[:hits][:memory]}"
puts "Redis hits: #{metrics[:hits][:redis]}"
puts "Misses: #{metrics[:misses]}"
puts "Redis available: #{metrics[:redis_available]}"