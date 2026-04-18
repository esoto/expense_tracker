class RescopeBudgetsExternalUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :budgets, name: "idx_budgets_external_unique"
    add_index :budgets, [ :email_account_id, :external_source, :external_id, :start_date ],
              unique: true,
              where: "external_source IS NOT NULL",
              name: "idx_budgets_external_unique"
  end
end
