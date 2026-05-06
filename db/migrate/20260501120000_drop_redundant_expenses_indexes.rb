# frozen_string_literal: true

class DropRedundantExpensesIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # 1. BRIN index on amount — structurally wrong type for a low-cardinality
    #    decimal column with non-sequential distribution. BRIN is only useful for
    #    physical-order-correlated append-only data (e.g. time-series IDs).
    remove_index :expenses, name: "idx_expenses_amount_range", algorithm: :concurrently, if_exists: true

    # 2. GIST trigram on merchant_normalized — redundant with the GIN trigram
    #    index (idx_expenses_merchant_search). GIN outperforms GIST for
    #    equality, LIKE, and containment queries; GIST's only advantage is
    #    nearest-neighbour <-> operator which we don't use here.
    remove_index :expenses, name: "index_expenses_merchant_similarity", algorithm: :concurrently, if_exists: true

    # 3. Partial category+transaction_date index — idx_expenses_category_date
    #    is (category_id, transaction_date) WHERE category_id IS NOT NULL AND
    #    deleted_at IS NULL. The unfiltered index
    #    index_expenses_on_category_id_and_transaction_date covers the same
    #    column set with no restriction, making this partial index redundant:
    #    the planner can use the broader index for any query that also matches
    #    the partial predicate.
    remove_index :expenses, name: "idx_expenses_category_date", algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :expenses, :amount,
              name: "idx_expenses_amount_range",
              using: :brin,
              comment: "BRIN index for amount range queries",
              algorithm: :concurrently

    add_index :expenses, :merchant_normalized,
              name: "index_expenses_merchant_similarity",
              using: :gist,
              opclass: :gist_trgm_ops,
              where: "(merchant_normalized IS NOT NULL)",
              algorithm: :concurrently

    add_index :expenses, %i[category_id transaction_date],
              name: "idx_expenses_category_date",
              where: "((category_id IS NOT NULL) AND (deleted_at IS NULL))",
              algorithm: :concurrently
  end
end
