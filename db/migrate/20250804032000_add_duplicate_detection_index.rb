class AddDuplicateDetectionIndex < ActiveRecord::Migration[8.0]
  def change
    # Optimize duplicate detection queries
    add_index :expenses, [ :email_account_id, :amount, :transaction_date ],
              name: "index_expenses_on_account_amount_date_for_duplicates"

    # Also add index for merchant name lookups
    add_index :expenses, :merchant_name,
              name: "index_expenses_on_merchant_name"
  end
end
