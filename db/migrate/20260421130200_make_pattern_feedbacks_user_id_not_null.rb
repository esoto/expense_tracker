# frozen_string_literal: true

class MakePatternFeedbacksUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationPatternFeedback < ActiveRecord::Base
    self.table_name = "pattern_feedbacks"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column.
    null_count = MigrationPatternFeedback.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} pattern_feedbacks with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user

      # Prefer inheriting from expense
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE pattern_feedbacks pf
        SET user_id = e.user_id
        FROM expenses e
        WHERE pf.expense_id = e.id
          AND pf.user_id IS NULL
          AND e.user_id IS NOT NULL
      SQL

      MigrationPatternFeedback.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :pattern_feedbacks, :user_id, false
  end

  def down
    change_column_null :pattern_feedbacks, :user_id, true
  end
end
