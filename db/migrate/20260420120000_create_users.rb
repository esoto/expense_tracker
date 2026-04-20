# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.integer :role, null: false, default: 0
      t.string :name, null: false
      t.string :session_token
      t.datetime :session_expires_at
      t.datetime :last_login_at
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :session_token, unique: true, where: "session_token IS NOT NULL"
    add_index :users, :session_expires_at
    add_index :users, :locked_at
  end
end
