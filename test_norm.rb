# Test normalization options
matcher_with_norm = Categorization::Matchers::FuzzyMatcher.new(normalize_text: true)
candidates = [ "STARBUCKS" ]

# Test with normalization disabled via options
result = matcher_with_norm.match("starbucks", candidates, normalize_text: false)
puts "With normalization disabled via options:"
puts "  Matches found: #{result.matches.any?}"
puts "  Result: #{result.matches.inspect}"

# Test with normalization enabled (default)
result = matcher_with_norm.match("starbucks", candidates)
puts "\nWith normalization enabled (default):"
puts "  Matches found: #{result.matches.any?}"
puts "  Best score: #{result.best_score}"
