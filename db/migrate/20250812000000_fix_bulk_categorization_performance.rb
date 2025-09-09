# frozen_string_literal: true

class FixBulkCategorizationPerformance < ActiveRecord::Migration[8.0]
  def up
    # Enable pg_trgm extension if not already enabled
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    # Add trigram index for merchant_normalized to support similarity searches
    # This dramatically improves performance of fuzzy matching from O(n²) to O(log n)
    add_index :expenses, :merchant_normalized,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: "index_expenses_on_merchant_normalized_trgm",
              if_not_exists: true

    # Add composite indexes for common query patterns in bulk categorization
    add_index :expenses, [ :category_id, :merchant_normalized ],
              name: "index_expenses_on_category_id_and_merchant_normalized",
              if_not_exists: true

    add_index :expenses, [ :merchant_normalized, :transaction_date, :amount ],
              name: "index_expenses_on_merchant_date_amount",
              if_not_exists: true

    # Add index for uncategorized expenses with merchant data
    add_index :expenses, [ :merchant_normalized, :category_id ],
              where: "category_id IS NULL AND merchant_normalized IS NOT NULL",
              name: "index_expenses_uncategorized_with_merchant",
              if_not_exists: true

    # Add functional index for similarity searches
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_expenses_merchant_similarity
      ON expenses#{' '}
      USING gist (merchant_normalized gist_trgm_ops)
      WHERE merchant_normalized IS NOT NULL;
    SQL
  end

  def down
    remove_index :expenses, name: "index_expenses_on_merchant_normalized_trgm", if_exists: true
    remove_index :expenses, name: "index_expenses_on_category_id_and_merchant_normalized", if_exists: true
    remove_index :expenses, name: "index_expenses_on_merchant_date_amount", if_exists: true
    remove_index :expenses, name: "index_expenses_uncategorized_with_merchant", if_exists: true

    execute "DROP INDEX IF EXISTS index_expenses_merchant_similarity;"
  end
end
