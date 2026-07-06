# frozen_string_literal: true

class ProcessedEmail < ApplicationRecord
  belongs_to :user
  belongs_to :email_account

  validates :message_id, presence: true, uniqueness: { scope: :email_account_id }
  validates :email_account, presence: true

  before_validation :normalize_message_id_column

  scope :for_user, ->(u) { where(user_id: u.id) }
  scope :for_account, ->(account) { where(email_account: account) }
  scope :recent, -> { order(processed_at: :desc) }
  scope :by_date_range, ->(start_date, end_date) { where(processed_at: start_date..end_date) }

  # Canonical normalization for RFC822 Message-ID headers — the SINGLE place
  # where readers (already_processed?) and writers must agree. Strips
  # whitespace and the surrounding angle brackets ("<abc@host>" → "abc@host")
  # and downcases. Returns nil for blank/bracket-only input.
  def self.normalize_message_id(raw)
    return nil if raw.blank?

    raw.to_s.strip.gsub(/\A<+/, "").gsub(/>+\z/, "").strip.downcase.presence
  end

  # Blank/unparseable Message-IDs are never considered processed — the safe
  # direction is to re-process (one wasted parse) rather than risk silently
  # dropping a real expense.
  def self.already_processed?(message_id, email_account)
    normalized = normalize_message_id(message_id)
    return false if normalized.nil?

    exists?(message_id: normalized, email_account: email_account)
  end

  private

  def normalize_message_id_column
    self.message_id = self.class.normalize_message_id(message_id)
  end
end
