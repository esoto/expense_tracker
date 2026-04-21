# frozen_string_literal: true

class MakeBudgetsUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationBudget < ActiveRecord::Base
    self.table_name = "budgets"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column. We inline
    # the same update_all logic here so any freshly-NULL rows get assigned
    # to the default admin user before the constraint is enforced.
    null_count = MigrationBudget.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} budgets with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user
      MigrationBudget.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :budgets, :user_id, false
  end

  def down
    change_column_null :budgets, :user_id, true
  end
end
