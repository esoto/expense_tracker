class AddSessionTokenToSyncSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sessions, :session_token, :string
    add_index :sync_sessions, :session_token, unique: true
  end
end
