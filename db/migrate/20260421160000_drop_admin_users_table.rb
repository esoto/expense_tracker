# frozen_string_literal: true

class DropAdminUsersTable < ActiveRecord::Migration[8.1]
  def up
    # Remove the legacy FK and column from sync_sessions before dropping the table.
    if table_exists?(:sync_sessions)
      if foreign_key_exists?(:sync_sessions, :admin_users)
        remove_foreign_key :sync_sessions, :admin_users
      end
      if column_exists?(:sync_sessions, :admin_user_id)
        remove_column :sync_sessions, :admin_user_id
      end
    end

    drop_table :admin_users if table_exists?(:admin_users)
  end

  def down
    # Intentionally irreversible — AdminUser records were migrated to User
    # in PR 3 (CreateDefaultUserFromAdminUsers). A `down` that recreates
    # the table would be missing both the schema nuances and the data.
    raise ActiveRecord::IrreversibleMigration, "admin_users was dropped in PR 14 after the full User migration."
  end
end
