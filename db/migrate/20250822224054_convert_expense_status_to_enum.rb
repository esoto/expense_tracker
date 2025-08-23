class ConvertExpenseStatusToEnum < ActiveRecord::Migration[8.0]
  def up
    # Add new integer status column
    add_column :expenses, :status_enum, :integer, null: false, default: 0
    
    # Map existing string values to integers
    # pending: 0, processed: 1, failed: 2, duplicate: 3
    execute <<-SQL
      UPDATE expenses SET status_enum = 
        CASE 
          WHEN status = 'pending' THEN 0
          WHEN status = 'processed' THEN 1
          WHEN status = 'failed' THEN 2
          WHEN status = 'duplicate' THEN 3
          ELSE 0
        END;
    SQL
    
    # Remove old string status column
    remove_column :expenses, :status
    
    # Rename the new column to status
    rename_column :expenses, :status_enum, :status
    
    # Add index for better performance
    add_index :expenses, :status
  end
  
  def down
    # Add back string status column
    add_column :expenses, :status_string, :string, null: false, default: 'pending'
    
    # Map integer values back to strings
    execute <<-SQL
      UPDATE expenses SET status_string = 
        CASE 
          WHEN status = 0 THEN 'pending'
          WHEN status = 1 THEN 'processed'
          WHEN status = 2 THEN 'failed'
          WHEN status = 3 THEN 'duplicate'
          ELSE 'pending'
        END;
    SQL
    
    # Remove index
    remove_index :expenses, :status
    
    # Remove integer status column
    remove_column :expenses, :status
    
    # Rename string column back to status
    rename_column :expenses, :status_string, :status
  end
end
