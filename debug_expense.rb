require 'factory_bot_rails'

e1 = FactoryBot.create(:expense, merchant_normalized: "Starbucks Coffee")
e2 = FactoryBot.create(:expense, merchant_normalized: "Coffee Time")

extractor = Categorization::Matchers::TextExtractor.new
puts "E1 merchant_name: #{e1.merchant_name}"
puts "E2 merchant_name: #{e2.merchant_name}"
puts "E1 extracted: #{extractor.extract_from(e1)}"
puts "E2 extracted: #{extractor.extract_from(e2)}"

matcher = Categorization::Matchers::FuzzyMatcher.new
result = matcher.match("Coffee", [ e1, e2 ])
puts "\nMatching 'Coffee' against expenses:"
result.matches.each do |m|
  puts "  Text: #{m[:text]}, Score: #{m[:score]}"
end
