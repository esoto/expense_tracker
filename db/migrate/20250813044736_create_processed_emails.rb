class CreateProcessedEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_emails do |t|
      t.string :message_id, null: false
      t.references :email_account, null: false, foreign_key: true
      t.datetime :processed_at, null: false
      t.string :uid
      t.text :subject
      t.string :from_address

      t.timestamps
    end

    add_index :processed_emails, [ :message_id, :email_account_id ], unique: true, name: 'idx_processed_emails_unique'
    add_index :processed_emails, :processed_at
  end
end
