# frozen_string_literal: true

# Add composite indexes with email_account_id first for efficient user data isolation
# These indexes optimize queries that filter by email_account_id first
class AddEmailAccountIndexesForMetrics < ActiveRecord::Migration[8.0]
  def change
    # Remove existing indexes that will be replaced with composite ones
    remove_index :expenses, :transaction_date if index_exists?(:expenses, :transaction_date)
    remove_index :expenses, [:transaction_date, :amount] if index_exists?(:expenses, [:transaction_date, :amount])
    
    # Add composite indexes with email_account_id first for better performance
    # These ensure queries scoped by email_account are optimized
    
    # Primary metrics queries
    add_index :expenses, [:email_account_id, :transaction_date, :status], 
              name: 'idx_expenses_account_date_status'
    
    add_index :expenses, [:email_account_id, :transaction_date, :category_id, :amount], 
              name: 'idx_expenses_account_date_category_amount'
    
    add_index :expenses, [:email_account_id, :transaction_date, :currency], 
              name: 'idx_expenses_account_date_currency'
    
    add_index :expenses, [:email_account_id, :transaction_date, :merchant_name], 
              name: 'idx_expenses_account_date_merchant'
    
    # For uncategorized expenses query
    add_index :expenses, [:email_account_id, :category_id, :transaction_date], 
              name: 'idx_expenses_account_uncategorized',
              where: 'category_id IS NULL'
    
    # For aggregation queries
    add_index :expenses, [:email_account_id, :status, :transaction_date, :amount], 
              name: 'idx_expenses_account_status_date_amount'
    
    # Keep the general transaction_date index for other queries
    add_index :expenses, :transaction_date unless index_exists?(:expenses, :transaction_date)
    add_index :expenses, [:transaction_date, :amount] unless index_exists?(:expenses, [:transaction_date, :amount])
  end
end
