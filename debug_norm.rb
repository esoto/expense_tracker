# Debug normalization
matcher = Categorization::Matchers::FuzzyMatcher.new(normalize_text: true)

# Test text extraction
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

extractor = Categorization::Matchers::TextExtractor.new
puts "Expense merchant_name: #{expense.merchant_name}"
puts "Other expense merchant_name: #{other_expense.merchant_name}"
puts "Extracted from expense: #{extractor.extract_from(expense)}"
puts "Extracted from other_expense: #{extractor.extract_from(other_expense)}"

result = matcher.match("Coffee", [ expense, other_expense ])
puts "\nMatching 'Coffee' against expenses:"
puts "  Matches found: #{result.matches.count}"
result.matches.each do |m|
  puts "  - Text: #{m[:text]}, Score: #{m[:score]}"
end
