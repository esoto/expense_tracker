require_relative 'config/environment'

puts "🔐 Updating BAC Email Account Password"
puts "======================================"

print "Enter your Gmail App Password (16 characters): "
app_password = gets.chomp

account = EmailAccount.find(2)
account.encrypted_password = app_password

if account.save
  puts "✅ Password updated successfully!"
  
  # Test the connection
  puts "\n🔗 Testing connection..."
  fetcher = EmailFetcher.new(account)
  
  if fetcher.test_connection
    puts "✅ Gmail connection working!"
    puts "Ready to fetch BAC emails."
  else
    puts "❌ Still having connection issues:"
    fetcher.errors.each { |error| puts "  - #{error}" }
  end
else
  puts "❌ Failed to update password: #{account.errors.full_messages.join(', ')}"
end