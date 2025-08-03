class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Dashboard query optimizations
    # Combines status + date for filtered queries
    add_index :expenses, [ :status, :transaction_date ],
              name: "index_expenses_on_status_and_transaction_date"

    # For bank-specific dashboard views and reports
    add_index :expenses, [ :bank_name, :transaction_date ],
              name: "index_expenses_on_bank_name_and_transaction_date"

    # For top merchants queries (sorted by amount)
    add_index :expenses, [ :merchant_name, :amount ],
              name: "index_expenses_on_merchant_name_and_amount"

    # Sync operations optimization - finding latest expenses per account
    add_index :expenses, [ :email_account_id, :created_at ],
              name: "index_expenses_on_email_account_id_and_created_at"

    # For date range queries with amount aggregation
    add_index :expenses, [ :transaction_date, :amount ],
              name: "index_expenses_on_transaction_date_and_amount"

    # Category + date queries (category_id index already exists)
    add_index :expenses, [ :category_id, :transaction_date ],
              name: "index_expenses_on_category_id_and_transaction_date"

    # Parsing rules optimization - find active rules by bank
    # (bank_name and active indexes exist separately, this combines them)
    add_index :parsing_rules, [ :bank_name, :active ],
              name: "index_parsing_rules_on_bank_name_and_active"

    # API token optimization - find active non-expired tokens
    # (active and expires_at indexes exist separately, this combines them)
    add_index :api_tokens, [ :active, :expires_at ],
              name: "index_api_tokens_on_active_and_expires_at"

    # Email account optimization - find active accounts by bank
    # (active and bank_name indexes exist separately, this combines them)
    add_index :email_accounts, [ :active, :bank_name ],
              name: "index_email_accounts_on_active_and_bank_name"
  end
end
