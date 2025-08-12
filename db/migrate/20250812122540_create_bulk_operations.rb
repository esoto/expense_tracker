# frozen_string_literal: true

class CreateBulkOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :bulk_operations do |t|
      t.integer :operation_type, null: false, default: 0
      t.string :user_id
      t.references :target_category, foreign_key: { to_table: :categories }
      t.integer :expense_count, null: false, default: 0
      t.decimal :total_amount, precision: 15, scale: 2, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.datetime :undone_at
      t.jsonb :metadata, default: {}
      t.text :error_message

      t.timestamps

      t.index :operation_type
      t.index :status
      t.index :user_id
      t.index :created_at
      t.index [ :status, :created_at ]
      t.index [ :user_id, :created_at ]
      t.index :metadata, using: :gin
    end

    create_table :bulk_operation_items do |t|
      t.references :bulk_operation, null: false, foreign_key: true
      t.references :expense, null: false, foreign_key: true
      t.references :previous_category, foreign_key: { to_table: :categories }
      t.references :new_category, foreign_key: { to_table: :categories }
      t.integer :status, null: false, default: 0
      t.float :previous_confidence
      t.datetime :processed_at
      t.text :error_message

      t.timestamps

      t.index :status
      t.index [ :bulk_operation_id, :expense_id ], unique: true
      t.index [ :bulk_operation_id, :status ]
    end

    # Add columns to expenses if they don't exist
    unless column_exists?(:expenses, :categorization_method)
      add_column :expenses, :categorization_method, :string
    end

    unless column_exists?(:expenses, :categorized_at)
      add_column :expenses, :categorized_at, :datetime
    end

    unless column_exists?(:expenses, :categorized_by)
      add_column :expenses, :categorized_by, :string
    end

    unless column_exists?(:expenses, :auto_categorized)
      add_column :expenses, :auto_categorized, :boolean, default: false
    end

    unless column_exists?(:expenses, :categorization_confidence)
      add_column :expenses, :categorization_confidence, :float
    end

    # Add indexes to expenses table for bulk operations (after columns are created)
    add_index :expenses, :categorization_method unless index_exists?(:expenses, :categorization_method)
    add_index :expenses, :categorized_at unless index_exists?(:expenses, :categorized_at)
    add_index :expenses, :categorized_by unless index_exists?(:expenses, :categorized_by)
  end
end
