class CreateSyncSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_sessions do |t|
      t.string :status, default: 'pending', null: false
      t.integer :total_emails, default: 0
      t.integer :processed_emails, default: 0
      t.integer :detected_expenses, default: 0
      t.integer :errors_count, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_details
      t.timestamps
    end

    create_table :sync_session_accounts do |t|
      t.references :sync_session, null: false, foreign_key: true
      t.references :email_account, null: false, foreign_key: true
      t.string :status, default: 'pending', null: false
      t.integer :total_emails, default: 0
      t.integer :processed_emails, default: 0
      t.integer :detected_expenses, default: 0
      t.text :last_error
      t.timestamps
    end

    add_index :sync_sessions, :status
    add_index :sync_sessions, :created_at
    add_index :sync_session_accounts, :status
  end
end
