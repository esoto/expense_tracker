class AddJobIdToSyncSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sessions, :job_ids, :text, default: '[]'
    add_column :sync_session_accounts, :job_id, :string

    add_index :sync_session_accounts, :job_id
  end
end
