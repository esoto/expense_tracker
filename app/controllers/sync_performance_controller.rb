require "csv"

class SyncPerformanceController < ApplicationController
  before_action :set_date_range, only: [ :index, :export ]

  def index
    @metrics_summary = load_metrics_summary || default_metrics_summary
    @performance_data = load_performance_data || default_performance_data
    @account_metrics = load_account_metrics || []
    @error_analysis = load_error_analysis || default_error_analysis
    @peak_times = load_peak_times || default_peak_times

    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end

  def export
    metrics = SyncMetric.in_period(@start_date, @end_date).includes(:sync_session, :email_account)

    respond_to do |format|
      format.csv { send_data generate_csv(metrics), filename: csv_filename }
    end
  end

  def realtime
    # Endpoint for real-time updates via Turbo Streams
    @current_metrics = load_current_metrics

    respond_to do |format|
      format.turbo_stream
      format.json { render json: @current_metrics }
    end
  end

  private

  def set_date_range
    @period = params[:period] || "last_24_hours"

    case @period
    when "last_hour"
      @start_date = 1.hour.ago
      @end_date = Time.current
    when "last_24_hours"
      @start_date = 24.hours.ago
      @end_date = Time.current
    when "last_7_days"
      @start_date = 7.days.ago.beginning_of_day
      @end_date = Time.current
    when "last_30_days"
      @start_date = 30.days.ago.beginning_of_day
      @end_date = Time.current
    when "custom"
      @start_date = params[:start_date]&.to_datetime || 24.hours.ago
      @end_date = params[:end_date]&.to_datetime || Time.current
    else
      @start_date = 24.hours.ago
      @end_date = Time.current
    end
  end

  def load_metrics_summary
    metrics = SyncMetric.in_period(@start_date, @end_date)

    {
      total_syncs: metrics.by_type("account_sync").count,
      total_operations: metrics.count,
      success_rate: calculate_success_rate(metrics),
      average_duration: format_duration(metrics.average(:duration)),
      total_emails: metrics.sum(:emails_processed) || 0,
      processing_rate: calculate_processing_rate(metrics),
      active_sessions: SyncSession.active.count,
      last_sync: SyncSession.recent.first&.created_at
    }
  rescue => e
    Rails.logger.error "Error loading metrics summary: #{e.message}"
    default_metrics_summary
  end

  def load_performance_data
    # Data for charts - group by hour for last 24 hours, by day for longer periods
    grouping = @period == "last_24_hours" ? :hour : :day

    metrics = SyncMetric.in_period(@start_date, @end_date)

    if grouping == :hour
      grouped_data = metrics.group_by_hour(:started_at)
    else
      grouped_data = metrics.group_by_day(:started_at)
    end

    {
      timeline: grouped_data.group(:success).count,
      duration_trend: grouped_data.average(:duration),
      emails_trend: grouped_data.sum(:emails_processed),
      success_rate_trend: calculate_success_rate_trend(grouped_data)
    }
  rescue => e
    Rails.logger.error "Error loading performance data: #{e.message}"
    default_performance_data
  end

  def load_account_metrics
    EmailAccount.active.map do |account|
      metrics = SyncMetric
        .in_period(@start_date, @end_date)
        .for_account(account.id)
        .by_type("account_sync")

      {
        id: account.id,
        bank_name: account.bank_name,
        email: account.email,
        total_syncs: metrics.count,
        success_rate: calculate_success_rate(metrics),
        average_duration: format_duration(metrics.average(:duration)),
        emails_processed: metrics.sum(:emails_processed) || 0,
        last_sync: metrics.maximum(:started_at),
        errors: metrics.failed.count
      }
    end.sort_by { |a| -a[:total_syncs] }
  rescue => e
    Rails.logger.error "Error loading account metrics: #{e.message}"
    []
  end

  def load_error_analysis
    failed_metrics = SyncMetric.in_period(@start_date, @end_date).failed

    {
      total_errors: failed_metrics.count,
      error_rate: calculate_error_rate,
      error_types: failed_metrics.group(:error_type).count.sort_by { |_, v| -v },
      affected_accounts: failed_metrics
        .joins(:email_account)
        .group("email_accounts.bank_name")
        .count,
      error_timeline: error_timeline_data(failed_metrics),
      recent_errors: format_recent_errors(failed_metrics.recent.limit(10))
    }
  rescue => e
    Rails.logger.error "Error loading error analysis: #{e.message}"
    default_error_analysis
  end

  def load_peak_times
    metrics = SyncMetric.in_period(@start_date, @end_date)

    {
      hourly: metrics.group_by_hour_of_day(:started_at, format: "%l %P").count,
      daily: metrics.group_by_day_of_week(:started_at, format: "%A").count,
      peak_hours: identify_peak_hours(metrics),
      queue_depth: calculate_queue_depth_trend
    }
  rescue => e
    Rails.logger.error "Error loading peak times: #{e.message}"
    default_peak_times
  end

  def load_current_metrics
    # Real-time metrics for live updates
    last_5_minutes = SyncMetric.where(started_at: 5.minutes.ago..Time.current)

    {
      current_operations: last_5_minutes.count,
      success_rate: calculate_success_rate(last_5_minutes),
      average_duration: last_5_minutes.average(:duration).to_f.round(3),
      emails_per_second: calculate_current_processing_rate,
      active_jobs: SolidQueue::Job.where(finished_at: nil).count,
      queue_depth: SolidQueue::ReadyExecution.count
    }
  end

  def dashboard_json
    {
      summary: @metrics_summary,
      performance: @performance_data,
      accounts: @account_metrics,
      errors: @error_analysis,
      peak_times: @peak_times,
      generated_at: Time.current.iso8601
    }
  end

  def generate_csv(metrics)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Fecha/Hora",
        "Sesión ID",
        "Cuenta",
        "Tipo de Métrica",
        "Duración (ms)",
        "Correos Procesados",
        "Éxito",
        "Tipo de Error",
        "Mensaje de Error"
      ]

      metrics.find_each do |metric|
        csv << [
          metric.started_at.strftime("%Y-%m-%d %H:%M:%S"),
          metric.sync_session_id,
          metric.email_account&.email || "N/A",
          metric.metric_type,
          metric.duration&.round(2),
          metric.emails_processed,
          metric.success? ? "Sí" : "No",
          metric.error_type || "",
          metric.error_message || ""
        ]
      end
    end
  end

  def csv_filename
    "rendimiento_sincronizacion_#{@start_date.to_date}_#{@end_date.to_date}.csv"
  end

  def calculate_success_rate(metrics)
    total = metrics.count
    return 100.0 if total.zero?

    success = metrics.successful.count
    ((success.to_f / total) * 100).round(2)
  end

  def calculate_error_rate
    total = SyncMetric.in_period(@start_date, @end_date).count
    return 0.0 if total.zero?

    errors = SyncMetric.in_period(@start_date, @end_date).failed.count
    ((errors.to_f / total) * 100).round(2)
  end

  def calculate_processing_rate(metrics)
    total_duration = metrics.sum(:duration) / 1000.0 # Convert to seconds
    total_emails = metrics.sum(:emails_processed)

    return 0.0 if total_duration.zero?

    (total_emails / total_duration).round(2)
  end

  def calculate_current_processing_rate
    # Use Redis analytics if available
    if defined?(RedisAnalyticsService)
      data = RedisAnalyticsService.get_time_series("sync_metrics", window: 5.minutes)
      return data[:average].to_f.round(2) if data[:average] > 0
    end

    # Fallback to database
    recent = SyncMetric.where(started_at: 1.minute.ago..Time.current)
    calculate_processing_rate(recent)
  end

  def calculate_success_rate_trend(grouped_data)
    # Calculate success rate for each time period
    success_counts = grouped_data.successful.count
    total_counts = grouped_data.count

    trend = {}
    total_counts.each do |timestamp, total|
      success = success_counts[timestamp] || 0
      rate = total > 0 ? ((success.to_f / total) * 100).round(2) : 0
      trend[timestamp] = rate
    end

    trend
  end

  def error_timeline_data(failed_metrics)
    if @period == "last_24_hours"
      failed_metrics.group_by_hour(:started_at).count
    else
      failed_metrics.group_by_day(:started_at).count
    end
  end

  def format_recent_errors(errors)
    errors.map do |error|
      {
        time: error.started_at,
        account: error.email_account&.email || "Sistema",
        type: error.error_type,
        message: error.error_message&.truncate(100)
      }
    end
  end

  def identify_peak_hours(metrics)
    hourly_counts = metrics.group_by_hour_of_day(:started_at).count
    hourly_counts.sort_by { |_, count| -count }.first(5).map do |hour, count|
      { hour: format_hour(hour), count: count }
    end
  end

  def calculate_queue_depth_trend
    # Get queue depth over time from Solid Queue
    trend = []

    if @period == "last_24_hours"
      24.times do |i|
        time = i.hours.ago
        # This is a simplified example - you might want to store this data
        depth = SolidQueue::ReadyExecution.where(created_at: ..time).count
        trend << { time: time, depth: depth }
      end
    end

    trend.reverse
  end

  def format_duration(duration_ms)
    return "0 ms" if duration_ms.nil? || duration_ms.zero?

    duration = duration_ms.to_f

    if duration < 1000
      "#{duration.round(0)} ms"
    elsif duration < 60000
      "#{(duration / 1000).round(2)} s"
    else
      "#{(duration / 60000).round(2)} min"
    end
  end

  def format_hour(hour)
    Time.parse("2000-01-01 #{hour}:00").strftime("%l %P").strip
  end

  def default_metrics_summary
    {
      total_syncs: 0,
      total_operations: 0,
      success_rate: 0.0,
      average_duration: "0 ms",
      total_emails: 0,
      processing_rate: 0.0,
      active_sessions: 0,
      last_sync: nil
    }
  end

  def default_performance_data
    {
      timeline: {},
      duration_trend: {},
      emails_trend: {},
      success_rate_trend: {}
    }
  end

  def default_error_analysis
    {
      total_errors: 0,
      error_rate: 0.0,
      error_types: [],
      affected_accounts: {},
      error_timeline: {},
      recent_errors: []
    }
  end

  def default_peak_times
    {
      hourly: {},
      daily: {},
      peak_hours: [],
      queue_depth: []
    }
  end
end
