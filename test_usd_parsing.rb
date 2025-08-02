require_relative 'config/environment'

puts "🧪 Testing USD Transaction Parsing"
puts "================================="

# Simulate the CLAUDE.AI subscription email content based on the screenshot
usd_email_content = <<~EMAIL_BODY
  Hola ROGER ESTEBAN SOTO MADRIZ A continuación le detallamos la transacción realizada:

  Comercio: CLAUDE.AI SUBSCRIPTION
  Ciudad y país: +14152360599, País no Definido
  Fecha: Ago 1, 2025, 00:25
  VISA ************1972
  Autorización: 355684
  Referencia: 521306346420
  Tipo de Transacción: COMPRA
  Monto: USD 20.00

  ¿Tiene dudas sobre esta transacción?
EMAIL_BODY

puts "📧 Email content:"
puts email_content = usd_email_content

# Get BAC parsing rule
rule = ParsingRule.find_by(bank_name: 'BAC')
puts "\n🔍 Testing with BAC parsing rule:"
puts "Amount pattern: #{rule.amount_pattern}"

# Test parsing
parsed_data = rule.parse_email(email_content)

puts "\n💰 Parsed Data:"
puts "Amount: #{parsed_data[:amount]}"
puts "Date: #{parsed_data[:transaction_date]}"
puts "Merchant: #{parsed_data[:merchant_name]}"
puts "Description: #{parsed_data[:description]}"

# Test if this would create an expense
if parsed_data[:amount].present? && parsed_data[:transaction_date].present?
  puts "\n✅ Essential data present - expense could be created!"
  puts "Amount: #{parsed_data[:amount]} (#{parsed_data[:amount].class})"
  puts "Date: #{parsed_data[:transaction_date]} (#{parsed_data[:transaction_date].class})"
else
  puts "\n❌ Missing essential data:"
  puts "Amount: #{parsed_data[:amount] || 'MISSING'}"
  puts "Date: #{parsed_data[:transaction_date] || 'MISSING'}"
end
