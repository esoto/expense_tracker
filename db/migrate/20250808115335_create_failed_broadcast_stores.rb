class CreateFailedBroadcastStores < ActiveRecord::Migration[8.0]
  def change
    create_table :failed_broadcast_stores do |t|
      t.string :channel_name, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.json :data, null: false
      t.string :priority, null: false, default: 'medium'
      t.string :error_type, null: false
      t.text :error_message, null: false
      t.datetime :failed_at, null: false
      t.integer :retry_count, null: false, default: 0
      t.string :sidekiq_job_id
      t.datetime :recovered_at
      t.text :recovery_notes

      t.timestamps

      # Indexes for efficient querying
      t.index [ :channel_name, :priority ], name: 'idx_failed_broadcasts_channel_priority'
      t.index [ :target_type, :target_id ], name: 'idx_failed_broadcasts_target'
      t.index [ :failed_at, :recovered_at ], name: 'idx_failed_broadcasts_status'
      t.index [ :error_type ], name: 'idx_failed_broadcasts_error_type'
      t.index [ :sidekiq_job_id ], name: 'idx_failed_broadcasts_job_id', unique: true
    end
  end
end
