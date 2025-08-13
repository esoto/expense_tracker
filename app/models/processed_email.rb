# frozen_string_literal: true

class ProcessedEmail < ApplicationRecord
  belongs_to :email_account

  validates :message_id, presence: true, uniqueness: { scope: :email_account_id }
  validates :email_account, presence: true

  scope :for_account, ->(account) { where(email_account: account) }
  scope :recent, -> { order(processed_at: :desc) }
  scope :by_date_range, ->(start_date, end_date) { where(processed_at: start_date..end_date) }

  def self.already_processed?(message_id, email_account)
    exists?(message_id: message_id, email_account: email_account)
  end
end
