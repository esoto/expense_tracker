require_relative 'config/environment'

puts "🎯 Testing BAC Email Processing"
puts "==============================="

# Simulate the actual BAC email content based on your voucher
bac_email_content = {
  message_id: 12345,
  from: "notificaciones@bac.net",
  subject: "Notificación de transacción PTA LEONA SOC 01-08-2025 - 14:16",
  date: Time.parse("2025-08-01 14:16:00"),
  body: <<~EMAIL_BODY
    Notificación de transacción

    Estimado cliente,

    Se ha realizado una transacción con su tarjeta:

    Comercio: PTA LEONA SOC
    Fecha: Ago 1, 2025, 14:16
    Monto: CRC 95,000.00
    Tipo de Transacción: COMPRA
    
    Si no reconoce esta transacción, comuníquese inmediatamente con BAC.
    
    Gracias,
    BAC San José
  EMAIL_BODY
}

# Get your BAC account
account = EmailAccount.find(2)
puts "Processing with account: #{account.email}"
puts ""

# Test the parser
puts "🔍 Testing EmailParser..."
parser = EmailParser.new(account, bac_email_content)

# Check if parsing rule exists
parsing_rule = ParsingRule.find_by(bank_name: 'BAC')
if parsing_rule
  puts "✅ BAC parsing rule found"
  
  # Test patterns
  puts "\n📋 Testing parsing patterns:"
  test_results = parsing_rule.test_patterns(bac_email_content[:body])
  
  puts "  Amount: #{test_results[:amount]&.dig(:matched) ? '✅' : '❌'}"
  puts "  Date: #{test_results[:date]&.dig(:matched) ? '✅' : '❌'}"
  puts "  Merchant: #{test_results[:merchant]&.dig(:matched) ? '✅' : '❌'}"
  puts "  Description: #{test_results[:description]&.dig(:matched) ? '✅' : '❌'}"
  
  # Actually parse the email
  puts "\n💰 Creating expense from email..."
  expense = parser.parse_expense
  
  if expense
    puts "✅ SUCCESS! Expense created:"
    puts "   ID: #{expense.id}"
    puts "   Amount: #{expense.formatted_amount}"
    puts "   Merchant: #{expense.merchant_name}"
    puts "   Date: #{expense.transaction_date}"
    puts "   Category: #{expense.category&.name || 'None'}"
    puts "   Status: #{expense.status}"
    puts "   Bank: #{expense.bank_name}"
    
    puts "\n📊 Total expenses now: #{Expense.count}"
    
  else
    puts "❌ Failed to create expense!"
    puts "Errors:"
    parser.errors.each { |error| puts "  - #{error}" }
  end
  
else
  puts "❌ No BAC parsing rule found!"
end