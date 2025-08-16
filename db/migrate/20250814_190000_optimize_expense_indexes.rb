# frozen_string_literal: true

# This migration optimizes the expense table indexes to reduce over-proliferation
# Target: Maximum of 15 indexes (down from 23+)
class OptimizeExpenseIndexes < ActiveRecord::Migration[8.0]
  def up
    # Remove duplicate and redundant indexes
    # Keep only the most efficient ones that cover multiple query patterns

    say_with_time "Analyzing and removing redundant expense indexes..." do
      # Remove indexes that are covered by composite indexes
      remove_index_if_exists :expenses, :amount, name: "idx_expenses_amount_brin"

      # Remove duplicate merchant indexes (keep only the most efficient trigram one)
      remove_index_if_exists :expenses, :merchant_normalized, name: "index_expenses_on_merchant_normalized_trgm"
      remove_index_if_exists :expenses, [ :merchant_normalized ], name: "idx_expenses_merchant_trgm_new"

      # Remove redundant category indexes (covered by composite indexes)
      remove_index_if_exists :expenses, [ :category_id, :created_at, :merchant_normalized ],
                             name: "idx_expenses_uncategorized_optimized"
      remove_index_if_exists :expenses, [ :category_id, :merchant_normalized, :transaction_date ],
                             name: "idx_expenses_uncategorized"

      # Remove overlapping account/status indexes
      remove_index_if_exists :expenses, [ :email_account_id, :status, :transaction_date, :amount ],
                             name: "idx_expenses_account_status_date_amount"
      remove_index_if_exists :expenses, [ :email_account_id, :amount, :transaction_date ],
                             name: "index_expenses_on_account_amount_date_for_duplicates"

      # Remove redundant filter indexes (covered by primary filter index)
      remove_index_if_exists :expenses, [ :email_account_id, :transaction_date, :category_id ],
                             name: "idx_expenses_filter_primary"
      remove_index_if_exists :expenses, [ :email_account_id, :transaction_date ],
                             name: "idx_expenses_uncategorized_new"

      # Remove redundant auto-categorized indexes
      remove_index_if_exists :expenses, [ :auto_categorized, :categorization_confidence, :created_at ],
                             name: "idx_auto_categorized_tracking"

      # Remove redundant status tracking index (covered by status_account index)
      remove_index_if_exists :expenses, [ :status, :created_at ],
                             name: "idx_expenses_status_tracking"
    end

    say_with_time "Creating optimized composite indexes..." do
      # Primary composite index for filtering operations (covers most queries)
      add_index :expenses, [ :email_account_id, :deleted_at, :transaction_date, :category_id, :status ],
                name: "idx_expenses_primary_composite",
                where: "deleted_at IS NULL",
                comment: "Primary composite index for filtering operations"

      # Merchant search index (trigram for fuzzy matching)
      unless index_exists?(:expenses, :merchant_normalized, name: "idx_expenses_merchant_search")
        # Keep existing if it exists
        add_index :expenses, :merchant_normalized,
                  name: "idx_expenses_merchant_fuzzy",
                  using: :gin,
                  opclass: :gin_trgm_ops,
                  where: "merchant_normalized IS NOT NULL AND deleted_at IS NULL",
                  comment: "Trigram index for merchant fuzzy search"
      end

      # Amount range queries (BRIN index for range scans)
      add_index :expenses, :amount,
                name: "idx_expenses_amount_range",
                using: :brin,
                comment: "BRIN index for amount range queries"

      # Date-based analytics (covering index)
      add_index :expenses, [ :transaction_date, :category_id, :amount ],
                name: "idx_expenses_analytics",
                where: "deleted_at IS NULL",
                comment: "Covering index for date-based analytics"

      # Uncategorized expenses (specific optimization)
      add_index :expenses, [ :category_id, :transaction_date ],
                name: "idx_expenses_uncategorized",
                where: "category_id IS NULL AND deleted_at IS NULL",
                comment: "Index for finding uncategorized expenses"

      # Auto-categorization tracking
      add_index :expenses, [ :auto_categorized, :categorization_confidence ],
                name: "idx_expenses_auto_categorization",
                where: "auto_categorized = true AND deleted_at IS NULL",
                comment: "Index for tracking auto-categorization"

      # Duplicate detection
      add_index :expenses, [ :email_account_id, :amount, :transaction_date, :merchant_name ],
                name: "idx_expenses_duplicate_check",
                comment: "Index for detecting duplicate transactions"
    end

    # Verify we're at or below target
    expense_indexes = ActiveRecord::Base.connection.indexes(:expenses)
    say "Expense table now has #{expense_indexes.size} indexes (target: ≤15)"

    if expense_indexes.size > 15
      say "WARNING: Still have #{expense_indexes.size} indexes, review for further consolidation", true
    end
  end

  def down
    # Remove new optimized indexes
    remove_index_if_exists :expenses, name: "idx_expenses_primary_composite"
    remove_index_if_exists :expenses, name: "idx_expenses_merchant_fuzzy"
    remove_index_if_exists :expenses, name: "idx_expenses_amount_range"
    remove_index_if_exists :expenses, name: "idx_expenses_analytics"
    remove_index_if_exists :expenses, name: "idx_expenses_uncategorized"
    remove_index_if_exists :expenses, name: "idx_expenses_auto_categorization"
    remove_index_if_exists :expenses, name: "idx_expenses_duplicate_check"

    # Note: Not recreating all removed indexes in down migration
    # as they were redundant. If needed, restore from schema backup.
  end

  private

  def remove_index_if_exists(table, columns = nil, name: nil)
    if name && index_exists?(table, name: name)
      remove_index table, name: name
    elsif columns && index_exists?(table, columns)
      remove_index table, columns
    end
  end
end
