#!/usr/bin/env ruby

puts "🏦 Setting up BAC Email Account"
puts "You'll need:"
puts "  • Your BAC notification email address"
puts "  • App password (for Gmail/Outlook) or regular password"
puts ""

print "Enter your email address: "
email = gets.chomp

print "Enter your email provider (gmail/outlook/yahoo/custom): "
provider = gets.chomp

print "Enter your password (will be encrypted): "
system('stty -echo')
password = gets.chomp
system('stty echo')
puts ""

# Create the email account
require_relative 'config/environment'

begin
  email_account = EmailAccount.create!(
    provider: provider,
    email: email,
    encrypted_password: password,
    bank_name: "BAC",
    active: true
  )

  puts "✅ BAC email account created successfully!"
  puts "   Email: #{email_account.email}"
  puts "   Bank: #{email_account.bank_name}"
  puts "   ID: #{email_account.id}"
  puts ""
  puts "🚀 Ready to process BAC emails!"
  puts ""
  puts "📱 iPhone Shortcuts endpoints:"
  puts "   Process emails: POST /api/webhooks/process_emails"
  puts "   With specific account: POST /api/webhooks/process_emails?email_account_id=#{email_account.id}"
  puts ""
  puts "🔑 Use this API token: 2rOX-bkxeU9Cv1WCxxEA-hgLH3WbHWsOqanqTMH_vAY"

rescue ActiveRecord::RecordInvalid => e
  puts "❌ Error creating account: #{e.message}"
  puts "   Please check your inputs and try again."
end
