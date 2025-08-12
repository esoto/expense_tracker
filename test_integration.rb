# Test the integration scenario
matcher = Categorization::Matchers::FuzzyMatcher.new

category = Category.create!(name: "Food")

pattern1 = CategorizationPattern.create!(
  pattern_value: "Starbucks",
  pattern_type: "merchant",
  category: category,
  confidence_weight: 1.0
)

pattern2 = CategorizationPattern.create!(
  pattern_value: "Coffee Shop",
  pattern_type: "keyword",
  category: category,
  confidence_weight: 0.8
)

email_account = EmailAccount.first || EmailAccount.create!(email: "test@test.com", bank_name: "Test Bank")

expense = Expense.create!(
  merchant_normalized: "STARBUCKS COFFEE #12345",
  description: "Morning coffee purchase",
  amount: 10,
  transaction_date: Date.today,
  status: "processed",
  email_account: email_account
)

patterns = [ pattern1, pattern2 ]

puts "Expense merchant_name: #{expense.merchant_name}"
puts "Pattern1 value: #{pattern1.pattern_value}"
puts "Pattern1 effective_confidence: #{pattern1.effective_confidence}"
puts "Pattern2 value: #{pattern2.pattern_value}"
puts "Pattern2 effective_confidence: #{pattern2.effective_confidence}"

result = matcher.match_pattern(expense.merchant_name, patterns)

puts "\nResults:"
result.matches.each do |match|
  puts "  Pattern: #{match[:text]}"
  puts "  Score: #{match[:score]}"
  puts "  Adjusted Score: #{match[:adjusted_score]}"
  puts "  Pattern ID: #{match[:id]}"
  puts "  ---"
end
