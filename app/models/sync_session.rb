class SyncSession < ApplicationRecord
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable

  has_many :sync_session_accounts, dependent: :destroy
  has_many :email_accounts, through: :sync_session_accounts
  has_many :sync_conflicts, dependent: :destroy
  has_many :sync_metrics, dependent: :destroy

  validates :status, presence: true, inclusion: { in: %w[pending running completed failed cancelled] }

  serialize :job_ids, coder: JSON, type: Array

  before_create :generate_session_token

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :finished, -> { where(status: %w[completed failed cancelled]) }

  # Broadcast to dashboard for real-time updates
  after_update_commit :broadcast_dashboard_update

  # Add callbacks for better error tracking
  before_save :track_status_changes
  after_commit :log_status_change, if: :saved_change_to_status?

  def progress_percentage
    return 0 if total_emails.zero?
    (processed_emails.to_f / total_emails * 100).round
  end

  def estimated_time_remaining
    return nil unless running? && processed_emails > 0 && started_at.present?

    elapsed_time = Time.current - started_at
    processing_rate = processed_emails.to_f / elapsed_time
    remaining_emails = total_emails - processed_emails

    return nil if processing_rate.zero?

    (remaining_emails / processing_rate).seconds
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def pending?
    status == "pending"
  end

  def active?
    status.in?([ "pending", "running" ])
  end

  def finished?
    status.in?([ "completed", "failed", "cancelled" ])
  end

  def start!
    update!(status: "running", started_at: Time.current)
    SyncStatusChannel.broadcast_status(self) if should_broadcast?
  rescue StandardError => e
    Rails.logger.error "Error broadcasting start status: #{e.message}"
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
    SyncStatusChannel.broadcast_completion(self) if should_broadcast?
  rescue => e
    # Only catch broadcasting errors, not ActiveRecord errors
    unless e.is_a?(ActiveRecord::ActiveRecordError)
      Rails.logger.error "Error broadcasting completion: #{e.message}"
    else
      raise # Re-raise ActiveRecord errors
    end
  end

  def fail!(error_message = nil)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_details: error_message
    )
    SyncStatusChannel.broadcast_failure(self, error_message) if should_broadcast?
  rescue => e
    # Only catch broadcasting errors, not ActiveRecord errors
    unless e.is_a?(ActiveRecord::ActiveRecordError)
      Rails.logger.error "Error broadcasting failure: #{e.message}"
    else
      raise # Re-raise ActiveRecord errors
    end
  end

  def cancel!
    transaction do
      # Cancel all associated jobs
      cancel_all_jobs

      # Update status
      update!(status: "cancelled", completed_at: Time.current)

      # Mark all pending/processing accounts as cancelled
      sync_session_accounts.where(status: [ "pending", "waiting", "processing" ]).update_all(
        status: "failed",
        last_error: "Sync cancelled by user"
      )
    end
  end

  def add_job_id(job_id)
    return unless job_id.present?
    with_lock do
      new_ids = (reload.job_ids || []) + [ job_id.to_s ]
      update_column(:job_ids, new_ids)
      self.job_ids = new_ids
    end
  end

  # Collect multiple job IDs in one DB write — use this when dispatching
  # per-account jobs in a loop to avoid serial write-lock contention.
  # Wraps the read-modify-write in a row lock to prevent lost updates.
  def batch_add_job_ids(new_job_ids)
    ids_to_add = Array(new_job_ids).map(&:to_s).reject(&:blank?)
    return if ids_to_add.empty?
    with_lock do
      merged = (reload.job_ids || []) + ids_to_add
      update_column(:job_ids, merged)
      self.job_ids = merged
    end
  end

  def cancel_all_jobs
    return if job_ids.blank?

    job_ids.each do |job_id|
      begin
        job = SolidQueue::Job.find_by(id: job_id)
        job&.destroy if job&.scheduled? || job&.ready?
      rescue => e
        Rails.logger.error "Failed to cancel job #{job_id}: #{e.message}"
      end
    end

    # Also cancel account-specific jobs
    sync_session_accounts.where.not(job_id: nil).each do |account|
      begin
        job = SolidQueue::Job.find_by(id: account.job_id)
        job&.destroy if job&.scheduled? || job&.ready?
      rescue => e
        Rails.logger.error "Failed to cancel job #{account.job_id}: #{e.message}"
      end
    end
  end

  def update_progress
    Services::SyncProgressUpdater.new(self).call
  end

  def duration
    return nil unless started_at
    end_time = completed_at || Time.current
    end_time - started_at
  end

  def average_processing_time_per_email
    return nil if processed_emails.zero? || duration.nil?
    duration / processed_emails
  end

  # Process-global toggle used exclusively by the test suite (see spec/support/performance_optimizations.rb).
  # Not thread-safe: intended for sequential RSpec examples only. Do not call from application code.
  def self.broadcasting_enabled?
    @broadcasting_enabled || false
  end

  def self.enable_broadcasting!
    @broadcasting_enabled = true
  end

  def self.disable_broadcasting!
    @broadcasting_enabled = false
  end

  private

  def should_broadcast?
    !Rails.env.test? || self.class.broadcasting_enabled?
  end

  def generate_session_token
    self.session_token ||= SecureRandom.urlsafe_base64(32)
  end

  def track_status_changes
    if status_changed? && status_was == "running" && finished?
      self.completed_at ||= Time.current
    end
  end

  def log_status_change
    if failed?
      Rails.logger.error "SyncSession #{id} failed: #{error_details}"
    end
  end

  def broadcast_dashboard_update
    # Skip broadcasting unless specifically enabled
    return unless should_broadcast?

    # Broadcast to dashboard using Turbo Streams
    begin
      # Fetch active accounts once with latest expense preloaded to avoid N+1
      accounts_with_latest = active_accounts_with_latest_expense

      # Get dashboard data for the partial
      dashboard_data = {
        active_sync_session: active? ? self : nil,
        email_accounts: accounts_with_latest,
        last_sync_info: build_sync_info_for_dashboard(accounts_with_latest)
      }

      # Broadcast Turbo Stream update to the dashboard
      broadcast_replace_to(
        "dashboard_sync_updates",
        target: "sync_status_section",
        partial: "expenses/sync_status_section",
        locals: dashboard_data
      )
    rescue StandardError => e
      Rails.logger.error "Error broadcasting dashboard update: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def build_sync_info_for_dashboard(accounts = nil)
    # Accept pre-loaded accounts to avoid N+1; fall back to fetching if not provided
    accounts ||= active_accounts_with_latest_expense

    # Build sync info similar to Services::DashboardService
    sync_data = {}

    accounts.each do |account|
      # Use the preloaded latest_expense attribute when available; otherwise query.
      # has_attribute? works for both standard columns and SQL-aliased virtual attributes.
      last_expense_time = if account.has_attribute?(:latest_expense_created_at)
        account.latest_expense_created_at
      else
        account.expenses.order(created_at: :desc).first&.created_at
      end

      sync_data[account.id] = {
        last_sync: last_expense_time,
        account: account
      }
    end

    sync_data[:has_running_jobs] = active?
    sync_data[:running_job_count] = active? ? 1 : 0

    sync_data
  end

  def active_accounts_with_latest_expense
    # Single query: fetch active accounts with their latest expense created_at
    # using a LEFT JOIN on a subquery that finds the max created_at per account.
    # This eliminates the N+1 of querying each account's expenses individually.
    EmailAccount
      .active
      .select("email_accounts.*, latest_expenses.created_at AS latest_expense_created_at")
      .joins(
        "LEFT JOIN (
          SELECT email_account_id, MAX(created_at) AS created_at
          FROM expenses
          WHERE deleted_at IS NULL
          GROUP BY email_account_id
        ) AS latest_expenses ON latest_expenses.email_account_id = email_accounts.id"
      )
      .order(:bank_name, :email)
  end
end
