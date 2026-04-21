# frozen_string_literal: true

# `undo_histories.user_id` already exists as a plain bigint column with a
# composite covering index [user_id, created_at].  This migration promotes it
# to a proper foreign key pointing at `users`.
#
# No new index is needed: PostgreSQL will use the existing composite index
# `index_undo_histories_on_user_id_and_created_at` to satisfy FK lookups.
# `disable_ddl_transaction!` is still declared for structural consistency with
# the other step-1 migrations in this PR.
class AddUserFkToUndoHistories < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_foreign_key :undo_histories, :users, validate: false
  end

  def down
    remove_foreign_key :undo_histories, :users
  end
end
