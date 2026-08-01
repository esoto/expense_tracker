# frozen_string_literal: true

# Security fix (2026-08 audit): ProcessEmailJob previously received the full
# decoded bank-email body (transaction PII) as a plain job argument. Active
# Job serializes arguments into solid_queue_jobs.arguments (and the
# ready/failed_executions tables) as PLAINTEXT text — readable by anyone with
# DB access on the shared personal-blog-db host. The app already encrypts
# expenses.email_body and email_parsing_failures.raw_email_content; this table
# closes the queue-table gap by moving the payload out of job arguments and
# into an encrypted record, referenced by id.
class CreateQueuedEmailPayloads < ActiveRecord::Migration[8.1]
  def change
    create_table :queued_email_payloads do |t|
      t.references :email_account, null: false, foreign_key: true
      t.references :sync_session, null: true, foreign_key: true

      # Encrypted JSON blob holding the original email_data hash plus any
      # pre-parsed expense data (both may contain the full bank-email body).
      # Serialized via ActiveJob::Arguments so Symbol keys, Time/BigDecimal
      # values, etc. round-trip exactly as ProcessEmailJob previously
      # received them as raw job arguments.
      t.text :encrypted_payload, null: false

      # Set once ProcessEmailJob has consumed the record. Drives retention:
      # processed rows purge quickly, unprocessed ones stick around longer
      # so retries still have data to work with.
      t.datetime :processed_at

      t.timestamps
    end

    add_index :queued_email_payloads, :processed_at
  end
end
