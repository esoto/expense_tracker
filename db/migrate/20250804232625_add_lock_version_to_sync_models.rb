class AddLockVersionToSyncModels < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sessions, :lock_version, :integer, default: 0, null: false
    add_column :sync_session_accounts, :lock_version, :integer, default: 0, null: false
  end
end
