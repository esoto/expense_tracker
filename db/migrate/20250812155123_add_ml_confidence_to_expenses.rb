class AddMlConfidenceToExpenses < ActiveRecord::Migration[8.0]
  def change
    add_column :expenses, :ml_confidence, :float
    add_column :expenses, :ml_confidence_explanation, :text
    add_column :expenses, :ml_suggested_category_id, :integer
    add_column :expenses, :ml_last_corrected_at, :datetime
    add_column :expenses, :ml_correction_count, :integer, default: 0

    # Add indexes for performance
    add_index :expenses, :ml_confidence
    add_index :expenses, [ :category_id, :ml_confidence ]
    add_index :expenses, :ml_suggested_category_id

    # Add foreign key for suggested category
    add_foreign_key :expenses, :categories, column: :ml_suggested_category_id
  end
end
