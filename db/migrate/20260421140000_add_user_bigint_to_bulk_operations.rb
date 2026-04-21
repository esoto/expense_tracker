# frozen_string_literal: true

# Step 1 of 4: Add a new nullable `user_bigint_id` FK column pointing at `users`.
#
# Strategy:
#   - Keep the existing `user_id` string column untouched.
#   - Add `user_bigint_id` as a proper FK to `users` (nullable for now).
#   - Create the index CONCURRENTLY to avoid table locks in production.
#   - The backfill migration (step 2) will populate this column.
#
# `disable_ddl_transaction!` is required for CONCURRENTLY index creation.
class AddUserBigintToBulkOperations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :bulk_operations, :user_bigint,
                  foreign_key: { to_table: :users },
                  index: false,
                  null: true

    add_index :bulk_operations, :user_bigint_id,
              algorithm: :concurrently,
              name: "index_bulk_operations_on_user_bigint_id"
  end
end
