# frozen_string_literal: true

class MakeExternalBudgetSourcesUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationExternalBudgetSource < ActiveRecord::Base
    self.table_name = "external_budget_sources"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column.
    null_count = MigrationExternalBudgetSource.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} external_budget_sources with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user

      # Prefer inheriting from email_account
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE external_budget_sources ebs
        SET user_id = ea.user_id
        FROM email_accounts ea
        WHERE ebs.email_account_id = ea.id
          AND ebs.user_id IS NULL
          AND ea.user_id IS NOT NULL
      SQL

      MigrationExternalBudgetSource.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :external_budget_sources, :user_id, false
  end

  def down
    change_column_null :external_budget_sources, :user_id, true
  end
end
