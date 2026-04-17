class EmailParsingFailure < ApplicationRecord
  RETENTION_DAYS = 30

  belongs_to :email_account

  # PER-496: raw_email_content holds bank PII (amounts, merchants, account
  # refs, recipient addresses, transaction times). Encrypt at rest.
  # support_unencrypted_data: true keeps existing plaintext rows readable
  # until the 30-day retention job purges them (EmailParsingFailureCleanupJob).
  # TODO(PER-534): Remove support_unencrypted_data once legacy plaintext rows
  # have aged out (30+ days after PR #428 reaches production).
  encrypts :raw_email_content, support_unencrypted_data: true

  # Retention-window scope used by EmailParsingFailureCleanupJob. Inclusive
  # endpoint so a row at exactly the cutoff is considered expired.
  scope :expired, -> { where(created_at: ..RETENTION_DAYS.days.ago) }

  validate :error_messages_not_nil

  private

  def error_messages_not_nil
    errors.add(:error_messages, "must be an array") unless error_messages.is_a?(Array)
  end
end
