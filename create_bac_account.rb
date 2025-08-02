require_relative 'config/environment'

puts "🏦 Creating BAC Email Account for ecsoto07@gmail.com"

# You'll need to replace 'your_gmail_app_password' with your actual Gmail app password
# To get a Gmail app password:
# 1. Go to Google Account settings
# 2. Security > 2-Step Verification > App passwords
# 3. Generate an app password for "Mail"

password = "Xm7FRYXmrX;YVy9D"  # Replace this with your actual app password

begin
  email_account = EmailAccount.create!(
    provider: "gmail",
    email: "ecsoto07@gmail.com",
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
  puts "   Process all emails: POST /api/webhooks/process_emails"
  puts "   Process specific account: POST /api/webhooks/process_emails?email_account_id=#{email_account.id}"
  puts ""
  puts "🔑 API Token: 2rOX-bkxeU9Cv1WCxxEA-hgLH3WbHWsOqanqTMH_vAY"
  puts ""
  puts "📧 Gmail App Password Setup:"
  puts "   1. Go to https://myaccount.google.com/security"
  puts "   2. Enable 2-Step Verification if not already enabled"
  puts "   3. Go to App passwords and generate one for 'Mail'"
  puts "   4. Update the password in this script and run again"

rescue ActiveRecord::RecordInvalid => e
  puts "❌ Error creating account: #{e.message}"
end