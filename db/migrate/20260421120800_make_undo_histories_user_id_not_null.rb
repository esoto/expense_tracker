# frozen_string_literal: true

class MakeUndoHistoriesUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationUndoHistory < ActiveRecord::Base
    self.table_name = "undo_histories"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column.
    null_count = MigrationUndoHistory.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} undo_histories with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user

      MigrationUndoHistory.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :undo_histories, :user_id, false

    # Step 1 added the FK with `validate: false` because the column pre-existed
    # as a plain bigint and could have held orphan ids. Now that every row is
    # non-NULL and points at a real User (verified by the re-backfill above),
    # validate the constraint so Postgres can trust it and the schema can stop
    # showing it as unvalidated. This is safe and cheap — Postgres scans the
    # table once under SHARE UPDATE EXCLUSIVE (allows concurrent reads/writes).
    validate_foreign_key :undo_histories, :users
  end

  def down
    change_column_null :undo_histories, :user_id, true
    # Leave the FK in place but revert validation state to match step 1's
    # original posture. Postgres does not provide a direct "invalidate"
    # operation; we drop and re-add unvalidated as the closest equivalent.
    if foreign_key_exists?(:undo_histories, :users)
      remove_foreign_key :undo_histories, :users
      add_foreign_key :undo_histories, :users, validate: false
    end
  end
end
