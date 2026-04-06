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

  after_update :check_session_completion, if: -> { saved_change_to_status? && (completed? || failed?) }

  def update_progress(processed, total, detected = 0)
    retries = 0
    begin
      # Use update_columns to avoid callbacks and optimistic locking for progress updates
      update_columns(
        processed_emails: processed,
        total_emails: total,
        detected_expenses: detected_expenses + detected,
        updated_at: Time.current
      )

      # Update parent session progress
      sync_session.update_progress
    rescue ActiveRecord::StaleObjectError
      retries += 1
      if retries <= 3
        reload
        retry
      else
        Rails.logger.warn "[SyncSessionAccount] Max retries (3) for update_progress on account #{id}"
      end
    end
  end

  private

  def check_session_completion
    return unless sync_session.running?

    pending_siblings = sync_session.sync_session_accounts.where(status: %w[pending waiting processing])
    return if pending_siblings.exists?

    all_failed = sync_session.sync_session_accounts.where.not(status: "failed").none?

    if all_failed
      error_messages = sync_session.sync_session_accounts
        .where.not(last_error: nil)
        .pluck(:last_error)
        .join("; ")
      sync_session.fail!(error_messages.presence || "All accounts failed")
    else
      sync_session.complete!
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[SyncSessionAccount] Failed to auto-complete session #{sync_session.id}: #{e.message}"
  end
end
