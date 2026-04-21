# frozen_string_literal: true

# Step 1 of 3: Add nullable `user_id` FK column to `api_tokens`.
#
# Strategy:
#   - Add `user_id` as a FK to `users` (nullable for now, NOT NULL added in step 3).
#   - Create the index CONCURRENTLY to avoid table locks in production.
#   - `disable_ddl_transaction!` is required for CONCURRENTLY index creation.
class AddUserToApiTokens < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :api_tokens, :user, foreign_key: true, index: false, null: true

    add_index :api_tokens, :user_id,
              algorithm: :concurrently,
              name: "index_api_tokens_on_user_id"
  end
end
