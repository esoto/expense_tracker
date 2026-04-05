class RenameSidekiqJobIdToJobIdOnFailedBroadcastStores < ActiveRecord::Migration[8.1]
  def change
    rename_column :failed_broadcast_stores, :sidekiq_job_id, :job_id
  end
end
