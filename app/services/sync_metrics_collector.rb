# frozen_string_literal: true

# SyncMetricsCollector collects and records performance metrics during sync operations.
# It integrates with existing sync services to track performance at various stages.
#
# Usage:
#   collector = SyncMetricsCollector.new(sync_session)
#
#   # Track an operation
#   collector.track_operation(:email_fetch, email_account) do
#     # Perform email fetching
#   end
#
#   # Record a metric manually
#   collector.record_metric(
#     metric_type: :email_parse,
#     email_account: account,
#     success: true,
#     duration: 123.45,
#     emails_processed: 10
#   )
class SyncMetricsCollector
  attr_reader :sync_session, :metrics_buffer

  def initialize(sync_session)
    @sync_session = sync_session
    @metrics_buffer = []
    @operation_timers = {}
  end

  # Track an operation with automatic timing and error handling
  # @param operation_type [Symbol] Type of operation
  # @param email_account [EmailAccount] Optional email account
  # @param metadata [Hash] Additional metadata
  # @yield Block containing the operation to track
  # @return [Object] Result of the block
  def track_operation(operation_type, email_account = nil, metadata = {}, &block)
    metric_type = map_operation_to_metric_type(operation_type)
    start_time = Time.current
    emails_processed = 0
    success = true
    error_info = {}

    begin
      result = yield

      # Extract emails processed if available
      emails_processed = extract_emails_processed(result)

      result
    rescue StandardError => e
      success = false
      error_info = {
        error_type: e.class.name,
        error_message: e.message.truncate(500)
      }

      raise # Re-raise the error
    ensure
      end_time = Time.current
      duration = ((end_time - start_time) * 1000).round(3) # Convert to milliseconds

      # Record the metric
      record_metric(
        metric_type: metric_type,
        email_account: email_account,
        success: success,
        duration: duration,
        emails_processed: emails_processed,
        started_at: start_time,
        completed_at: end_time,
        metadata: metadata.merge(error_info)
      )

      # Also update Redis analytics for real-time monitoring
      update_redis_analytics(metric_type, duration, success, email_account)
    end
  end

  # Start timing an operation
  # @param operation_id [String] Unique identifier for the operation
  # @param metric_type [String] Type of metric
  # @param email_account [EmailAccount] Optional email account
  def start_operation(operation_id, metric_type, email_account = nil)
    @operation_timers[operation_id] = {
      metric_type: metric_type,
      email_account: email_account,
      started_at: Time.current,
      metadata: {}
    }
  end

  # Complete a timed operation
  # @param operation_id [String] Operation identifier
  # @param success [Boolean] Whether operation succeeded
  # @param emails_processed [Integer] Number of emails processed
  # @param metadata [Hash] Additional metadata
  def complete_operation(operation_id, success: true, emails_processed: 0, metadata: {})
    timer = @operation_timers.delete(operation_id)
    return unless timer

    completed_at = Time.current
    duration = ((completed_at - timer[:started_at]) * 1000).round(3)

    record_metric(
      metric_type: timer[:metric_type],
      email_account: timer[:email_account],
      success: success,
      duration: duration,
      emails_processed: emails_processed,
      started_at: timer[:started_at],
      completed_at: completed_at,
      metadata: timer[:metadata].merge(metadata)
    )
  end

  # Record a metric
  # @param metric_type [String] Type of metric
  # @param email_account [EmailAccount] Optional email account
  # @param success [Boolean] Whether operation succeeded
  # @param duration [Float] Duration in milliseconds
  # @param emails_processed [Integer] Number of emails processed
  # @param started_at [Time] Start time
  # @param completed_at [Time] Completion time
  # @param metadata [Hash] Additional metadata
  def record_metric(
    metric_type:,
    email_account: nil,
    success: true,
    duration: nil,
    emails_processed: 0,
    started_at: nil,
    completed_at: nil,
    metadata: {}
  )
    started_at ||= Time.current

    metric = SyncMetric.new(
      sync_session: sync_session,
      email_account: email_account,
      metric_type: metric_type.to_s,
      success: success,
      duration: duration,
      emails_processed: emails_processed,
      started_at: started_at,
      completed_at: completed_at,
      metadata: metadata
    )

    # Extract error information from metadata if present
    if metadata[:error_type].present?
      metric.error_type = metadata[:error_type]
      metric.error_message = metadata[:error_message]
    end

    # Buffer metrics for batch saving (performance optimization)
    @metrics_buffer << metric

    # Save immediately if buffer is large enough or if it's a critical metric
    flush_buffer if @metrics_buffer.size >= 10 || metric_type.to_s == "session_overall"

    metric
  end

  # Record session-level metrics
  def record_session_metrics
    return unless sync_session

    session_start = sync_session.started_at || sync_session.created_at
    session_end = sync_session.completed_at || Time.current
    duration = ((session_end - session_start) * 1000).round(3)

    record_metric(
      metric_type: :session_overall,
      success: sync_session.completed?,
      duration: duration,
      emails_processed: sync_session.processed_emails,
      started_at: session_start,
      completed_at: session_end,
      metadata: {
        total_emails: sync_session.total_emails,
        detected_expenses: sync_session.detected_expenses,
        errors_count: sync_session.errors_count,
        status: sync_session.status
      }
    )
  end

  # Flush buffered metrics to database
  def flush_buffer
    return if @metrics_buffer.empty?

    begin
      SyncMetric.import!(@metrics_buffer, validate: false)
      @metrics_buffer.clear
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to save metrics: #{e.message}"
      # Try saving individually
      @metrics_buffer.each do |metric|
        metric.save rescue Rails.logger.error("Failed to save metric: #{metric.errors.full_messages}")
      end
      @metrics_buffer.clear
    end
  end

  # Get real-time metrics for dashboard
  def self.dashboard_metrics
    cache_key = "sync_metrics:dashboard:#{Time.current.to_i / 60}" # 1-minute cache

    Rails.cache.fetch(cache_key, expires_in: 1.minute) do
      {
        current_performance: current_performance_metrics,
        historical_data: historical_performance_data,
        account_metrics: account_performance_metrics,
        error_analysis: error_analysis_metrics,
        peak_times: peak_time_analysis
      }
    end
  end

  private

  def map_operation_to_metric_type(operation_type)
    mapping = {
      fetch_emails: :email_fetch,
      parse_email: :email_parse,
      detect_expense: :expense_detection,
      detect_conflicts: :conflict_detection,
      save_expense: :database_write,
      broadcast_update: :broadcast,
      sync_account: :account_sync
    }

    mapping[operation_type] || operation_type.to_s
  end

  def extract_emails_processed(result)
    return 0 unless result

    case result
    when Hash
      result[:emails_processed] || result[:count] || 0
    when Array
      result.size
    when Integer
      result
    else
      0
    end
  end

  def update_redis_analytics(metric_type, duration, success, email_account)
    return unless defined?(RedisAnalyticsService)

    tags = {
      metric_type: metric_type,
      success: success.to_s
    }

    tags[:bank] = email_account.bank_name if email_account

    # Record in Redis for real-time analytics
    RedisAnalyticsService.increment_counter(
      "sync_metrics",
      tags: tags
    )

    RedisAnalyticsService.record_timing(
      "sync_duration",
      duration / 1000.0, # Convert to seconds
      tags: tags
    )
  rescue StandardError => e
    Rails.logger.warn "Failed to update Redis analytics: #{e.message}"
  end

  # Class methods for dashboard data
  class << self
    def current_performance_metrics
      last_hour = SyncMetric.last_24_hours.limit(1000)

      {
        total_operations: last_hour.count,
        success_rate: calculate_success_rate(last_hour),
        average_duration: last_hour.average(:duration).to_f.round(3),
        emails_per_second: calculate_processing_rate(last_hour),
        active_sessions: SyncSession.active.count
      }
    end

    def historical_performance_data
      # Get hourly data for the last 30 days
      data = []

      30.times do |i|
        date = i.days.ago.beginning_of_day
        metrics = SyncMetric.where(started_at: date..date.end_of_day)

        data << {
          date: date.to_date.iso8601,
          success_rate: calculate_success_rate(metrics),
          average_duration: metrics.average(:duration).to_f.round(3),
          total_syncs: metrics.by_type("account_sync").count,
          emails_processed: metrics.sum(:emails_processed)
        }
      end

      data.reverse
    end

    def account_performance_metrics
      SyncMetric.account_performance_summary(:last_7_days)
    end

    def error_analysis_metrics
      {
        error_distribution: SyncMetric.error_distribution(:last_24_hours),
        failure_trends: failure_trend_data,
        most_affected_accounts: most_affected_accounts
      }
    end

    def peak_time_analysis
      {
        peak_hours: SyncMetric.peak_hours(:last_7_days),
        hourly_distribution: hourly_distribution,
        day_of_week: day_of_week_distribution
      }
    end

    private

    def calculate_success_rate(scope)
      total = scope.count
      return 100.0 if total.zero?

      success_count = scope.successful.count
      ((success_count.to_f / total) * 100).round(2)
    end

    def calculate_processing_rate(scope)
      total_duration = scope.sum(:duration) / 1000.0 # Convert to seconds
      total_emails = scope.sum(:emails_processed)

      return 0.0 if total_duration.zero?

      (total_emails / total_duration).round(2)
    end

    def failure_trend_data
      SyncMetric
        .failed
        .last_7_days
        .group_by_day(:started_at)
        .count
    end

    def most_affected_accounts
      SyncMetric
        .failed
        .last_24_hours
        .joins(:email_account)
        .group("email_accounts.bank_name", "email_accounts.email")
        .count
        .sort_by { |_, count| -count }
        .first(5)
        .map { |(bank, email), count| { bank: bank, email: email, failures: count } }
    end

    def hourly_distribution
      SyncMetric
        .last_7_days
        .group_by_hour_of_day(:started_at)
        .count
    end

    def day_of_week_distribution
      SyncMetric
        .last_30_days
        .group_by_day_of_week(:started_at, format: "%a")
        .count
    end
  end
end
