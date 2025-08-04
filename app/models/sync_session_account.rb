class SyncSessionAccount < ApplicationRecord
  belongs_to :sync_session
  belongs_to :email_account

  validates :status, presence: true, inclusion: { in: %w[pending waiting processing completed failed] }

  scope :active, -> { where(status: %w[processing]) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

  def progress_percentage
    return 0 if total_emails.zero?
    (processed_emails.to_f / total_emails * 100).round
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end

  def waiting?
    status == "waiting"
  end

  def start_processing!
    update!(status: "processing")
  end

  def complete!
    update!(status: "completed")
    sync_session.update_progress
  end

  def fail!(error_message = nil)
    update!(status: "failed", last_error: error_message)
  end

  def update_progress(processed, total, detected = 0)
    self.processed_emails = processed
    self.total_emails = total
    self.detected_expenses += detected
    save!
    sync_session.update_progress
  end
end

