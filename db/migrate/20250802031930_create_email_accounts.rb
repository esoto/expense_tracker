class CreateEmailAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :email_accounts do |t|
      t.string :provider, null: false
      t.string :email, null: false
      t.text :encrypted_password
      t.text :encrypted_settings
      t.string :bank_name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :email_accounts, :email, unique: true
    add_index :email_accounts, :bank_name
    add_index :email_accounts, :active
  end
end
