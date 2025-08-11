matcher = Categorization::Matchers::FuzzyMatcher.new
result = matcher.match("starbucks", [ "STARBUCKS" ], normalize_text: false)
puts "Without normalization - Matches: #{result.matches.size}"
puts "Matches details: #{result.matches.inspect}"

result = matcher.match("starbucks", [ "STARBUCKS" ], normalize_text: true)
puts "\nWith normalization - Matches: #{result.matches.size}"
puts "Matches details: #{result.matches.inspect}"

# Test similarity calculation
score = matcher.calculate_similarity("starbucks", "STARBUCKS")
puts "\nSimilarity score with normalization: #{score}"

# Test raw similarity without normalization
score_raw = matcher.calculate_similarity_raw("starbucks", "STARBUCKS")
puts "Raw similarity score (no normalization): #{score_raw}"

score_raw2 = matcher.calculate_similarity_raw("starbucks", "starbucks")
puts "Raw similarity score (same case): #{score_raw2}"
