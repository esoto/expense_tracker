# frozen_string_literal: true

# Holds the full email payload (bank notification body + any pre-parsed
# expense data) that ProcessEmailJob needs, encrypted at rest.
#
# Security fix (2026-08 audit): this table exists so ProcessEmailJob.perform_later
# only receives an id in its job arguments — never the raw bank-email body.
# Active Job serializes job arguments into solid_queue_jobs.arguments (and the
# ready/failed_executions tables) as plaintext text, which is readable by
# anyone with DB access on the shared personal-blog-db host. Encrypting the
# payload here — the same `encrypts` mechanism already used for
# expenses.email_body and email_parsing_failures.raw_email_content — closes
# that gap.
#
# `encrypted_payload` stores an ActiveJob::Arguments-serialized JSON blob
# (not a plain `hash.to_json`) so Symbol keys, Time/BigDecimal values, etc.
# round-trip exactly as ProcessEmailJob previously received them as raw job
# arguments. Use `payload_data` / `payload_data=` rather than touching the
# encrypted column directly.
class QueuedEmailPayload < ApplicationRecord
  encrypts :encrypted_payload

  belongs_to :email_account
  belongs_to :sync_session, optional: true

  # Retention: processed rows are transient scratch data, purge quickly.
  # Unprocessed rows are kept longer so retries/backlogged jobs still have
  # something to consume; a much longer window also gives an operator time to
  # notice a stuck queue before payload data disappears.
  PROCESSED_RETENTION = 7.days
  UNPROCESSED_RETENTION = 30.days

  scope :processed, -> { where.not(processed_at: nil) }
  scope :unprocessed, -> { where(processed_at: nil) }
  scope :expired_processed, -> { processed.where(processed_at: ..PROCESSED_RETENTION.ago) }
  scope :expired_unprocessed, -> { unprocessed.where(created_at: ..UNPROCESSED_RETENTION.ago) }

  # @param data [Hash] arbitrary job-argument-shaped data (e.g.
  #   { email_data: {...}, pre_parsed: {...} })
  def payload_data=(data)
    self.encrypted_payload = ActiveJob::Arguments.serialize([ data ]).to_json
  end

  # @return [Hash, nil] the original hash passed to `payload_data=`, with
  #   Symbol keys and Time/BigDecimal values restored.
  def payload_data
    return nil if encrypted_payload.blank?

    ActiveJob::Arguments.deserialize(JSON.parse(encrypted_payload)).first
  end

  def mark_processed!
    update!(processed_at: Time.current)
  end
end
