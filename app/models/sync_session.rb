class SyncSession < ApplicationRecord
  has_many :sync_session_accounts, dependent: :destroy
  has_many :email_accounts, through: :sync_session_accounts

  validates :status, presence: true, inclusion: { in: %w[pending running completed failed cancelled] }

  serialize :job_ids, coder: JSON, type: Array

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :finished, -> { where(status: %w[completed failed cancelled]) }

  # Add callbacks for better error tracking
  before_save :track_status_changes
  after_commit :log_status_change, if: :saved_change_to_status?

  def progress_percentage
    return 0 if total_emails.zero?
    (processed_emails.to_f / total_emails * 100).round
  end

  def estimated_time_remaining
    return nil unless running? && processed_emails > 0

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
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def fail!(error_message = nil)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_details: error_message
    )
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
    # Use pluck to get the sums without ordering issues
    sums = sync_session_accounts
      .pluck(
        "SUM(total_emails)",
        "SUM(processed_emails)",
        "SUM(detected_expenses)"
      )
      .first

    self.total_emails = sums[0] || 0
    self.processed_emails = sums[1] || 0
    self.detected_expenses = sums[2] || 0
    save!
  rescue ActiveRecord::StaleObjectError
    # Handle optimistic locking conflict
    reload
    retry
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

  def track_status_changes
    if status_changed? && status_was == "running" && finished?
      self.completed_at ||= Time.current
    end
  end

  def log_status_change
    Rails.logger.info "SyncSession #{id} status changed from #{status_before_last_save} to #{status}"

    if failed?
      Rails.logger.error "SyncSession #{id} failed: #{error_details}"
    end
  end
end
