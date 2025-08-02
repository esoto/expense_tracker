require_relative 'config/environment'

puts '🎯 Processing All BAC Transaction Emails'
puts '======================================='

account = EmailAccount.find(2)
require 'net/imap'

begin
  imap_settings = account.imap_settings
  imap = Net::IMAP.new(
    imap_settings[:address],
    port: imap_settings[:port],
    ssl: imap_settings[:enable_ssl]
  )
  
  imap.login(imap_settings[:user_name], imap_settings[:password])
  imap.select('INBOX')
  
  # Find transaction emails
  message_ids = imap.search(['SINCE', 3.days.ago.strftime('%d-%b-%Y')])
  
  processed_emails = 0
  created_expenses = []
  
  message_ids.each do |msg_id|
    envelope = imap.fetch(msg_id, 'ENVELOPE')[0].attr['ENVELOPE']
    subject = envelope.subject || ''
    
    # Check if this is a transaction email (not transfer)
    if subject.include?('transacci') && !subject.include?('Transferencia')
      puts "Processing: #{subject}"
      
      from = envelope.from&.first&.mailbox + '@' + envelope.from&.first&.host if envelope.from&.first
      body_data = imap.fetch(msg_id, 'BODY[TEXT]')[0].attr['BODY[TEXT]']
      
      email_data = {
        message_id: msg_id,
        from: from,
        subject: subject,
        date: envelope.date,
        body: body_data
      }
      
      # Parse the email
      parser = EmailParser.new(account, email_data)
      expense = parser.parse_expense
      
      if expense
        created_expenses << expense
        puts "  ✅ Created expense: #{expense.formatted_amount} at #{expense.merchant_name}"
        puts "     Status: #{expense.status}"
      else
        puts "  ❌ Failed to parse:"
        parser.errors.each { |error| puts "     - #{error}" }
        
        # Show email content preview for debugging
        puts "     Email content preview:"
        puts "     #{body_data[0..300]}..." if body_data
      end
      
      processed_emails += 1
      puts ''
    end
  end
  
  puts "📊 Processing Summary:"
  puts "   Emails processed: #{processed_emails}"
  puts "   Expenses created: #{created_expenses.length}"
  
  if created_expenses.any?
    puts ''
    puts '💰 New Expenses:'
    created_expenses.each do |expense|
      puts "   - #{expense.formatted_amount} at #{expense.merchant_name} (#{expense.transaction_date.strftime('%Y-%m-%d')})"
    end
  end
  
  # Show total expenses in system
  puts ""
  puts "📊 Total expenses in system: #{Expense.count}"
  
  imap.logout
  imap.disconnect
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end