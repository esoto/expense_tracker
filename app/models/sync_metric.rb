class SyncMetric < ApplicationRecord
  belongs_to :sync_session
  belongs_to :email_account, optional: true # For session-level metrics

  # Metric types
  METRIC_TYPES = {
    session_overall: "session_overall",
    account_sync: "account_sync",
    email_fetch: "email_fetch",
    email_parse: "email_parse",
    expense_detection: "expense_detection",
    conflict_detection: "conflict_detection",
    database_write: "database_write",
    broadcast: "broadcast"
  }.freeze

  # Validations
  validates :metric_type, presence: true, inclusion: { in: METRIC_TYPES.values }
  validates :started_at, presence: true
  validates :duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :emails_processed, numericality: { greater_than_or_equal_to: 0 }

  # Calculate duration if completed_at is set
  before_save :calculate_duration

  # Scopes for filtering
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_type, ->(type) { where(metric_type: type) }
  scope :recent, -> { order(started_at: :desc) }
  scope :in_period, ->(start_date, end_date) {
    where(started_at: start_date..end_date)
  }
  scope :for_session, ->(session_id) { where(sync_session_id: session_id) }
  scope :for_account, ->(account_id) { where(email_account_id: account_id) }

  # Dashboard-specific scopes
  scope :last_24_hours, -> { where(started_at: 24.hours.ago..Time.current) }
  scope :last_7_days, -> { where(started_at: 7.days.ago..Time.current) }
  scope :last_30_days, -> { where(started_at: 30.days.ago..Time.current) }

  # Aggregation methods
  def self.average_duration_by_type(period = :last_24_hours)
    send(period)
      .group(:metric_type)
      .average(:duration)
      .transform_values { |v| v.to_f.round(3) }
  end

  def self.success_rate_by_type(period = :last_24_hours)
    metrics = send(period).group(:metric_type, :success).count

    result = {}
    METRIC_TYPES.values.each do |type|
      success_count = metrics[[ type, true ]] || 0
      failure_count = metrics[[ type, false ]] || 0
      total = success_count + failure_count

      result[type] = if total > 0
        ((success_count.to_f / total) * 100).round(2)
      else
        0.0
      end
    end

    result
  end

  def self.error_distribution(period = :last_24_hours)
    send(period)
      .failed
      .where.not(error_type: nil)
      .group(:error_type)
      .count
      .sort_by { |_, count| -count }
      .to_h
  end

  def self.hourly_performance(metric_type = nil, hours = 24)
    query = where(started_at: hours.hours.ago..Time.current)
    query = query.by_type(metric_type) if metric_type

    query
      .group_by_hour(:started_at, range: hours.hours.ago..Time.current)
      .group(:success)
      .count
  end

  def self.peak_hours(period = :last_7_days)
    send(period)
      .group_by_hour_of_day(:started_at, format: "%l %P")
      .count
      .sort_by { |_, count| -count }
      .first(5)
      .to_h
  end

  def self.account_performance_summary(period = :last_24_hours)
    # Use includes to preload email accounts and avoid N+1
    metrics_by_account = send(period)
      .includes(:email_account)
      .by_type("account_sync")
      .group_by(&:email_account_id)

    # Get all metrics for emails_processed calculation
    all_metrics = send(period)
      .group(:email_account_id)
      .sum(:emails_processed)

    # Get aggregated data in single queries
    sync_counts = send(period)
      .by_type("account_sync")
      .group(:email_account_id)
      .count

    avg_durations = send(period)
      .by_type("account_sync")
      .group(:email_account_id)
      .average(:duration)

    success_counts = send(period)
      .by_type("account_sync")
      .successful
      .group(:email_account_id)
      .count

    # Build results for active accounts
    EmailAccount.active.includes(:sync_metrics).map do |account|
      total_syncs = sync_counts[account.id] || 0
      success_count = success_counts[account.id] || 0
      success_rate = total_syncs > 0 ? ((success_count.to_f / total_syncs) * 100).round(2) : 0.0

      {
        account_id: account.id,
        bank_name: account.bank_name,
        email: account.email,
        total_syncs: total_syncs,
        average_duration: (avg_durations[account.id] || 0).to_f.round(3),
        success_rate: success_rate,
        emails_processed: all_metrics[account.id] || 0
      }
    end
  end

  # Instance methods
  def duration_in_seconds
    return nil unless duration
    (duration / 1000.0).round(3)
  end

  def processing_rate
    return nil if duration.nil? || duration.zero? || emails_processed.zero?
    (emails_processed / duration_in_seconds).round(2)
  end

  def status_badge
    success? ? "success" : "error"
  end

  private

  def calculate_duration
    if completed_at.present? && started_at.present? && duration.nil?
      self.duration = ((completed_at - started_at) * 1000).round(3) # Convert to milliseconds
    end
  end

  def self.calculate_success_rate(scope)
    total = scope.count
    return 0.0 if total.zero?

    success_count = scope.successful.count
    ((success_count.to_f / total) * 100).round(2)
  end
end

