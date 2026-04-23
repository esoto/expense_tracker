class AddBudgetIdToExpenses < ActiveRecord::Migration[8.1]
  def change
    add_reference :expenses, :budget, null: true, foreign_key: true, index: true
  end
end
