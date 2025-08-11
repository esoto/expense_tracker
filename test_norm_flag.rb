# Test normalization flag handling
matcher_with_norm = Categorization::Matchers::FuzzyMatcher.new(normalize_text: true)
candidates = [ "STARBUCKS" ]

# Test with normalization disabled via options
puts "Testing normalize_text: false option:"
result = matcher_with_norm.match("starbucks", candidates, normalize_text: false)
puts "  Input: 'starbucks', Candidates: ['STARBUCKS']"
puts "  Matches found: #{result.matches.any?}"
puts "  Expected: false (case mismatch when not normalized)"

# Test with normalization enabled (default)
puts "\nTesting with normalization enabled (default):"
result = matcher_with_norm.match("starbucks", candidates)
puts "  Input: 'starbucks', Candidates: ['STARBUCKS']"
puts "  Matches found: #{result.matches.any?}"
puts "  Best score: #{result.best_score}"
puts "  Expected: true (should match when normalized)"

# Test with case-sensitive exact match
puts "\nTesting case-sensitive exact match:"
result = matcher_with_norm.match("STARBUCKS", candidates, normalize_text: false)
puts "  Input: 'STARBUCKS', Candidates: ['STARBUCKS']"
puts "  Matches found: #{result.matches.any?}"
puts "  Best score: #{result.best_score}"
puts "  Expected: true (exact match)"
