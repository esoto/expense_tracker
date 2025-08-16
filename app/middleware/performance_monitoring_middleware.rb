# frozen_string_literal: true

# PerformanceMonitoringMiddleware tracks request performance metrics
# Monitors database queries, response times, and memory usage
class PerformanceMonitoringMiddleware
  # Performance thresholds
  SLOW_REQUEST_THRESHOLD = 100 # milliseconds
  SLOW_QUERY_THRESHOLD = 50 # milliseconds
  HIGH_QUERY_COUNT_THRESHOLD = 10
  HIGH_MEMORY_THRESHOLD = 50 # MB

  # Request types to monitor
  MONITORED_PATHS = %r{^/api/|^/expenses|^/sync|^/categorization}

  def initialize(app)
    @app = app
    @logger = Rails.logger.tagged("Performance")
  end

  def call(env)
    return @app.call(env) unless should_monitor?(env)

    # Start monitoring
    request_id = env["action_dispatch.request_id"] || SecureRandom.uuid
    metrics = {
      request_id: request_id,
      path: env["PATH_INFO"],
      method: env["REQUEST_METHOD"],
      start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      start_memory: current_memory_usage,
      queries: []
    }

    # Subscribe to SQL queries
    sql_subscriber = subscribe_to_sql_queries(metrics)

    begin
      # Process request
      status, headers, response = @app.call(env)

      # Calculate metrics
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration = ((end_time - metrics[:start_time]) * 1000).round(2)
      memory_delta = current_memory_usage - metrics[:start_memory]

      # Build performance report
      report = build_performance_report(
        metrics: metrics,
        status: status,
        duration: duration,
        memory_delta: memory_delta
      )

      # Log and track metrics
      log_performance(report)
      track_metrics(report)

      # Add performance headers in development/staging
      if Rails.env.development? || Rails.env.staging?
        headers["X-Runtime-Total"] = duration.to_s
        headers["X-DB-Query-Count"] = metrics[:queries].size.to_s
        headers["X-DB-Runtime"] = calculate_total_query_time(metrics[:queries]).to_s
        headers["X-Memory-Delta"] = "#{memory_delta}MB"
      end

      [ status, headers, response ]
    ensure
      # Clean up subscriptions
      ActiveSupport::Notifications.unsubscribe(sql_subscriber) if sql_subscriber
    end
  rescue StandardError => e
    @logger.error "Middleware error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    @app.call(env)
  end

  private

  def should_monitor?(env)
    return false if env["PATH_INFO"] =~ %r{^/assets/|^/packs/}
    return true if env["PATH_INFO"] =~ MONITORED_PATHS
    return true if env["REQUEST_METHOD"] != "GET"
    false
  end

  def subscribe_to_sql_queries(metrics)
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, start, finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:sql] =~ /^PRAGMA/

      duration = ((finish - start) * 1000).round(2)
      metrics[:queries] << {
        sql: sanitize_sql(payload[:sql]),
        duration: duration,
        name: payload[:name],
        cached: payload[:cached] || false
      }
    end
  end

  def build_performance_report(metrics:, status:, duration:, memory_delta:)
    query_time = calculate_total_query_time(metrics[:queries])
    slow_queries = metrics[:queries].select { |q| q[:duration] > SLOW_QUERY_THRESHOLD }

    {
      request_id: metrics[:request_id],
      path: metrics[:path],
      method: metrics[:method],
      status: status,
      duration_ms: duration,
      db_runtime_ms: query_time,
      view_runtime_ms: duration - query_time,
      query_count: metrics[:queries].size,
      cached_query_count: metrics[:queries].count { |q| q[:cached] },
      slow_query_count: slow_queries.size,
      memory_delta_mb: memory_delta,
      timestamp: Time.current.iso8601,
      slow: duration > SLOW_REQUEST_THRESHOLD,
      high_query_count: metrics[:queries].size > HIGH_QUERY_COUNT_THRESHOLD,
      high_memory: memory_delta > HIGH_MEMORY_THRESHOLD,
      slow_queries: slow_queries.map { |q|
        {
          sql: q[:sql],
          duration_ms: q[:duration]
        }
      }
    }
  end

  def log_performance(report)
    # Always log slow requests
    if report[:slow] || report[:high_query_count] || report[:high_memory]
      @logger.warn format_performance_warning(report)
    elsif Rails.env.development?
      @logger.info format_performance_info(report)
    end

    # Log to separate performance log file if configured
    if defined?(Rails.application.config.performance_logger)
      Rails.application.config.performance_logger.info(report.to_json)
    end
  end

  def track_metrics(report)
    # Send to StatsD if available
    if defined?(StatsD)
      StatsD.timing("rails.request.total", report[:duration_ms])
      StatsD.timing("rails.request.db", report[:db_runtime_ms])
      StatsD.timing("rails.request.view", report[:view_runtime_ms])
      StatsD.gauge("rails.request.queries", report[:query_count])
      StatsD.increment("rails.request.slow") if report[:slow]
      StatsD.increment("rails.request.high_queries") if report[:high_query_count]
    end

    # Send to APM if configured
    if defined?(Appsignal)
      Appsignal.add_distribution_value(
        "request_duration",
        report[:duration_ms],
        path: report[:path],
        method: report[:method]
      )
    end

    # Store in Redis for real-time dashboards if available
    if defined?(Redis) && Rails.application.config.respond_to?(:redis_metrics)
      store_in_redis(report)
    end
  end

  def format_performance_warning(report)
    warning = [ "SLOW REQUEST DETECTED" ]
    warning << "Path: #{report[:method]} #{report[:path]}"
    warning << "Duration: #{report[:duration_ms]}ms"
    warning << "DB: #{report[:db_runtime_ms]}ms (#{report[:query_count]} queries)"
    warning << "Memory: +#{report[:memory_delta_mb]}MB"

    if report[:slow_queries].any?
      warning << "Slow Queries:"
      report[:slow_queries].first(3).each do |query|
        warning << "  - #{query[:duration_ms]}ms: #{query[:sql][0..100]}"
      end
    end

    warning.join("\n")
  end

  def format_performance_info(report)
    [
      report[:method],
      report[:path],
      "#{report[:status]} in #{report[:duration_ms]}ms",
      "(DB: #{report[:db_runtime_ms]}ms/#{report[:query_count]}q",
      "Memory: #{report[:memory_delta_mb] >= 0 ? '+' : ''}#{report[:memory_delta_mb]}MB)"
    ].join(" ")
  end

  def calculate_total_query_time(queries)
    queries.reject { |q| q[:cached] }.sum { |q| q[:duration] }.round(2)
  end

  def current_memory_usage
    # Get current process memory usage in MB
    if defined?(GetProcessMem)
      GetProcessMem.new.mb.round(2)
    else
      # Fallback to RSS from /proc if available
      pid = Process.pid
      if File.exist?("/proc/#{pid}/status")
        File.read("/proc/#{pid}/status").match(/VmRSS:\s+(\d+)/)[1].to_i / 1024.0
      else
        0
      end
    end
  rescue StandardError
    0
  end

  def sanitize_sql(sql)
    # Remove sensitive data from SQL for logging
    sql.gsub(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/, "[TIMESTAMP]")
       .gsub(/('[^']*')/, "[STRING]")
       .gsub(/(\d+\.\d+)/, "[NUMBER]")
       .gsub(/(\d{10,})/, "[ID]")
       .truncate(500)
  end

  def store_in_redis(report)
    return unless Rails.application.config.redis_metrics

    redis = Rails.application.config.redis_metrics
    key = "performance:#{Date.current}:#{report[:path]}"

    # Store aggregated metrics
    redis.multi do |r|
      r.hincrby(key, "requests", 1)
      r.hincrbyfloat(key, "total_duration", report[:duration_ms])
      r.hincrbyfloat(key, "total_db_time", report[:db_runtime_ms])
      r.hincrby(key, "total_queries", report[:query_count])
      r.hincrby(key, "slow_requests", 1) if report[:slow]
      r.expire(key, 7.days.to_i)
    end

    # Store recent slow requests
    if report[:slow]
      slow_key = "performance:slow:#{Date.current}"
      redis.zadd(slow_key, report[:duration_ms], report.to_json)
      redis.expire(slow_key, 1.day.to_i)
      redis.zremrangebyrank(slow_key, 0, -101) # Keep only top 100
    end
  rescue StandardError => e
    @logger.error "Failed to store metrics in Redis: #{e.message}"
  end
end
