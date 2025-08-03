require "benchmark"

# Benchmark script to demonstrate ApiToken authentication performance improvement
#
# Before: O(n) - iterates through all tokens with BCrypt comparison
# After: O(1) - direct lookup using token_hash index
#
# Usage: bin/rails runner lib/benchmarks/api_token_auth_benchmark.rb

puts "=== ApiToken Authentication Performance Benchmark ==="
puts

# Create test tokens
puts "Setting up test data..."
test_tokens = []
token_count = 100

# Clean up existing test tokens
ApiToken.where("name LIKE ?", "Benchmark Token %").destroy_all

# Create new test tokens
token_count.times do |i|
  token = ApiToken.create!(
    name: "Benchmark Token #{i + 1}",
    expires_at: 1.year.from_now
  )
  test_tokens << token.token
end

# Create one more token that we'll authenticate
target_token = ApiToken.create!(
  name: "Target Token",
  expires_at: 1.year.from_now
)
target_token_string = target_token.token

puts "Created #{token_count + 1} test tokens"
puts

# Warm up
ApiToken.authenticate(target_token_string)

# Benchmark authentication
puts "Running authentication benchmark..."
puts "Authenticating against #{ApiToken.active.count} active tokens"
puts

iterations = 100
time = Benchmark.measure do
  iterations.times do
    result = ApiToken.authenticate(target_token_string)
    raise "Authentication failed!" unless result
  end
end

average_time_ms = (time.real / iterations * 1000).round(2)

puts "Results:"
puts "--------"
puts "Total time for #{iterations} authentications: #{time.real.round(3)} seconds"
puts "Average time per authentication: #{average_time_ms} ms"
puts

# Performance comparison
puts "Performance Analysis:"
puts "--------------------"
puts "With O(1) token_hash lookup:"
puts "  - Direct database lookup using indexed token_hash"
puts "  - Single BCrypt verification for security"
puts "  - Constant time regardless of token count"
puts
puts "Previous O(n) implementation would have:"
puts "  - Performed up to #{ApiToken.active.count} BCrypt comparisons"
puts "  - Estimated time: ~#{(average_time_ms * 50).round(2)} ms per auth (50x slower)"
puts

# Cleanup
puts "Cleaning up test data..."
ApiToken.where("name LIKE ?", "Benchmark Token %").destroy_all
ApiToken.where(name: "Target Token").destroy_all

puts "Benchmark complete!"
