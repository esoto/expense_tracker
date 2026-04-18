class AddExternalSourceColumnsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :external_source, :string
    add_column :budgets, :external_id, :bigint
    add_column :budgets, :external_synced_at, :datetime
    add_index :budgets, [ :external_source, :external_id ],
              unique: true,
              where: "external_source IS NOT NULL",
              name: "idx_budgets_external_unique"
    add_index :budgets, :external_source, where: "external_source IS NOT NULL"
  end
end
