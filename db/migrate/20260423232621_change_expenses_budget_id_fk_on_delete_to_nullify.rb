class ChangeExpensesBudgetIdFkOnDeleteToNullify < ActiveRecord::Migration[8.1]
  # Aligns the DB FK with the Rails-level `has_many :override_expenses,
  # dependent: :nullify` association on Budget. Without this, any destroy
  # path that bypasses Rails (raw SQL, cascade-bypass batch deletes) raises a
  # FK violation instead of nulling the expense's budget_id.
  def change
    remove_foreign_key :expenses, :budgets
    add_foreign_key :expenses, :budgets, on_delete: :nullify
  end
end
