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

    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
    add_index :users, :session_token, unique: true, where: "session_token IS NOT NULL"
    add_index :users, :session_expires_at
    add_index :users, :locked_at

    add_check_constraint :users, "role IN (0, 1)", name: "check_users_role_valid"
  end
end
