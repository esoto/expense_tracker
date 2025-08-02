class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.text :description
      t.integer :parent_id
      t.string :color, limit: 7

      t.timestamps
    end

    add_index :categories, :name
    add_index :categories, :parent_id
    add_foreign_key :categories, :categories, column: :parent_id
  end
end
