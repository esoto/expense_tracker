require_relative 'config/environment'

puts "🧪 Testing HTML Extraction"
puts "========================="

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

# Find the PTA LEONA email (message ID 4002)
message_id = 4002

puts "Testing with message ID: #{message_id}"

# Get the HTML content from part 1
html_content = imap.fetch(message_id, 'BODY[1]')[0].attr['BODY[1]']

puts "\n📄 Raw HTML (first 500 chars):"
puts html_content[0..500]

# Test our HTML extraction method
fetcher = EmailFetcher.new(account)
extracted_text = fetcher.send(:extract_text_from_html, html_content)

puts "\n✨ Extracted Text:"
puts extracted_text

puts "\n🔍 Looking for key patterns:"
puts "Contains 'PTA LEONA'? #{extracted_text.include?('PTA LEONA')}"
puts "Contains 'Comercio'? #{extracted_text.include?('Comercio')}"
puts "Contains 'Monto'? #{extracted_text.include?('Monto')}"
puts "Contains 'Fecha'? #{extracted_text.include?('Fecha')}"

# Test parsing with BAC rule
rule = ParsingRule.find_by(bank_name: 'BAC')
if rule
  puts "\n💰 Testing parsing with BAC rule:"
  parsed_data = rule.parse_email(extracted_text)

  puts "Amount: #{parsed_data[:amount]}"
  puts "Date: #{parsed_data[:transaction_date]}"
  puts "Merchant: #{parsed_data[:merchant_name]}"
  puts "Description: #{parsed_data[:description]}"
end

imap.logout
imap.disconnect
