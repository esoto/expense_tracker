# frozen_string_literal: true

# Adds the `user_id` FK to `pattern_feedbacks` as a nullable column.
# The backfill runs in the next migration; the NOT NULL flip runs in the one
# after that.
#
# The index is created with `algorithm: :concurrently` so production writes
# are not blocked during deploy.  That forces `disable_ddl_transaction!`.
class AddUserToPatternFeedbacks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :pattern_feedbacks, :user, foreign_key: true, index: false, null: true
    add_index :pattern_feedbacks, :user_id, algorithm: :concurrently
  end
end
