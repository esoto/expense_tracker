class CreateExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :expenses do |t|
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description
      t.datetime :transaction_date, null: false
      t.string :merchant_name
      t.references :email_account, null: false, foreign_key: true
      t.references :category, null: true, foreign_key: true
      t.text :raw_email_content
      t.text :parsed_data
      t.string :status, default: 'pending', null: false

      t.timestamps
    end

    add_index :expenses, :transaction_date
    add_index :expenses, :amount
    add_index :expenses, :status
    add_index :expenses, [ :email_account_id, :transaction_date ]
  end
end
