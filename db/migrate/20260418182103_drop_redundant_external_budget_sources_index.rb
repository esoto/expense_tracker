class DropRedundantExternalBudgetSourcesIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :external_budget_sources, name: "idx_ebs_on_account_active"
  end
end
