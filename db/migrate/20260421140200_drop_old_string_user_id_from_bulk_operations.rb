# frozen_string_literal: true

# Step 3 of 4: Promote `user_bigint_id` to become the canonical `user_id`.
#
# Operations (all within `up`):
#   1. Remove the composite index on the legacy string [user_id, created_at].
#   2. Drop the legacy string `user_id` column.
#   3. Rename `user_bigint_id` → `user_id`.
#   4. Add the new composite index [user_id, created_at] CONCURRENTLY.
#
# `disable_ddl_transaction!` is required for the CONCURRENTLY index creation
# in step 4.
#
# Reversibility: renaming back + re-inserting the string column from a bigint
# column without the original values is not feasible. `down` raises
# IrreversibleMigration (matching the PR 3 precedent).
class DropOldStringUserIdFromBulkOperations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # 1. Drop the old composite index on the string column.
    remove_index :bulk_operations,
                 name: "index_bulk_operations_on_user_id_and_created_at",
                 algorithm: :concurrently

    # 2. Drop the standalone bigint index created in step 1 (we'll replace it
    #    with the composite index in step 4).
    if index_exists?(:bulk_operations, :user_bigint_id,
                     name: "index_bulk_operations_on_user_bigint_id")
      remove_index :bulk_operations,
                   name: "index_bulk_operations_on_user_bigint_id",
                   algorithm: :concurrently
    end

    # 3 + 4. Drop the old string column and rename user_bigint_id → user_id.
    #        `disable_ddl_transaction!` is on (for the concurrent indexes), so
    #        remove_column and rename_column would otherwise commit separately
    #        — opening a brief window where bulk_operations has NO user_id
    #        column at all and live queries would error. Wrap them in an
    #        explicit transaction so the column swap is atomic from live
    #        traffic's perspective.
    ActiveRecord::Base.transaction do
      remove_column :bulk_operations, :user_id
      rename_column :bulk_operations, :user_bigint_id, :user_id
    end

    # 5. Add the new composite covering index CONCURRENTLY (outside the txn).
    add_index :bulk_operations, %i[user_id created_at],
              algorithm: :concurrently,
              name: "index_bulk_operations_on_user_id_and_created_at"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "DropOldStringUserIdFromBulkOperations cannot be reversed: the original " \
      "string user_id values were dropped and cannot be reconstructed."
  end
end
