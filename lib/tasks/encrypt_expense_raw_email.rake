# frozen_string_literal: true

# PER-533: Backfill rake task to encrypt Expense#raw_email_content rows that
# were written as plaintext before the encrypts declaration was deployed.
#
# Usage:
#   bin/rails encrypt:expense_raw_email
#
# This task is idempotent — re-running it safely skips already-encrypted rows.
# A row is considered already encrypted when its raw column value starts with
# the ActiveRecord::Encryption header prefix "{".
#
# It processes rows in batches of 1000 with a small sleep between batches to
# avoid saturating the database in production.
#
# TODO(PER-534): Once all rows are confirmed encrypted (30+ days after this
# rake task runs in production), remove support_unencrypted_data: true from
# Expense#raw_email_content and delete this task.

namespace :encrypt do
  desc "Backfill encryption for Expense#raw_email_content (PER-533)"
  task expense_raw_email: :environment do
    batch_size    = 1_000
    sleep_seconds = 0.1

    total     = 0
    encrypted = 0
    skipped   = 0
    errored   = 0

    start_time = Time.current
    Rails.logger.info "[PER-533] Starting Expense#raw_email_content encryption backfill"
    puts "[PER-533] Starting Expense#raw_email_content encryption backfill"

    # Query the raw column via SQL to identify truly plaintext rows.
    # An already-encrypted row's raw column value begins with the JSON header
    # that ActiveRecord::Encryption writes (e.g. {"p":"..."}). We check for
    # rows where the raw value does NOT start with "{" — those are plaintext.
    Expense.in_batches(of: batch_size) do |batch|
      batch.each do |expense|
        total += 1

        raw_value = ActiveRecord::Base.connection.execute(
          "SELECT raw_email_content FROM expenses WHERE id = #{expense.id}"
        ).first&.fetch("raw_email_content", nil)

        # Skip rows with no raw email content
        if raw_value.nil?
          skipped += 1
          next
        end

        # Skip rows that already have ciphertext (header starts with "{")
        if raw_value.start_with?("{")
          skipped += 1
          next
        end

        # Re-assign the attribute so AR Encryption marks it dirty and writes
        # the ciphertext on save. Without this, AR skips the column update
        # because the decrypted value matches what's already in memory.
        # We reload first to ensure AR reads the plaintext from the raw column
        # before we reassign, then force the attribute change via clear_attribute_change.
        expense.reload
        expense.raw_email_content = raw_value
        # Mark as changed even if the decoded value appears identical —
        # AR Encryption may otherwise skip the write because the String
        # objects compare equal.
        expense.send(:raw_email_content_will_change!)
        expense.save!
        encrypted += 1
      rescue StandardError => e
        errored += 1
        Rails.logger.error "[PER-533] Error encrypting Expense id=#{expense.id}: #{e.message}"
      end

      sleep(sleep_seconds) if sleep_seconds > 0
    end

    elapsed = (Time.current - start_time).round(1)
    summary = "[PER-533] Done. total=#{total} encrypted=#{encrypted} " \
              "skipped=#{skipped} errored=#{errored} elapsed=#{elapsed}s"
    Rails.logger.info summary
    puts summary
  end
end
