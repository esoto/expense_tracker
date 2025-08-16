class AddPerformanceIndexesToExpenses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Add missing columns for batch operations if they don't exist
    unless column_exists?(:expenses, :lock_version)
      add_column :expenses, :lock_version, :integer, default: 0, null: false
    end

    unless column_exists?(:expenses, :deleted_at)
      add_column :expenses, :deleted_at, :datetime
    end

    unless column_exists?(:expenses, :deleted_by_id)
      add_column :expenses, :deleted_by_id, :integer
    end

    # Primary composite index for filtering
    # This is the most critical index for common filter combinations
    unless index_exists?(:expenses, [ :email_account_id, :transaction_date, :category_id ], name: 'idx_expenses_filter_primary')
      add_index :expenses,
                [ :email_account_id, :transaction_date, :category_id ],
                name: 'idx_expenses_filter_primary',
                algorithm: :concurrently,
                where: "deleted_at IS NULL"
    end

    # Covering index for list display - includes commonly accessed columns
    # This prevents table lookups for the most common queries
    unless index_exists?(:expenses, [ :email_account_id, :transaction_date, :amount, :merchant_name, :category_id, :status ], name: 'idx_expenses_list_covering')
      add_index :expenses,
                [ :email_account_id, :transaction_date, :amount, :merchant_name, :category_id, :status ],
                name: 'idx_expenses_list_covering',
                algorithm: :concurrently,
                where: "deleted_at IS NULL"
    end

    # Category filtering index - optimized for category-based queries
    unless index_exists?(:expenses, [ :category_id, :transaction_date ], name: 'idx_expenses_category_date')
      add_index :expenses,
                [ :category_id, :transaction_date ],
                name: 'idx_expenses_category_date',
                algorithm: :concurrently,
                where: "category_id IS NOT NULL AND deleted_at IS NULL"
    end

    # Uncategorized expenses index - frequently used filter
    unless index_exists?(:expenses, [ :email_account_id, :transaction_date ], name: 'idx_expenses_uncategorized_new')
      add_index :expenses,
                [ :email_account_id, :transaction_date ],
                name: 'idx_expenses_uncategorized_new',
                algorithm: :concurrently,
                where: "category_id IS NULL AND deleted_at IS NULL"
    end

    # Bank filtering index - for bank-specific queries
    unless index_exists?(:expenses, [ :bank_name, :transaction_date ], name: 'idx_expenses_bank_date')
      add_index :expenses,
                [ :bank_name, :transaction_date ],
                name: 'idx_expenses_bank_date',
                algorithm: :concurrently,
                where: "deleted_at IS NULL"
    end

    # Status filtering index - for status-based queries
    unless index_exists?(:expenses, [ :status, :email_account_id, :created_at ], name: 'idx_expenses_status_account')
      add_index :expenses,
                [ :status, :email_account_id, :created_at ],
                name: 'idx_expenses_status_account',
                algorithm: :concurrently,
                where: "deleted_at IS NULL"
    end

    # Amount range index using BRIN for large tables
    # BRIN indexes are very efficient for range queries on sorted data
    unless index_exists?(:expenses, :amount, name: 'idx_expenses_amount_brin')
      execute <<-SQL
        CREATE INDEX CONCURRENTLY idx_expenses_amount_brin
        ON expenses USING brin(amount)
        WITH (pages_per_range = 128);
      SQL
    end

    # Ensure pg_trgm extension is enabled for fuzzy search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

    # Full-text search index on merchant_name if not exists
    unless index_exists?(:expenses, :merchant_name, name: 'idx_expenses_merchant_trgm_new')
      execute <<-SQL
        CREATE INDEX CONCURRENTLY idx_expenses_merchant_trgm_new
        ON expenses USING gin(merchant_name gin_trgm_ops)
        WHERE deleted_at IS NULL;
      SQL
    end

    # Add statistics for query optimizer
    execute "ANALYZE expenses;"
  end

  def down
    # Remove indexes in reverse order
    remove_index :expenses, name: 'idx_expenses_merchant_trgm_new' if index_exists?(:expenses, name: 'idx_expenses_merchant_trgm_new')

    execute "DROP INDEX IF EXISTS idx_expenses_amount_brin;"

    remove_index :expenses, name: 'idx_expenses_status_account' if index_exists?(:expenses, name: 'idx_expenses_status_account')
    remove_index :expenses, name: 'idx_expenses_bank_date' if index_exists?(:expenses, name: 'idx_expenses_bank_date')
    remove_index :expenses, name: 'idx_expenses_uncategorized_new' if index_exists?(:expenses, name: 'idx_expenses_uncategorized_new')
    remove_index :expenses, name: 'idx_expenses_category_date' if index_exists?(:expenses, name: 'idx_expenses_category_date')
    remove_index :expenses, name: 'idx_expenses_list_covering' if index_exists?(:expenses, name: 'idx_expenses_list_covering')
    remove_index :expenses, name: 'idx_expenses_filter_primary' if index_exists?(:expenses, name: 'idx_expenses_filter_primary')

    # Remove columns if they were added by this migration
    remove_column :expenses, :deleted_by_id if column_exists?(:expenses, :deleted_by_id)
    remove_column :expenses, :deleted_at if column_exists?(:expenses, :deleted_at)
    remove_column :expenses, :lock_version if column_exists?(:expenses, :lock_version)
  end
end
