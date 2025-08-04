class SyncSession < ApplicationRecord
  has_many :sync_session_accounts, dependent: :destroy
  has_many :email_accounts, through: :sync_session_accounts

  validates :status, presence: true, inclusion: { in: %w[pending running completed failed cancelled] }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  scope :completed, -> { where(status: "completed") }

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
    update!(status: "cancelled", completed_at: Time.current)
  end

  def update_progress
    self.total_emails = sync_session_accounts.sum(:total_emails)
    self.processed_emails = sync_session_accounts.sum(:processed_emails)
    self.detected_expenses = sync_session_accounts.sum(:detected_expenses)
    save!
  end
end

