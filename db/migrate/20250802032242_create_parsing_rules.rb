class CreateParsingRules < ActiveRecord::Migration[8.0]
  def change
    create_table :parsing_rules do |t|
      t.string :bank_name, null: false
      t.text :email_pattern
      t.string :amount_pattern, null: false
      t.string :date_pattern, null: false
      t.string :merchant_pattern
      t.string :description_pattern
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :parsing_rules, :bank_name
    add_index :parsing_rules, :active
  end
end
