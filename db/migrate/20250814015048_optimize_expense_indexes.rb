# frozen_string_literal: true

class OptimizeExpenseIndexes < ActiveRecord::Migration[8.0]
  def up
    # Step 1: Remove duplicate and overlapping indexes
    # These indexes are redundant or covered by composite indexes
    
    say_with_time "Removing duplicate and redundant indexes..." do
      # Remove duplicate indexes on api_tokens
      remove_index_if_exists :api_tokens, name: "idx_tokens_active_expires"
      remove_index_if_exists :api_tokens, name: "idx_tokens_last_used"
      
      # Remove redundant single-column indexes covered by composite indexes on expenses
      remove_index_if_exists :expenses, name: "index_expenses_on_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_category_id"
      remove_index_if_exists :expenses, name: "index_expenses_on_email_account_id"
      remove_index_if_exists :expenses, name: "index_expenses_on_merchant_name"
      remove_index_if_exists :expenses, name: "index_expenses_on_status"
      remove_index_if_exists :expenses, name: "index_expenses_on_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_currency"
      remove_index_if_exists :expenses, name: "index_expenses_on_merchant_normalized"
      
      # Remove overlapping composite indexes on expenses
      remove_index_if_exists :expenses, name: "idx_expenses_bank_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_bank_name_and_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_category_id_and_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_email_account_id_and_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_status_and_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_transaction_date_and_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_merchant_name_and_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_date_category_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_date_currency_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_date_merchant_amount"
      remove_index_if_exists :expenses, name: "index_expenses_on_date_status_amount"
      remove_index_if_exists :expenses, name: "idx_expenses_date_category"
      remove_index_if_exists :expenses, name: "idx_expenses_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_created_and_transaction_date"
      remove_index_if_exists :expenses, name: "index_expenses_on_email_account_id_and_created_at"
      remove_index_if_exists :expenses, name: "index_expenses_on_category_id_and_merchant_normalized"
      remove_index_if_exists :expenses, name: "index_expenses_on_merchant_date_amount"
      
      # Remove duplicate uncategorized indexes (keep only the most efficient one)
      remove_index_if_exists :expenses, name: "idx_uncategorized_expenses"
      remove_index_if_exists :expenses, name: "index_expenses_uncategorized"
      remove_index_if_exists :expenses, name: "idx_expenses_uncategorized_with_merchant"
      remove_index_if_exists :expenses, name: "index_expenses_uncategorized_with_merchant"
      remove_index_if_exists :expenses, name: "idx_expenses_account_uncategorized"
      
      # Remove redundant merchant indexes (keep only the trigram ones)
      remove_index_if_exists :expenses, name: "idx_expenses_merchant_trgm"
      remove_index_if_exists :expenses, name: "index_expenses_merchant_similarity"
      
      # Remove less efficient composite indexes
      remove_index_if_exists :expenses, name: "idx_expenses_account_date_category_amount"
      remove_index_if_exists :expenses, name: "idx_expenses_account_date_currency"
      remove_index_if_exists :expenses, name: "idx_expenses_account_date_merchant"
      remove_index_if_exists :expenses, name: "idx_expenses_account_date_status"
      
      # Remove redundant auto-categorization indexes
      remove_index_if_exists :expenses, name: "idx_on_auto_categorized_categorization_confidence_98abf3d147"
      
      # Remove redundant categorization indexes
      remove_index_if_exists :expenses, name: "index_expenses_on_categorization_method"
      remove_index_if_exists :expenses, name: "index_expenses_on_categorized_at"
      remove_index_if_exists :expenses, name: "index_expenses_on_categorized_by"
    end

    # Step 2: Create optimized composite indexes
    say_with_time "Creating optimized composite indexes..." do
      # Primary filtering index (most common queries)
      add_index :expenses, [:email_account_id, :transaction_date, :deleted_at],
                name: "idx_expenses_primary_filter",
                where: "deleted_at IS NULL",
                comment: "Primary index for common filtering operations"
      
      # Category analysis index
      add_index :expenses, [:category_id, :transaction_date, :amount],
                name: "idx_expenses_category_analysis",
                where: "deleted_at IS NULL",
                comment: "For category-based analytics and reporting"
      
      # Uncategorized expenses index (simplified)
      add_index :expenses, [:category_id, :merchant_normalized, :transaction_date],
                name: "idx_expenses_uncategorized",
                where: "category_id IS NULL AND deleted_at IS NULL",
                comment: "For finding uncategorized expenses"
      
      # Merchant search index (using trigram)
      unless index_exists?(:expenses, :merchant_normalized, name: "idx_expenses_merchant_search")
        add_index :expenses, :merchant_normalized,
                  name: "idx_expenses_merchant_search",
                  using: :gin,
                  opclass: :gin_trgm_ops,
                  where: "merchant_normalized IS NOT NULL AND deleted_at IS NULL",
                  comment: "Trigram index for merchant name fuzzy search"
      end
      
      # Status tracking index
      add_index :expenses, [:status, :created_at],
                name: "idx_expenses_status_tracking",
                where: "deleted_at IS NULL",
                comment: "For tracking pending/processed expenses"
      
      # Bank reconciliation index
      add_index :expenses, [:bank_name, :transaction_date, :amount],
                name: "idx_expenses_bank_reconciliation",
                where: "deleted_at IS NULL",
                comment: "For bank statement reconciliation"
      
      # Duplicate detection index
      unless index_exists?(:expenses, [:email_account_id, :amount, :transaction_date], 
                          name: "idx_expenses_duplicate_detection")
        add_index :expenses, [:email_account_id, :amount, :transaction_date, :merchant_name],
                  name: "idx_expenses_duplicate_detection",
                  comment: "For detecting potential duplicate transactions"
      end
      
      # Auto-categorization tracking (simplified)
      unless index_exists?(:expenses, [:auto_categorized, :categorization_confidence], 
                          name: "idx_expenses_auto_categorized")
        add_index :expenses, [:auto_categorized, :categorization_confidence],
                  name: "idx_expenses_auto_categorized",
                  where: "auto_categorized = true AND deleted_at IS NULL",
                  comment: "For tracking auto-categorization performance"
      end
      
      # Time-based analysis index
      add_index :expenses, "EXTRACT(year FROM transaction_date), EXTRACT(month FROM transaction_date)",
                name: "idx_expenses_year_month",
                where: "deleted_at IS NULL",
                comment: "For monthly/yearly aggregations"
      
      # Currency grouping index
      add_index :expenses, [:currency, :transaction_date],
                name: "idx_expenses_currency_date",
                where: "deleted_at IS NULL",
                comment: "For multi-currency reporting"
    end

    # Step 3: Add database configuration for performance
    say_with_time "Updating database performance settings..." do
      execute <<-SQL
        -- Set statement timeout for expense queries (5 seconds)
        ALTER DATABASE #{connection.current_database} SET statement_timeout = '5s';
        
        -- Optimize for read-heavy workload
        ALTER DATABASE #{connection.current_database} SET random_page_cost = 1.1;
        
        -- Increase work memory for complex queries
        ALTER DATABASE #{connection.current_database} SET work_mem = '16MB';
        
        -- Enable parallel queries for large datasets
        ALTER DATABASE #{connection.current_database} SET max_parallel_workers_per_gather = 2;
      SQL
    end

    # Step 4: Analyze tables to update statistics
    say_with_time "Analyzing tables to update statistics..." do
      execute "ANALYZE expenses;"
    end
  end

  def down
    # Remove new optimized indexes
    remove_index_if_exists :expenses, name: "idx_expenses_primary_filter"
    remove_index_if_exists :expenses, name: "idx_expenses_category_analysis"
    remove_index_if_exists :expenses, name: "idx_expenses_uncategorized"
    remove_index_if_exists :expenses, name: "idx_expenses_merchant_search"
    remove_index_if_exists :expenses, name: "idx_expenses_status_tracking"
    remove_index_if_exists :expenses, name: "idx_expenses_bank_reconciliation"
    remove_index_if_exists :expenses, name: "idx_expenses_duplicate_detection"
    remove_index_if_exists :expenses, name: "idx_expenses_auto_categorized"
    remove_index_if_exists :expenses, name: "idx_expenses_year_month"
    remove_index_if_exists :expenses, name: "idx_expenses_currency_date"
    
    # Reset database settings
    execute <<-SQL
      ALTER DATABASE #{connection.current_database} RESET statement_timeout;
      ALTER DATABASE #{connection.current_database} RESET random_page_cost;
      ALTER DATABASE #{connection.current_database} RESET work_mem;
      ALTER DATABASE #{connection.current_database} RESET max_parallel_workers_per_gather;
    SQL
    
    # Note: We don't recreate the removed indexes in the down migration
    # as they were redundant. If needed, they can be added back manually.
  end

  private

  def remove_index_if_exists(table, name:)
    remove_index table, name: name if index_exists?(table, nil, name: name)
  end
end
