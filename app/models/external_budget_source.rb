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

  # Record a transient sync failure — metadata only, source stays active so
  # the next scheduled sync will retry.
  def record_failure!(error:)
    update!(last_sync_status: "failed", last_sync_error: error.to_s.truncate(1000))
  end

  # Deactivate the source permanently — callers must choose this explicitly
  # (e.g., revoked credentials, unrecoverable errors). No auto-retry.
  def deactivate!(reason:)
    update!(active: false, last_sync_status: "failed", last_sync_error: reason.to_s.truncate(1000))
  end

  private

  def base_url_must_be_http
    uri = URI.parse(base_url.to_s)
    unless (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && uri.host.present?
      errors.add(:base_url, "must be an absolute http(s) URL")
    end
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end
end
