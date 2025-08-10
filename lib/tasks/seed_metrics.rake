namespace :metrics do
  desc "Seed performance metrics with test data"
  task seed: :environment do
    puts "Creating test sync metrics..."

    # Get or create test sync session and email accounts
    sync_session = SyncSession.first || SyncSession.create!(
      status: "completed",
      total_emails: 1000,
      processed_emails: 1000,
      detected_expenses: 150,
      started_at: 30.days.ago,
      completed_at: 30.days.ago + 2.hours
    )

    email_accounts = EmailAccount.active.presence || [
      EmailAccount.create!(
        provider: "gmail",
        email: "test1@example.com",
        bank_name: "BAC San José",
        active: true
      ),
      EmailAccount.create!(
        provider: "gmail",
        email: "test2@example.com",
        bank_name: "Banco Nacional",
        active: true
      )
    ]

    # Create metrics for the last 30 days
    metrics_to_create = []

    30.times do |day|
      date = day.days.ago

      # Create session-level metrics
      3.times do |i|
        start_time = date.beginning_of_day + (i * 8).hours + rand(0..180).minutes
        duration = rand(30000..180000) # 30 seconds to 3 minutes

        metrics_to_create << SyncMetric.new(
          sync_session: sync_session,
          metric_type: "session_overall",
          started_at: start_time,
          completed_at: start_time + (duration / 1000.0).seconds,
          duration: duration,
          emails_processed: rand(50..200),
          success: [ true, true, true, false ].sample, # 75% success rate
          error_type: rand > 0.75 ? [ "ConnectionError", "TimeoutError", "ParseError" ].sample : nil,
          metadata: {
            accounts_synced: email_accounts.size,
            day_of_week: start_time.strftime("%A")
          }
        )
      end

      # Create account-specific metrics
      email_accounts.each do |account|
        5.times do |i|
          start_time = date.beginning_of_day + rand(0..23).hours + rand(0..59).minutes
          duration = rand(5000..60000) # 5 seconds to 1 minute
          success = rand > 0.1 # 90% success rate

          # Account sync metric
          metrics_to_create << SyncMetric.new(
            sync_session: sync_session,
            email_account: account,
            metric_type: "account_sync",
            started_at: start_time,
            completed_at: start_time + (duration / 1000.0).seconds,
            duration: duration,
            emails_processed: rand(10..50),
            success: success,
            error_type: success ? nil : [ "ConnectionError", "AuthenticationError" ].sample,
            error_message: success ? nil : "Failed to connect to email server",
            metadata: { bank: account.bank_name }
          )

          # Email fetch metric
          metrics_to_create << SyncMetric.new(
            sync_session: sync_session,
            email_account: account,
            metric_type: "email_fetch",
            started_at: start_time + 1.second,
            completed_at: start_time + (duration / 2000.0).seconds,
            duration: duration / 2,
            emails_processed: rand(5..25),
            success: success,
            metadata: { bank: account.bank_name }
          )

          # Email parse metric
          metrics_to_create << SyncMetric.new(
            sync_session: sync_session,
            email_account: account,
            metric_type: "email_parse",
            started_at: start_time + 2.seconds,
            completed_at: start_time + (duration / 4000.0).seconds,
            duration: duration / 4,
            emails_processed: rand(5..25),
            success: [ true, true, true, true, false ].sample, # 80% success
            error_type: rand > 0.8 ? "ParseError" : nil,
            metadata: { bank: account.bank_name }
          )
        end
      end
    end

    # Bulk insert for performance
    SyncMetric.import!(metrics_to_create, validate: false)

    puts "Created #{metrics_to_create.size} test metrics"
    puts "You can now visit /sync_performance to see the dashboard"
  end

  desc "Clear all sync metrics"
  task clear: :environment do
    SyncMetric.destroy_all
    puts "All sync metrics cleared"
  end
end
