# frozen_string_literal: true

namespace :email do
  desc "Manually trigger email sync for a specific date range"
  task :sync, [ :since, :until ] => :environment do |task, args|
    puts "Manual Email Sync Task"
    puts "=" * 50

    # Parse arguments
    since_date = args[:since] ? Date.parse(args[:since]) : 1.month.ago
    until_date = args[:until] ? Date.parse(args[:until]) : Date.current

    puts "Date range: #{since_date} to #{until_date}"
    puts "Processing emails for all active accounts..."

    EmailAccount.active.find_each do |email_account|
      puts "\nProcessing account: #{email_account.email}"

      begin
        fetcher = Services::EmailProcessing::Fetcher.new(email_account)
        result = fetcher.fetch_new_emails(since: since_date.to_time)

        if result.success?
          puts "Results:"
          puts "  - Emails found: #{result.total_emails_found}"
          puts "  - Emails processed: #{result.processed_emails_count}"
          if result.has_errors?
            puts "Warnings:"
            result.error_messages.each { |msg| puts "  - #{msg}" }
          end
        else
          puts "Sync failed: #{result.error_messages}"
        end
      rescue => e
        puts "Error processing #{email_account.email}: #{e.message}"
        puts "   #{e.backtrace.first}"
      end
    end

    puts "\n" + "=" * 50
    puts "Email sync task completed!"

    # Show summary
    total_expenses = Expense.where(transaction_date: since_date..until_date).count
    categorized = Expense.where(transaction_date: since_date..until_date, auto_categorized: true).count

    puts "Summary for #{since_date} to #{until_date}:"
    puts "  - Total expenses: #{total_expenses}"
    puts "  - Auto-categorized: #{categorized}"
    puts "  - Categorization rate: #{total_expenses > 0 ? (categorized.to_f / total_expenses * 100).round(1) : 0}%"
  end

  desc "Sync emails for last month"
  task sync_last_month: :environment do
    last_month_start = Date.current.beginning_of_month - 1.month
    last_month_end = Date.current.beginning_of_month - 1.day

    puts "Syncing emails for last month (#{last_month_start} to #{last_month_end})"
    Rake::Task["email:sync"].invoke(last_month_start.to_s, last_month_end.to_s)
  end

  desc "Sync emails for current month"
  task sync_current_month: :environment do
    current_month_start = Date.current.beginning_of_month
    current_month_end = Date.current

    puts "Syncing emails for current month (#{current_month_start} to #{current_month_end})"
    Rake::Task["email:sync"].invoke(current_month_start.to_s, current_month_end.to_s)
  end

  desc "Sync emails for a specific month (YYYY-MM format)"
  task :sync_month, [ :year_month ] => :environment do |task, args|
    year_month = args[:year_month] || Date.current.strftime("%Y-%m")

    begin
      date = Date.parse("#{year_month}-01")
      month_start = date.beginning_of_month
      month_end = date.end_of_month

      puts "Syncing emails for #{date.strftime('%B %Y')} (#{month_start} to #{month_end})"
      Rake::Task["email:sync"].invoke(month_start.to_s, month_end.to_s)
    rescue ArgumentError
      puts "Invalid date format. Use YYYY-MM format (e.g., 2025-07)"
    end
  end
end
