class AddMetadataToSyncSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sessions, :metadata, :jsonb, default: {}
    add_index :sync_sessions, :metadata, using: :gin
  end
end
