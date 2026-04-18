# frozen_string_literal: true

class ExternalBudgetSource < ApplicationRecord
  SOURCE_TYPES = %w[salary_calculator].freeze

  encrypts :api_token

  belongs_to :email_account

  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :base_url, presence: true
  validate  :base_url_must_be_http
  validates :email_account_id, uniqueness: true

  scope :active, -> { where(active: true) }

  def mark_succeeded!
    update!(last_synced_at: Time.current, last_sync_status: "ok", last_sync_error: nil)
  end

  def mark_failed!(error:)
    update!(active: false, last_sync_status: "failed", last_sync_error: error.to_s.truncate(1000))
  end

  private

  def base_url_must_be_http
    uri = URI.parse(base_url.to_s)
    errors.add(:base_url, "must be http(s)") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end
end
