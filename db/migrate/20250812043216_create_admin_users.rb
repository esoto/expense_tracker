class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :email
      t.string :password_digest
      t.string :name
      t.integer :role
      t.datetime :last_login_at
      t.integer :failed_login_attempts
      t.datetime :locked_at
      t.string :session_token
      t.datetime :session_expires_at
      t.boolean :two_factor_enabled
      t.string :two_factor_secret

      t.timestamps
    end
    add_index :admin_users, :email, unique: true
    add_index :admin_users, :session_token, unique: true
  end
end
