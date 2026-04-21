# frozen_string_literal: true

class MakeSyncConflictsUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationSyncConflict < ActiveRecord::Base
    self.table_name = "sync_conflicts"
  end

  class MigrationSyncSession < ActiveRecord::Base
    self.table_name = "sync_sessions"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column.
    null_count = MigrationSyncConflict.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} sync_conflicts with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user

      # Prefer inheriting from sync_session
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE sync_conflicts sc
        SET user_id = ss.user_id
        FROM sync_sessions ss
        WHERE sc.sync_session_id = ss.id
          AND sc.user_id IS NULL
          AND ss.user_id IS NOT NULL
      SQL

      MigrationSyncConflict.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :sync_conflicts, :user_id, false
  end

  def down
    change_column_null :sync_conflicts, :user_id, true
  end
end
