class AddSoftDeleteToExpenses < ActiveRecord::Migration[8.0]
  def change
    # Check if columns already exist before adding
    unless column_exists?(:expenses, :deleted_at)
      add_column :expenses, :deleted_at, :datetime
      add_index :expenses, :deleted_at
    end
    
    unless column_exists?(:expenses, :deleted_by)
      add_column :expenses, :deleted_by, :string
    end
  end
end
