#!/usr/bin/env ruby

# Test Budget creation for different periods
email_account = EmailAccount.first
if email_account.nil?
  puts 'No email account found. Creating one for testing...'
  email_account = EmailAccount.create!(
    email: 'test@example.com',
    password: 'password123',
    host: 'imap.example.com',
    port: 993,
    ssl: true
  )
  puts 'Created test email account'
end

puts "Using email account: #{email_account.email}"

# Test monthly budget creation
monthly_budget = Budget.new(
  email_account: email_account,
  name: 'Test Monthly Budget',
  amount: 500000,
  period: :monthly,
  currency: 'CRC'
)

puts 'Testing monthly budget validation:'
puts "Valid: #{monthly_budget.valid?}"
unless monthly_budget.valid?
  puts "Errors: #{monthly_budget.errors.full_messages}"
end

# Save if valid
if monthly_budget.save
  puts 'Monthly budget created successfully!'
  puts "Budget ID: #{monthly_budget.id}"
  puts "Usage percentage: #{monthly_budget.usage_percentage}%"
  puts "Status: #{monthly_budget.status}"
  puts "Status color: #{monthly_budget.status_color}"
else
  puts "Failed to save monthly budget: #{monthly_budget.errors.full_messages}"
end

# Test weekly budget
weekly_budget = Budget.new(
  email_account: email_account,
  name: 'Test Weekly Budget',
  amount: 125000,
  period: :weekly,
  currency: 'CRC'
)

if weekly_budget.save
  puts 'Weekly budget created successfully!'
  puts "Usage percentage: #{weekly_budget.usage_percentage}%"
else
  puts "Failed to save weekly budget: #{weekly_budget.errors.full_messages}"
end

# Test daily budget
daily_budget = Budget.new(
  email_account: email_account,
  name: 'Test Daily Budget',
  amount: 18000,
  period: :daily,
  currency: 'CRC'
)

if daily_budget.save
  puts 'Daily budget created successfully!'
  puts "Usage percentage: #{daily_budget.usage_percentage}%"
else
  puts "Failed to save daily budget: #{daily_budget.errors.full_messages}"
end

# Test yearly budget
yearly_budget = Budget.new(
  email_account: email_account,
  name: 'Test Yearly Budget',
  amount: 6000000,
  period: :yearly,
  currency: 'CRC'
)

if yearly_budget.save
  puts 'Yearly budget created successfully!'
  puts "Usage percentage: #{yearly_budget.usage_percentage}%"
else
  puts "Failed to save yearly budget: #{yearly_budget.errors.full_messages}"
end

puts "Total budgets created: #{Budget.count}"

# Test threshold validation
puts "\nTesting threshold validation..."
invalid_budget = Budget.new(
  email_account: email_account,
  name: 'Invalid Budget',
  amount: 100000,
  period: :monthly,
  currency: 'CRC',
  warning_threshold: 90,
  critical_threshold: 80  # Invalid: critical < warning
)

puts "Should be invalid: #{!invalid_budget.valid?}"
puts "Validation errors: #{invalid_budget.errors.full_messages}"

puts "\nTesting unique constraint..."
duplicate_budget = Budget.new(
  email_account: email_account,
  name: 'Duplicate Monthly Budget',
  amount: 300000,
  period: :monthly,  # Should conflict with existing monthly budget
  currency: 'CRC'
)

puts "Duplicate should be invalid: #{!duplicate_budget.valid?}"
puts "Duplicate errors: #{duplicate_budget.errors.full_messages}"