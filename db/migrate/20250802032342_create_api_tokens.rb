class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, :active
    add_index :api_tokens, :expires_at
  end
end
