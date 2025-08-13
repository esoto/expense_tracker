# frozen_string_literal: true

namespace :email do
  desc "Manually trigger email sync for a specific date range"
  task :sync, [ :since, :until ] => :environment do |task, args|
    puts "🔄 Manual Email Sync Task"
    puts "=" * 50

    # Parse arguments
    since_date = args[:since] ? Date.parse(args[:since]) : 1.month.ago
    until_date = args[:until] ? Date.parse(args[:until]) : Date.current

    puts "📅 Date range: #{since_date} to #{until_date}"
    puts "📧 Processing emails for all active accounts..."

    EmailAccount.active.find_each do |email_account|
      puts "\n🏦 Processing account: #{email_account.email}"

      begin
        # Load the service class
        require Rails.root.join("app/services/email/processing_service")

        # Create processing service with auto-categorization
        service = Services::Email::ProcessingService.new(email_account, {
          auto_categorize: true,
          limit: 500
        })

        # Test connection first
        puts "🔗 Testing connection..."
        connection_result = service.test_connection

        if connection_result[:success]
          puts "✅ Connection successful"

          # Process emails
          result = service.process_new_emails(since: since_date)

          if result[:success]
            metrics = result[:metrics] || {}
            details = result[:details] || {}

            puts "📊 Results:"
            puts "  - Emails found: #{metrics[:emails_found] || 0}"
            puts "  - Emails processed: #{metrics[:emails_processed] || 0}"
            puts "  - Expenses created: #{metrics[:expenses_created] || 0}"
            puts "  - Processing time: #{metrics[:processing_time]&.round(2) || 0}s"
            puts "  - Errors: #{details[:errors]&.length || 0}"

            if details[:errors]&.any?
              puts "❌ Errors:"
              details[:errors].each { |error| puts "    - #{error}" }
            end
          else
            puts "❌ Sync failed: #{result[:error]}"
          end
        else
          puts "🔒 Connection failed: #{connection_result[:message]}"
          puts "💡 This is expected in development without real credentials"

          # In development, create sample expenses for testing
          if Rails.env.development?
            puts "🧪 Creating sample expenses for testing..."
            create_sample_expenses(email_account, since_date, until_date)
          end
        end

      rescue => e
        puts "💥 Error processing #{email_account.email}: #{e.message}"
        puts "   #{e.backtrace.first}"
      end
    end

    puts "\n" + "=" * 50
    puts "✅ Email sync task completed!"

    # Show summary
    total_expenses = Expense.where(transaction_date: since_date..until_date).count
    categorized = Expense.where(transaction_date: since_date..until_date, auto_categorized: true).count

    puts "📈 Summary for #{since_date} to #{until_date}:"
    puts "  - Total expenses: #{total_expenses}"
    puts "  - Auto-categorized: #{categorized}"
    puts "  - Categorization rate: #{total_expenses > 0 ? (categorized.to_f / total_expenses * 100).round(1) : 0}%"
  end

  desc "Sync emails for last month"
  task sync_last_month: :environment do
    last_month_start = Date.current.beginning_of_month - 1.month
    last_month_end = Date.current.beginning_of_month - 1.day

    puts "📅 Syncing emails for last month (#{last_month_start} to #{last_month_end})"
    Rake::Task["email:sync"].invoke(last_month_start.to_s, last_month_end.to_s)
  end

  desc "Sync emails for current month"
  task sync_current_month: :environment do
    current_month_start = Date.current.beginning_of_month
    current_month_end = Date.current

    puts "📅 Syncing emails for current month (#{current_month_start} to #{current_month_end})"
    Rake::Task["email:sync"].invoke(current_month_start.to_s, current_month_end.to_s)
  end

  desc "Sync emails for a specific month (YYYY-MM format)"
  task :sync_month, [ :year_month ] => :environment do |task, args|
    year_month = args[:year_month] || Date.current.strftime("%Y-%m")

    begin
      date = Date.parse("#{year_month}-01")
      month_start = date.beginning_of_month
      month_end = date.end_of_month

      puts "📅 Syncing emails for #{date.strftime('%B %Y')} (#{month_start} to #{month_end})"
      Rake::Task["email:sync"].invoke(month_start.to_s, month_end.to_s)
    rescue ArgumentError
      puts "❌ Invalid date format. Use YYYY-MM format (e.g., 2025-07)"
    end
  end

  private

  def create_sample_expenses(email_account, since_date, until_date)
    # Sample expense data for testing
    sample_expenses = [
      { merchant: "Walmart", amount: 156.78, description: "Grocery shopping", category_hint: "groceries" },
      { merchant: "Shell", amount: 89.99, description: "Gas station", category_hint: "gas" },
      { merchant: "McDonald's", amount: 12.45, description: "Fast food", category_hint: "restaurants" },
      { merchant: "Amazon", amount: 67.89, description: "Online purchase", category_hint: "shopping" },
      { merchant: "Starbucks", amount: 8.50, description: "Coffee", category_hint: "coffee" }
    ]

    # Create 2-3 random expenses in the date range
    num_expenses = rand(2..4)

    num_expenses.times do |i|
      sample = sample_expenses.sample
      random_date = rand(since_date..until_date)

      begin
        require Rails.root.join("app/services/email/processing_service")
        service = Services::Email::ProcessingService.new(email_account, auto_categorize: true)
        expense_data = {
          amount: sample[:amount] + rand(-10.0..10.0).round(2),
          description: sample[:description],
          merchant: sample[:merchant],
          date: random_date,
          currency: "USD",
          raw_text: "Sample transaction at #{sample[:merchant]} for testing"
        }

        expense = service.send(:create_expense, expense_data)
        puts "  📝 Created: #{expense.merchant_name} - $#{expense.amount} (#{expense.category&.name || 'Uncategorized'})"

      rescue => e
        puts "  ❌ Failed to create sample expense: #{e.message}"
      end
    end
  end
end
