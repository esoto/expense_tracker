# frozen_string_literal: true

# Adds the `user_id` FK to `external_budget_sources` as a nullable column.
# The backfill runs in the next migration; the NOT NULL flip runs in the one
# after that.
#
# The index is created with `algorithm: :concurrently` so production writes
# are not blocked during deploy.  That forces `disable_ddl_transaction!`.
class AddUserToExternalBudgetSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :external_budget_sources, :user, foreign_key: true, index: false, null: true
    add_index :external_budget_sources, :user_id, algorithm: :concurrently
  end
end
