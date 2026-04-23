class CreateBudgetCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_categories do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end

    add_index :budget_categories, [ :budget_id, :category_id ],
              unique: true,
              name: "index_budget_categories_on_budget_and_category"
  end
end
