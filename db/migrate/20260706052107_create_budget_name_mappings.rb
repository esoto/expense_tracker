# frozen_string_literal: true

class CreateBudgetNameMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_name_mappings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :normalized_name, null: false
      t.references :category, null: true, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.integer :source, null: false
      t.decimal :confidence, precision: 4, scale: 3
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :budget_name_mappings, [ :user_id, :normalized_name ], unique: true
  end
end
