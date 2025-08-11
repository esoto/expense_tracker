#!/usr/bin/env ruby

# Create expenses to test color thresholds properly
email_account = EmailAccount.first
daily_budget = Budget.find_by(period: :daily)

puts "Current daily budget: ₡#{daily_budget.amount.to_i}"
puts "Warning threshold (70%): ₡#{(daily_budget.amount * 0.7).to_i}"
puts "Critical threshold (90%): ₡#{(daily_budget.amount * 0.9).to_i}"

# Create expense that puts us at exceeded level (110% of budget) 
exceeded_amount = (daily_budget.amount * 1.10).to_i

# Delete existing test expenses first to have clean data  
email_account.expenses.where('merchant_name LIKE ?', 'Test%').delete_all
puts "Deleted existing test expenses"

# Create new test expense for today
test_expense = Expense.create!(
  email_account: email_account,
  merchant_name: 'Test Exceeded Level Expense',
  amount: exceeded_amount,
  transaction_date: Date.current,
  currency: :crc,
  bank_name: 'Test Bank',
  description: 'Test expense to trigger exceeded threshold'
)

puts "Created test expense: ₡#{test_expense.amount} on #{test_expense.transaction_date}"

# Let the budget recalculate
daily_budget.calculate_current_spend!
puts "Updated daily budget usage: #{daily_budget.usage_percentage}% - Status: #{daily_budget.status} - Color: #{daily_budget.status_color}"

# Clear caches
Rails.cache.clear
MetricsCalculator.clear_cache