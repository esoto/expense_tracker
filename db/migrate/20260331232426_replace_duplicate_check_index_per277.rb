# frozen_string_literal: true

# PER-277: Replace the non-unique idx_expenses_duplicate_check with a unique
# partial index to prevent duplicate active expenses at the database level.
#
# The unique constraint covers (email_account_id, amount, transaction_date,
# merchant_name) WHERE deleted_at IS NULL AND merchant_name IS NOT NULL AND
# email_account_id IS NOT NULL. This excludes soft-deleted records and manual
# entries (NULL merchant or email_account) from the constraint.
#
# Before creating the unique index, existing duplicates are marked with
# status = 3 (duplicate) to avoid constraint violations.
class ReplaceDuplicateCheckIndexPer277 < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Step 1: Soft-delete existing duplicates and mark as status = 3 (duplicate).
    # Keeps the earliest record (by created_at) and soft-deletes later copies
    # so they are excluded from the new unique partial index.
    execute <<~SQL
      WITH duplicates AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY email_account_id, amount, transaction_date, merchant_name
                 ORDER BY created_at ASC
               ) AS rn
        FROM expenses
        WHERE deleted_at IS NULL
          AND merchant_name IS NOT NULL
          AND email_account_id IS NOT NULL
      )
      UPDATE expenses
      SET status = 3, deleted_at = NOW(), updated_at = NOW()
      FROM duplicates
      WHERE expenses.id = duplicates.id
        AND duplicates.rn > 1
    SQL

    # Step 2: Drop old non-unique index concurrently
    if index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
      remove_index :expenses, name: "idx_expenses_duplicate_check", algorithm: :concurrently
    end

    # Step 3: Create new unique partial index concurrently
    unless index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
      add_index :expenses,
                %i[email_account_id amount transaction_date merchant_name],
                name: "idx_expenses_duplicate_check",
                unique: true,
                where: "deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NOT NULL",
                algorithm: :concurrently,
                comment: "Unique constraint for detecting duplicate active transactions"
    end
  end

  def down
    # NOTE: Data changes from Step 1 (soft-deleting duplicates via deleted_at
    # and status = 3) are NOT reversible by this migration. Previously
    # soft-deleted records will remain soft-deleted after rollback.

    # Drop the unique partial index
    if index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
      remove_index :expenses, name: "idx_expenses_duplicate_check", algorithm: :concurrently
    end

    # Restore the original non-unique index
    unless index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
      add_index :expenses,
                %i[email_account_id amount transaction_date merchant_name],
                name: "idx_expenses_duplicate_check",
                algorithm: :concurrently,
                comment: "Index for detecting duplicate transactions"
    end
  end
end
