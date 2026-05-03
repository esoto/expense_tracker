# frozen_string_literal: true

# PER-533: Backfill rake task to encrypt Expense#raw_email_content rows that
# were written as plaintext before the encrypts declaration was deployed.
#
# Usage:
#   bin/rails encrypt:expense_raw_email
#
# Idempotent — re-running it scans only plaintext rows (filtered at the SQL
# layer, no per-row probe) and is a no-op once everything is encrypted.
#
# Includes soft-deleted rows (Expense.unscoped). Soft-deleted expenses still
# carry the same bank PII; encryption parity covers them too.
#
# TODO(PER-534): Once all rows are confirmed encrypted (30+ days after this
# task runs in production), remove support_unencrypted_data: true from
# Expense#raw_email_content and delete this task.

namespace :encrypt do
  desc "Backfill encryption for Expense#raw_email_content (PER-533)"
  task expense_raw_email: :environment do
    batch_size    = 1_000
    sleep_seconds = 0.1

    total     = 0
    encrypted = 0
    errored   = 0

    start_time = Time.current
    Rails.logger.info "[PER-533] Starting Expense#raw_email_content encryption backfill"
    puts "[PER-533] Starting Expense#raw_email_content encryption backfill"

    # Pre-filter at the DB layer: only rows whose raw column value is
    # plaintext. AR::Encryption ciphertext serializes as a JSON envelope
    # starting with `{"p":` (the payload header). A NOT LIKE check on the
    # short prefix is sargable enough and lets re-runs short-circuit at the
    # WHERE clause instead of probing every row. unscoped covers
    # soft-deleted expenses whose default_scope would otherwise hide them.
    Expense.unscoped
           .where.not(raw_email_content: nil)
           .where("raw_email_content NOT LIKE ?", '{"p":%')
           .find_each(batch_size: batch_size) do |expense|
      total += 1

      # AR Encryption with support_unencrypted_data: true returns the
      # plaintext for legacy rows on read. Re-assign and save with
      # validate: false to:
      #   - go through the AR Encryption write path (correct ciphertext
      #     envelope produced by the attribute type)
      #   - skip validations (legacy rows may fail rules added later;
      #     we don't want them to orphan plaintext)
      #   - run callbacks (no-ops here: clear_dashboard_cache and
      #     trigger_metrics_refresh both gate on columns we aren't
      #     touching, and the before_save normalizers are idempotent)
      plaintext = expense.raw_email_content
      expense.raw_email_content = plaintext
      expense.send(:raw_email_content_will_change!)
      expense.save(validate: false)
      encrypted += 1

      if total % batch_size == 0
        progress = "[PER-533] processed=#{total} encrypted=#{encrypted} errored=#{errored}"
        Rails.logger.info progress
        puts progress
        sleep(sleep_seconds) if sleep_seconds > 0
      end
    rescue StandardError => e
      errored += 1
      # Log only the exception class — `e.message` may interpolate the
      # column value (PG::ValueTooLong, custom validation messages),
      # which would echo plaintext bank PII into production.log.
      Rails.logger.error "[PER-533] Error encrypting Expense id=#{expense&.id}: #{e.class}"
    end

    elapsed = (Time.current - start_time).round(1)
    summary = "[PER-533] Done. total=#{total} encrypted=#{encrypted} errored=#{errored} elapsed=#{elapsed}s"
    Rails.logger.info summary
    puts summary
  end
end
