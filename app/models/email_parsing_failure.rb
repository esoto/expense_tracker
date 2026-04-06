class EmailParsingFailure < ApplicationRecord
  belongs_to :email_account

  validate :error_messages_not_nil

  private

  def error_messages_not_nil
    errors.add(:error_messages, "must not be nil") if error_messages.nil?
  end
end
