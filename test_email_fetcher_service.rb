require_relative 'config/environment'

puts "🔧 Testing EmailFetcher Service"
puts "==============================="

account = EmailAccount.find(2)
fetcher = EmailFetcher.new(account)

puts "Testing EmailFetcher with account: #{account.email}"
puts ""

# Test connection first
puts "🔌 Testing connection..."
if fetcher.test_connection
  puts "✅ Connection successful"
else
  puts "❌ Connection failed:"
  fetcher.errors.each { |error| puts "  - #{error}" }
  exit 1
end

puts ""

# Test fetching emails
puts "📧 Fetching emails from last 2 days..."
result = fetcher.fetch_new_emails(since: 2.days.ago)

if result
  puts "✅ Email fetch completed"
else
  puts "❌ Email fetch failed:"
  fetcher.errors.each { |error| puts "  - #{error}" }
end

puts ""

# Check how many expenses were created
expenses_count = Expense.count
puts "📊 Total expenses in system: #{expenses_count}"

# Show recent expenses
recent_expenses = Expense.order(created_at: :desc).limit(5)
if recent_expenses.any?
  puts ""
  puts "💰 Most recent expenses:"
  recent_expenses.each do |expense|
    puts "  - #{expense.formatted_amount} at #{expense.merchant_name} (#{expense.transaction_date})"
  end
end