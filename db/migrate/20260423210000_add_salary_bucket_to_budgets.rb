class AddSalaryBucketToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :salary_bucket, :integer, null: true
    add_index  :budgets, :salary_bucket
  end
end
