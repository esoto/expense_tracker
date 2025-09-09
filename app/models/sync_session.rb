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
    return unless job_id
    self.job_ids ||= []
    self.job_ids << job_id.to_s
    save!
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
    SyncProgressUpdater.new(self).call
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

  private

  def should_broadcast?
    # Don't broadcast in non-test environments unless specifically enabled
    return true unless Rails.env.test?

    # In test environment, check if the current test wants broadcasting
    # This works by checking the current RSpec example metadata
    return false unless defined?(RSpec) && RSpec.current_example

    # Check if the test has needs_broadcasting: true metadata
    RSpec.current_example.metadata[:needs_broadcasting] == true
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
      # Get dashboard data for the partial
      dashboard_data = {
        active_sync_session: active? ? self : nil,
        email_accounts: EmailAccount.active.order(:bank_name, :email),
        last_sync_info: build_sync_info_for_dashboard
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

  def build_sync_info_for_dashboard
    # Build sync info similar to DashboardService
    sync_data = {}

    EmailAccount.active.each do |account|
      last_expense = account.expenses.order(created_at: :desc).first
      sync_data[account.id] = {
        last_sync: last_expense&.created_at,
        account: account
      }
    end

    sync_data[:has_running_jobs] = active?
    sync_data[:running_job_count] = active? ? 1 : 0

    sync_data
  end
end
