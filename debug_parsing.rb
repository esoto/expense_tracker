require_relative 'config/environment'

puts "🔍 Debugging BAC Parsing Step by Step"
puts "====================================="

# Test email content
email_body = <<~EMAIL_BODY
  Notificación de transacción

  Estimado cliente,

  Se ha realizado una transacción con su tarjeta:

  Comercio: PTA LEONA SOC
  Fecha: Ago 1, 2025, 14:16
  Monto: CRC 95,000.00
  Tipo de Transacción: COMPRA
  
  Si no reconoce esta transacción, comuníquese inmediatamente con BAC.
EMAIL_BODY

# Get BAC parsing rule
rule = ParsingRule.find_by(bank_name: 'BAC')

puts "Testing each pattern individually:"
puts "================================="

# Test amount parsing
puts "\n1. Amount Pattern:"
puts "   Pattern: #{rule.amount_pattern}"
parsed_data = rule.parse_email(email_body)
puts "   Parsed amount: #{parsed_data[:amount]}"
puts "   Type: #{parsed_data[:amount].class}"

# Test date parsing  
puts "\n2. Date Pattern:"
puts "   Pattern: #{rule.date_pattern}"
puts "   Parsed date: #{parsed_data[:transaction_date]}"
puts "   Type: #{parsed_data[:transaction_date].class}"

# Test merchant
puts "\n3. Merchant Pattern:"
puts "   Pattern: #{rule.merchant_pattern}"
puts "   Parsed merchant: #{parsed_data[:merchant_name]}"

# Test description
puts "\n4. Description Pattern:"
puts "   Pattern: #{rule.description_pattern}"
puts "   Parsed description: #{parsed_data[:description]}"

puts "\n📊 Complete Parsed Data:"
puts "========================"
parsed_data.each do |key, value|
  puts "#{key}: #{value.inspect} (#{value.class})"
end

# Check what the EmailParser validation is looking for
puts "\n🔍 Checking Validation Requirements:"
puts "===================================="
puts "Amount present? #{parsed_data[:amount].present?}"
puts "Date present? #{parsed_data[:transaction_date].present?}"

# Try to create the expense manually
puts "\n💰 Manual Expense Creation Test:"
puts "================================"

account = EmailAccount.find(2)

if parsed_data[:amount].present? && parsed_data[:transaction_date].present?
  begin
    expense = Expense.new(
      email_account: account,
      amount: parsed_data[:amount],
      transaction_date: parsed_data[:transaction_date],
      merchant_name: parsed_data[:merchant_name],
      description: parsed_data[:description],
      raw_email_content: email_body,
      parsed_data: parsed_data.to_json,
      status: "pending"
    )

    if expense.valid?
      expense.save!
      puts "✅ Manual expense creation SUCCESS!"
      puts "   ID: #{expense.id}"
      puts "   Amount: #{expense.formatted_amount}"
    else
      puts "❌ Expense validation failed:"
      expense.errors.full_messages.each { |msg| puts "  - #{msg}" }
    end
  rescue => e
    puts "❌ Error creating expense: #{e.message}"
  end
else
  puts "❌ Missing essential data:"
  puts "  Amount: #{parsed_data[:amount] || 'MISSING'}"
  puts "  Date: #{parsed_data[:transaction_date] || 'MISSING'}"
end