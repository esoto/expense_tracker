matcher = Categorization::Matchers::FuzzyMatcher.new(normalize_text: true, min_confidence: 0.3)

expense = Expense.create!(
  merchant_normalized: "Starbucks Coffee",
  amount: 10,
  transaction_date: Date.today,
  status: "processed",
  email_account: EmailAccount.first || EmailAccount.create!(email: "test@test.com", bank_name: "Test Bank")
)

other_expense = Expense.create!(
  merchant_normalized: "Coffee Time",
  amount: 5,
  transaction_date: Date.today,
  status: "processed",
  email_account: EmailAccount.first || EmailAccount.create!(email: "test@test.com", bank_name: "Test Bank")
)

result = matcher.match("Coffee", [ expense, other_expense ])
puts "Matching 'Coffee' against expenses with lower threshold:"
puts "  Matches found: #{result.matches.count}"
result.matches.each do |m|
  puts "  - Text: #{m[:text]}, Score: #{m[:score]}"
end

# Test normalization
score1 = matcher.calculate_similarity("Coffee", "Starbucks Coffee")
score2 = matcher.calculate_similarity("Coffee", "Coffee Time")
puts "\nDirect similarity scores:"
puts "  'Coffee' vs 'Starbucks Coffee': #{score1}"
puts "  'Coffee' vs 'Coffee Time': #{score2}"
