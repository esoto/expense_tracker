# frozen_string_literal: true

# Add performance indexes for MetricsCalculator service
# These indexes optimize queries for date ranges, category aggregations, and status filtering
class AddPerformanceIndexesForMetrics < ActiveRecord::Migration[8.0]
  def change
    # Composite index for date range queries with category
    add_index :expenses, [ :transaction_date, :category_id, :amount ],
              name: 'index_expenses_on_date_category_amount',
              if_not_exists: true

    # Composite index for date range queries with status
    add_index :expenses, [ :transaction_date, :status, :amount ],
              name: 'index_expenses_on_date_status_amount',
              if_not_exists: true

    # Composite index for merchant analysis
    add_index :expenses, [ :transaction_date, :merchant_name, :amount ],
              name: 'index_expenses_on_date_merchant_amount',
              if_not_exists: true

    # Composite index for currency breakdown
    add_index :expenses, [ :transaction_date, :currency, :amount ],
              name: 'index_expenses_on_date_currency_amount',
              if_not_exists: true

    # Index for uncategorized expense queries
    add_index :expenses, [ :category_id, :transaction_date, :amount ],
              where: 'category_id IS NULL',
              name: 'index_expenses_uncategorized',
              if_not_exists: true

    # Ensure categories name index exists for joins
    add_index :categories, :name, if_not_exists: true

    # Add index on created_at for recent calculations
    add_index :expenses, [ :created_at, :transaction_date ],
              name: 'index_expenses_on_created_and_transaction_date',
              if_not_exists: true
  end
end
