class CreateEmailParsingFailures < ActiveRecord::Migration[8.1]
  def change
    create_table :email_parsing_failures do |t|
      t.references :email_account, null: false, foreign_key: true
      t.string :bank_name
      t.jsonb :error_messages, default: []
      t.text :raw_email_content
      t.integer :original_email_size
      t.boolean :truncated, default: false

      t.timestamps
    end
  end
end
