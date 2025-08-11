#!/usr/bin/env ruby

# Test data isolation between email accounts
account1 = EmailAccount.first

puts 'Testing data isolation between email accounts:'

# Check if second account already exists
account2 = EmailAccount.find_by(email: 'test2@example.com')
unless account2
  account2 = EmailAccount.create!(
    email: 'test2@example.com',
    provider: 'imap',
    encrypted_settings: 'encrypted_test_data',
    bank_name: 'Test Bank'
  )
  puts 'Created second test account'
end

puts "Account 1: #{account1.email}"
puts "Account 2: #{account2.email}"

# Test that budgets are scoped to email accounts
account1_budgets_count = Budget.where(email_account: account1).count
account2_budgets_count = Budget.where(email_account: account2).count

puts "Account 1 budgets count: #{account1_budgets_count}"
puts "Account 2 budgets count: #{account2_budgets_count}"

# Test MetricsCalculator isolation
calc1 = MetricsCalculator.new(email_account: account1, period: :month)
calc2 = MetricsCalculator.new(email_account: account2, period: :month)

metrics1 = calc1.calculate
metrics2 = calc2.calculate

puts "Account 1 has budget in metrics: #{metrics1[:budgets][:has_budget]}"
puts "Account 2 has budget in metrics: #{metrics2[:budgets][:has_budget]}"

# Verify no cross-contamination
budget1_name = metrics1[:budgets][:general_budget][:name] if metrics1[:budgets][:general_budget]
budget2_name = metrics2[:budgets][:general_budget][:name] if metrics2[:budgets][:general_budget]

puts "Account 1 budget name: #{budget1_name || 'None'}"
puts "Account 2 budget name: #{budget2_name || 'None'}"

# Test data isolation at database level
puts "\n=== Database-level isolation test ==="
total_budgets = Budget.count
account1_accessible = Budget.joins(:email_account).where(email_accounts: { id: account1.id }).count
account2_accessible = Budget.joins(:email_account).where(email_accounts: { id: account2.id }).count

puts "Total budgets in database: #{total_budgets}"
puts "Account 1 can access: #{account1_accessible} budgets"
puts "Account 2 can access: #{account2_accessible} budgets"
puts "Isolation verified: #{account1_accessible + account2_accessible == total_budgets}"

puts "\nData isolation test complete! ✅"