puts "🔧 Updating Gmail account password..."
puts "This script will help you update the encrypted password for your Gmail account."
puts

# Find the Gmail account
gmail_account = EmailAccount.find_by(email: "ecsoto07@gmail.com", provider: "gmail")

if gmail_account.nil?
  puts "❌ Gmail account not found!"
  exit 1
end

puts "📧 Found account: #{gmail_account.email}"
puts "🏦 Bank: #{gmail_account.bank_name}"
puts

puts "📝 Instructions:"
puts "1. Go to https://myaccount.google.com/security"
puts "2. Click 'App passwords' (you need 2-Step Verification enabled)"
puts "3. Generate a new app password for 'Mail'"
puts "4. Copy the 16-character password (format: abcd efgh ijkl mnop)"
puts

print "Enter the Gmail App Password: "
app_password = gets.chomp.strip

if app_password.empty?
  puts "❌ No password entered. Exiting."
  exit 1
end

# Remove spaces from app password if present
clean_password = app_password.gsub(/\s+/, '')

if clean_password.length != 16
  puts "⚠️  Warning: App passwords are usually 16 characters long."
  puts "   Your password is #{clean_password.length} characters."
  print "Continue anyway? (y/N): "
  
  unless gets.chomp.downcase == 'y'
    puts "❌ Aborted."
    exit 1
  end
end

begin
  # Update the encrypted password
  gmail_account.encrypted_password = clean_password
  gmail_account.save!
  
  puts "✅ Password updated successfully!"
  puts "🔄 Testing connection..."
  
  # Quick test
  require 'net/imap'
  imap_settings = gmail_account.imap_settings
  
  imap = Net::IMAP.new(imap_settings[:address], {
    port: imap_settings[:port],
    ssl: imap_settings[:enable_ssl]
  })
  
  imap.login(imap_settings[:user_name], imap_settings[:password])
  puts "✅ IMAP authentication successful!"
  
  imap.disconnect
  puts "✅ Gmail sync should now work properly!"
  
rescue ActiveRecord::RecordInvalid => e
  puts "❌ Failed to save account: #{e.message}"
rescue Net::IMAP::NoResponseError => e
  puts "❌ IMAP test failed: #{e.message}"
  puts "💡 Double-check the app password and try again."
rescue => e
  puts "❌ Error: #{e.message}"
ensure
  imap&.disconnect rescue nil
end