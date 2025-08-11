class CreateSyncMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_metrics do |t|
      t.references :sync_session, null: false, foreign_key: true
      t.references :email_account, foreign_key: true # nullable for session-level metrics
      t.string :metric_type, null: false
      t.decimal :duration, precision: 10, scale: 3 # milliseconds precision
      t.integer :emails_processed, default: 0
      t.boolean :success, default: true
      t.string :error_type
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    # Performance indexes for time-based queries
    add_index :sync_metrics, :metric_type
    add_index :sync_metrics, [ :sync_session_id, :metric_type ]
    add_index :sync_metrics, [ :email_account_id, :metric_type ]
    add_index :sync_metrics, :started_at
    add_index :sync_metrics, :completed_at
    add_index :sync_metrics, [ :started_at, :completed_at ]
    add_index :sync_metrics, [ :metric_type, :started_at ]
    add_index :sync_metrics, [ :success, :metric_type ]
    add_index :sync_metrics, :error_type
    add_index :sync_metrics, :metadata, using: :gin

    # Composite index for dashboard queries
    add_index :sync_metrics, [ :metric_type, :success, :started_at ],
              name: "index_sync_metrics_dashboard"
  end
end
