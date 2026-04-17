class EmailParsingFailure < ApplicationRecord
  belongs_to :email_account

  # PER-496: raw_email_content holds bank PII (amounts, merchants, account
  # refs, recipient addresses, transaction times). Encrypt at rest.
  # support_unencrypted_data: true keeps existing plaintext rows readable
  # until the 30-day retention job purges them (EmailParsingFailureCleanupJob).
  encrypts :raw_email_content, support_unencrypted_data: true

  validate :error_messages_not_nil

  private

  def error_messages_not_nil
    errors.add(:error_messages, "must be an array") unless error_messages.is_a?(Array)
  end
end
