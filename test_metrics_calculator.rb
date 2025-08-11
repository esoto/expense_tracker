#!/usr/bin/env ruby

email_account = EmailAccount.first
calculator = MetricsCalculator.new(email_account: email_account, period: :day)
metrics = calculator.calculate!
budget_data = metrics[:budgets]

puts 'MetricsCalculator Daily Budget Data:'
if budget_data[:general_budget]
  gb = budget_data[:general_budget]  
  puts "Usage: #{gb[:usage_percentage]}%"
  puts "Status: #{gb[:status]}"
  puts "Status Color: #{gb[:status_color]}"
  puts "Current Spend: ₡#{gb[:current_spend].to_i}"
  puts "Amount: ₡#{gb[:amount].to_i}"
else
  puts 'No general budget found'
end

# Check the raw budget object
daily_budget = Budget.find_by(period: :daily)
puts "\nRaw Budget Object:"
puts "Usage: #{daily_budget.usage_percentage}%"
puts "Status: #{daily_budget.status}"
puts "Status Color: #{daily_budget.status_color}"
puts "Current Spend: ₡#{daily_budget.current_spend.to_i}"

# The issue might be that format_budget_data is calling calculate_current_spend!
puts "\nTesting format_budget_data method from MetricsCalculator..."