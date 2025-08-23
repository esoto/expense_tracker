# frozen_string_literal: true

# Query Performance Monitoring for Dashboard Operations
# Tracks slow queries and provides metrics for optimization
# Part of Task 3.1: Database Optimization requirements

# Skip monitoring during migrations and tests
if (Rails.env.development? || Rails.env.production?) && !defined?(Rails::Command::DbCommand)
  # Track slow queries
  ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    # Skip schema and transaction queries
    next if event.payload[:sql] =~ /^(BEGIN|COMMIT|ROLLBACK|SELECT.*FROM.*schema_migrations)/i

    # Alert on queries over 50ms (Task 3.1 requirement)
    if event.duration > 50
      query_info = {
        duration: "#{event.duration.round(2)}ms",
        name: event.payload[:name],
        sql: event.payload[:sql],
        source: extract_source_location
      }

      Rails.logger.warn "[SLOW QUERY] #{query_info[:duration]}: #{query_info[:sql]}"

      # Send metrics if StatsD is configured
      if defined?(StatsD)
        StatsD.timing("expense.query.slow", event.duration)
        StatsD.increment("expense.query.slow.count")

        # Track by query type
        case event.payload[:sql]
        when /expenses.*category_id/i
          StatsD.timing("expense.query.category_filter", event.duration)
        when /expenses.*transaction_date/i
          StatsD.timing("expense.query.date_filter", event.duration)
        when /expenses.*merchant/i
          StatsD.timing("expense.query.merchant_search", event.duration)
        when /expenses.*amount/i
          StatsD.timing("expense.query.amount_range", event.duration)
        end
      end

      # In development, also log to a dedicated slow query log
      if Rails.env.development?
        slow_query_logger = Logger.new(Rails.root.join("log", "slow_queries.log"))
        slow_query_logger.info(query_info.to_json)
      end
    end

    # Track all expense queries for performance baseline
    if event.payload[:sql] =~ /FROM.*expenses/i && event.duration > 5
      if defined?(StatsD)
        StatsD.timing("expense.query.all", event.duration)
        StatsD.increment("expense.query.count")
      end
    end
  end

  # Index usage monitoring commented out to prevent recursion during migrations
  # This can be enabled manually for development debugging
  # To enable: uncomment the block below and restart the server

  # ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
  #   event = ActiveSupport::Notifications::Event.new(*args)
  #
  #   # Skip non-SELECT and EXPLAIN queries
  #   next unless event.payload[:sql] =~ /^SELECT/i
  #   next if event.payload[:sql] =~ /EXPLAIN/i
  #
  #   # Only check for expenses table queries
  #   if event.payload[:sql] =~ /FROM.*expenses/i && event.duration > 10
  #     Rails.logger.info "[INDEX CHECK] Query took #{event.duration.round(2)}ms: #{event.payload[:sql][0..100]}..."
  #   end
  # end

  # Helper method to extract source location
  def extract_source_location
    app_frames = caller.select { |frame| frame.include?(Rails.root.to_s) }
    app_frames.first&.gsub(Rails.root.to_s + "/", "") || "unknown"
  end
end

# Dashboard Performance Targets (Task 3.1 Requirements)
Rails.application.config.after_initialize do
  if defined?(Rails::Console)
    puts "Query Performance Monitoring Active"
    puts "Target: All dashboard queries < 50ms"
    puts "Slow queries logged to: log/slow_queries.log" if Rails.env.development?
  end
end
