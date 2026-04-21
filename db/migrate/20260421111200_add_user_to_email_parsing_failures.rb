# frozen_string_literal: true

# Adds the `user_id` FK to `email_parsing_failures` as a nullable column.  The
# backfill runs in the next migration; the NOT NULL flip runs in the one after.
#
# The index is created with `algorithm: :concurrently` so production writes are
# not blocked during deploy.  That forces `disable_ddl_transaction!` — Postgres
# cannot create a concurrent index inside a transaction.  The foreign key itself
# (a metadata-only change) is cheap and stays in the default (transactional)
# path.
class AddUserToEmailParsingFailures < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :email_parsing_failures, :user, foreign_key: true, index: false, null: true
    add_index :email_parsing_failures, :user_id, algorithm: :concurrently
  end
end
