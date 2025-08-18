# frozen_string_literal: true

# This migration adds the missing performance-critical indexes required for Task 3.1
# as identified in the tech-lead-architect review.
# These indexes are essential for dashboard performance and batch operations.
class AddMissingDashboardPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # Allow concurrent index creation for production safety

  def up
    say_with_time "Creating missing performance indexes for dashboard operations..." do
      # 1. Remove the existing non-INCLUDE covering index if it exists
      if index_exists?(:expenses, nil, name: "idx_expenses_list_covering")
        remove_index :expenses, name: "idx_expenses_list_covering"
      end

      # 2. Create proper PostgreSQL 11+ covering index with INCLUDE clause
      # This prevents additional table lookups for dashboard display
      execute <<-SQL
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_list_covering
        ON expenses(
          email_account_id,
          transaction_date DESC,
          amount,
          merchant_name,
          category_id,
          status
        )
        INCLUDE (description, bank_name, currency, auto_categorized, categorization_confidence, created_at, updated_at)
        WHERE deleted_at IS NULL;
      SQL

      # 3. Replace basic BRIN index with properly configured one for amount ranges
      if index_exists?(:expenses, nil, name: "idx_expenses_amount_range")
        remove_index :expenses, name: "idx_expenses_amount_range"
      end

      if index_exists?(:expenses, nil, name: "idx_expenses_amount_brin")
        remove_index :expenses, name: "idx_expenses_amount_brin"
      end

      # Create optimized BRIN index for amount range filtering
      # BRIN indexes are extremely space-efficient for range queries on large tables
      execute <<-SQL
        CREATE INDEX idx_expenses_amount_brin
        ON expenses USING brin(amount)
        WITH (pages_per_range = 128, autosummarize = on);
      SQL

      # 4. Add specialized index for batch operations (Task 3.4/3.5 support)
      # This index optimizes bulk selection and categorization operations
      unless index_exists?(:expenses, nil, name: "idx_expenses_batch_operations")
        add_index :expenses,
                  [ :email_account_id, :status, :category_id, :created_at ],
                  name: "idx_expenses_batch_operations",
                  algorithm: :concurrently,
                  where: "deleted_at IS NULL",
                  comment: "Optimized for batch selection and bulk operations"
      end

      # 5. Add composite index for complex dashboard filters
      unless index_exists?(:expenses, nil, name: "idx_expenses_dashboard_filters")
        add_index :expenses,
                  [ :email_account_id, :deleted_at, :transaction_date, :category_id, :status, :bank_name ],
                  name: "idx_expenses_dashboard_filters",
                  algorithm: :concurrently,
                  where: "deleted_at IS NULL",
                  comment: "Composite index for complex dashboard filter combinations"
      end

      # 6. Add specialized index for uncategorized expenses with performance hints
      if index_exists?(:expenses, nil, name: "idx_expenses_uncategorized")
        remove_index :expenses, name: "idx_expenses_uncategorized"
      end

      execute <<-SQL
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_uncategorized_optimized
        ON expenses(category_id, email_account_id, transaction_date DESC)
        WHERE category_id IS NULL AND deleted_at IS NULL;
      SQL

      # 7. Add partial index for pending expenses (status filtering)
      unless index_exists?(:expenses, nil, name: "idx_expenses_pending_status")
        execute <<-SQL
          CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_pending_status
          ON expenses(status, email_account_id, created_at DESC)
          WHERE status = 'pending' AND deleted_at IS NULL;
        SQL
      end

      # 8. Add time-based partitioning support index
      unless index_exists?(:expenses, nil, name: "idx_expenses_hour_dow")
        execute <<-SQL
          CREATE INDEX CONCURRENTLY idx_expenses_hour_dow
          ON expenses(
            EXTRACT(hour FROM transaction_date),
            EXTRACT(dow FROM transaction_date)
          )
          WHERE deleted_at IS NULL;
        SQL
      end
    end

    # Update table statistics for query planner
    say_with_time "Analyzing expenses table to update statistics..." do
      execute "ANALYZE expenses;"
    end

    # Verify index creation
    verify_indexes!
  end

  def down
    say_with_time "Removing dashboard performance indexes..." do
      # Remove new indexes
      remove_index_if_exists :expenses, name: "idx_expenses_list_covering"
      remove_index_if_exists :expenses, name: "idx_expenses_amount_brin"
      remove_index_if_exists :expenses, name: "idx_expenses_batch_operations"
      remove_index_if_exists :expenses, name: "idx_expenses_dashboard_filters"
      remove_index_if_exists :expenses, name: "idx_expenses_uncategorized_optimized"
      remove_index_if_exists :expenses, name: "idx_expenses_pending_status"
      remove_index_if_exists :expenses, name: "idx_expenses_hour_dow"

      # Restore simpler indexes if needed
      unless index_exists?(:expenses, [ :category_id, :transaction_date ])
        add_index :expenses,
                  [ :category_id, :transaction_date ],
                  name: "idx_expenses_uncategorized",
                  where: "category_id IS NULL AND deleted_at IS NULL"
      end

      unless index_exists?(:expenses, :amount, using: :brin)
        add_index :expenses, :amount,
                  name: "idx_expenses_amount_range",
                  using: :brin
      end
    end
  end

  private

  def remove_index_if_exists(table, name:)
    remove_index table, name: name if index_exists?(table, name: name)
  end

  def verify_indexes!
    required_indexes = [
      "idx_expenses_list_covering",
      "idx_expenses_amount_brin",
      "idx_expenses_batch_operations",
      "idx_expenses_dashboard_filters",
      "idx_expenses_uncategorized_optimized",
      "idx_expenses_pending_status"
    ]

    missing_indexes = required_indexes.reject { |name| index_exists?(:expenses, nil, name: name) }

    if missing_indexes.any?
      raise "Failed to create indexes: #{missing_indexes.join(', ')}"
    end

    say "All required indexes created successfully!"
  end
end
