# frozen_string_literal: true

# Adds the `user_id` FK to `sync_conflicts` as a nullable column.  The backfill
# runs in the next migration; the NOT NULL flip runs in the one after that.
#
# The index is created with `algorithm: :concurrently` so production writes are
# not blocked during deploy.  That forces `disable_ddl_transaction!` — Postgres
# cannot create a concurrent index inside a transaction.  The foreign key itself
# (a metadata-only change) is cheap and stays in the default (transactional)
# path.
class AddUserToSyncConflicts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :sync_conflicts, :user, foreign_key: true, index: false, null: true
    add_index :sync_conflicts, :user_id, algorithm: :concurrently
  end
end
