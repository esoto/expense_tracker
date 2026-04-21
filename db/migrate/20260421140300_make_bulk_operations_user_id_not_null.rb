# frozen_string_literal: true

# Step 4 of 4: Flip `bulk_operations.user_id` to NOT NULL.
#
# Includes a race-guard re-check: any NULL rows that sneaked in after the
# backfill (e.g. from an old code path still writing nil user_id) are assigned
# to the first admin User before the constraint is applied.
class MakeBulkOperationsUserIdNotNull < ActiveRecord::Migration[8.1]
  class MigrationBulkOp < ActiveRecord::Base
    self.table_name = "bulk_operations"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    null_count = MigrationBulkOp.where(user_id: nil).count

    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first

      raise ActiveRecord::MigrationError,
        "Found #{null_count} bulk_operations with NULL user_id but no admin User " \
        "exists. Run PR 3 migration (CreateDefaultUserFromAdminUsers) first." unless default_user

      Rails.logger.warn(
        "[MakeBulkOperationsUserIdNotNull] #{null_count} NULL user_id rows found " \
        "after backfill — assigning to admin user id=#{default_user.id}."
      )
      MigrationBulkOp.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :bulk_operations, :user_id, false
  end

  def down
    change_column_null :bulk_operations, :user_id, true
  end
end
