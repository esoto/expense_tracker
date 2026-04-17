# frozen_string_literal: true

# PER-498 (B8): close the manual-expense duplicate-check hole.
#
# The pre-existing `idx_expenses_duplicate_check` index has
#   WHERE deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NOT NULL
# — the last clause means manual expenses (email_account_id IS NULL, created
# via the web form or the iPhone Shortcuts webhook) bypass deduplication. A
# double-tap on the UI or a retried webhook would create two identical rows.
#
# This migration adds a companion partial unique index for the NULL case. The
# app is single-user (one admin account, no expense-owner scoping), so
# (amount, transaction_date, merchant_name) is a sufficient dedup key for
# manual entries.
#
# Concurrently added so it can run on prod without locking writes.
class AddManualExpenseDuplicateCheckIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Defensive: if the upgrade ever reruns, don't fail.
    return if index_exists?(:expenses, %i[amount transaction_date merchant_name],
                            name: :idx_expenses_manual_duplicate_check)

    add_index :expenses,
              %i[amount transaction_date merchant_name],
              name: :idx_expenses_manual_duplicate_check,
              unique: true,
              where: "deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NULL",
              algorithm: :concurrently,
              comment: "Unique constraint for detecting duplicate manual expenses (email_account_id IS NULL)"
  end

  def down
    remove_index :expenses,
                 name: :idx_expenses_manual_duplicate_check,
                 algorithm: :concurrently
  end
end
