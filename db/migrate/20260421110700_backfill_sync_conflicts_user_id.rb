# frozen_string_literal: true

class BackfillSyncConflictsUserId < ActiveRecord::Migration[8.1]
  # Local anonymous models isolate this migration from future class changes.
  class MigrationSyncConflict < ActiveRecord::Base
    self.table_name = "sync_conflicts"
  end

  class MigrationSyncSession < ActiveRecord::Base
    self.table_name = "sync_sessions"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    default_user = MigrationUser.where(role: 1).order(:id).first

    if default_user.nil?
      raise ActiveRecord::MigrationError,
        "No admin User found — run PR 3 migration (CreateDefaultUserFromAdminUsers) first."
    end

    # Prefer inheriting user_id from the associated sync_session where available.
    # Fall back to the default admin user for any orphaned or already-null rows.
    ActiveRecord::Base.transaction do
      # Rows whose sync_session has a user_id — inherit from session
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE sync_conflicts sc
        SET user_id = ss.user_id
        FROM sync_sessions ss
        WHERE sc.sync_session_id = ss.id
          AND sc.user_id IS NULL
          AND ss.user_id IS NOT NULL
      SQL

      # Remaining NULL rows — assign to first admin user
      MigrationSyncConflict.where(user_id: nil).update_all(user_id: default_user.id)
    end
  end

  # Data migration — cannot safely determine which rows had a NULL user_id
  # before the backfill ran, so reversal would silently destroy ownership data.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillSyncConflictsUserId is a one-way data migration. " \
      "Rows cannot be safely reverted to NULL without knowing prior state."
  end
end
