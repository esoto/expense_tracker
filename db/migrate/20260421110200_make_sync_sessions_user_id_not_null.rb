# frozen_string_literal: true

class MakeSyncSessionsUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationSyncSession < ActiveRecord::Base
    self.table_name = "sync_sessions"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column. We inline
    # the same update_all logic here so any freshly-NULL rows get assigned
    # to the default admin user before the constraint is enforced.
    null_count = MigrationSyncSession.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} sync_sessions with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user
      MigrationSyncSession.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :sync_sessions, :user_id, false
  end

  def down
    change_column_null :sync_sessions, :user_id, true
  end
end
