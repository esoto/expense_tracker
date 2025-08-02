require_relative 'config/environment'

puts "🔍 Debugging CLAUDE.AI Email Structure"
puts "====================================="

account = EmailAccount.find(2)
require 'net/imap'

imap_settings = account.imap_settings
imap = Net::IMAP.new(
  imap_settings[:address],
  port: imap_settings[:port],
  ssl: imap_settings[:enable_ssl]
)

imap.login(imap_settings[:user_name], imap_settings[:password])
imap.select('INBOX')

# Find the CLAUDE.AI email (message ID 3976 from earlier)
message_id = 3976

puts "Testing with CLAUDE.AI email (message ID: #{message_id})"

# Get the HTML content from part 1
html_content = imap.fetch(message_id, 'BODY[1]')[0].attr['BODY[1]']

puts "\n📄 Raw HTML (first 300 chars):"
puts html_content[0..300]

# Test our HTML extraction method
fetcher = EmailFetcher.new(account)
extracted_text = fetcher.send(:extract_text_from_html, html_content)

puts "\n✨ Extracted Text:"
puts extracted_text

puts "\n🔍 Looking for key patterns:"
puts "Contains 'CLAUDE.AI'? #{extracted_text.include?('CLAUDE.AI')}"
puts "Contains 'Comercio'? #{extracted_text.include?('Comercio')}"
puts "Contains 'Monto'? #{extracted_text.include?('Monto')}"
puts "Contains 'USD'? #{extracted_text.include?('USD')}"

# Test parsing with BAC rule
rule = ParsingRule.find_by(bank_name: 'BAC')
if rule
  puts "\n💰 Testing parsing with BAC rule:"
  parsed_data = rule.parse_email(extracted_text)
  
  puts "Amount: #{parsed_data[:amount]}"
  puts "Date: #{parsed_data[:transaction_date]}"
  puts "Merchant: #{parsed_data[:merchant_name]}"
  puts "Description: #{parsed_data[:description]}"
  
  # Test each pattern individually
  puts "\n🧪 Testing patterns individually:"
  puts "Amount match: #{extracted_text.match(Regexp.new(rule.amount_pattern, Regexp::IGNORECASE))&.to_a}"
  puts "Merchant match: #{extracted_text.match(Regexp.new(rule.merchant_pattern, Regexp::IGNORECASE))&.to_a}"
  puts "Date match: #{extracted_text.match(Regexp.new(rule.date_pattern, Regexp::IGNORECASE))&.to_a}"
  puts "Description match: #{extracted_text.match(Regexp.new(rule.description_pattern, Regexp::IGNORECASE))&.to_a}"
end

imap.logout
imap.disconnect