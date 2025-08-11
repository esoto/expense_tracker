#!/usr/bin/env ruby

# Test Budget threshold calculations and color coding
email_account = EmailAccount.first
puts "Testing with email account: #{email_account.email}"

# Create test expenses to simulate different usage levels
category = Category.first || Category.create!(name: 'Test Category')

# Get existing budgets for testing
weekly_budget = Budget.where(period: :weekly).first
daily_budget = Budget.where(period: :daily).first
yearly_budget = Budget.where(period: :yearly).first

puts "\n=== Testing Color Coding and Status Thresholds ==="

# Test each budget type with different spending levels
budgets_to_test = [weekly_budget, daily_budget, yearly_budget].compact

budgets_to_test.each do |budget|
  puts "\n--- Testing #{budget.period} budget (₡#{budget.amount.to_i}) ---"
  
  # Force recalculate
  budget.calculate_current_spend!
  
  current_percentage = budget.usage_percentage
  puts "Current spending: ₡#{budget.current_spend_amount.to_i} (#{current_percentage}%)"
  puts "Status: #{budget.status}"
  puts "Status Color: #{budget.status_color}"
  puts "Status Message: #{budget.status_message}"
  puts "On Track: #{budget.on_track?}"
  
  # Test threshold logic
  case current_percentage
  when 0...70
    expected_status = :good
    expected_color = 'emerald-600'
  when 70...90
    expected_status = :warning  
    expected_color = 'amber-600'
  when 90...100
    expected_status = :critical
    expected_color = 'rose-500'
  else
    expected_status = :exceeded
    expected_color = 'rose-600'
  end
  
  puts "Expected Status: #{expected_status} -> Actual: #{budget.status}"
  puts "Expected Color: #{expected_color} -> Actual: #{budget.status_color}"
  
  status_correct = budget.status == expected_status
  color_correct = budget.status_color == expected_color
  
  puts "✓ Status correct: #{status_correct}"
  puts "✓ Color correct: #{color_correct}"
  
  # Test formatted amounts
  puts "Formatted Amount: #{budget.formatted_amount}"
  puts "Formatted Remaining: #{budget.formatted_remaining}"
  puts "Remaining Amount: ₡#{budget.remaining_amount.to_i}"
end

puts "\n=== Testing Edge Cases ==="

# Test zero budget
puts "\nTesting zero usage (new budget)..."
new_budget = Budget.create!(
  email_account: email_account,
  name: 'New Empty Budget',
  amount: 100000,
  period: :monthly,
  currency: 'USD'
)

puts "Zero usage - Status: #{new_budget.status}, Color: #{new_budget.status_color}"

# Test 70% exactly (warning threshold)
puts "\nTesting custom thresholds..."
custom_budget = Budget.create!(
  email_account: email_account,
  name: 'Custom Threshold Budget',
  amount: 100000,
  period: :weekly,
  currency: 'USD',
  category: category,
  warning_threshold: 60,
  critical_threshold: 80
)

# Manually set spending to test thresholds
custom_budget.update_columns(current_spend: 65000) # 65%
puts "65% usage (warning at 60%): Status: #{custom_budget.status}, Color: #{custom_budget.status_color}"

custom_budget.update_columns(current_spend: 85000) # 85%
puts "85% usage (critical at 80%): Status: #{custom_budget.status}, Color: #{custom_budget.status_color}"

custom_budget.update_columns(current_spend: 105000) # 105%
puts "105% usage (exceeded): Status: #{custom_budget.status}, Color: #{custom_budget.status_color}"

puts "\n=== Testing MetricsCalculator Integration ==="

calculator = MetricsCalculator.new(email_account: email_account, period: :month)
metrics = calculator.calculate

budget_data = metrics[:budgets]
puts "Has budget: #{budget_data[:has_budget]}"
puts "General budget present: #{budget_data[:general_budget].present?}"
puts "Category budgets count: #{budget_data[:category_budgets].length}"
puts "Total budget amount: ₡#{budget_data[:total_budget_amount].to_i}"
puts "Overall usage: #{budget_data[:overall_usage]}%"

if budget_data[:general_budget]
  general = budget_data[:general_budget]
  puts "\nGeneral budget details:"
  puts "  Name: #{general[:name]}"
  puts "  Amount: ₡#{general[:amount].to_i}"
  puts "  Current spend: ₡#{general[:current_spend].to_i}"
  puts "  Usage: #{general[:usage_percentage]}%"
  puts "  Status: #{general[:status]}"
  puts "  Status color: #{general[:status_color]}"
end

puts "\nBudget testing completed!"