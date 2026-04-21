# frozen_string_literal: true

class BackfillPatternFeedbacksUserId < ActiveRecord::Migration[8.1]
  # Local anonymous models isolate this migration from future class changes.
  class MigrationPatternFeedback < ActiveRecord::Base
    self.table_name = "pattern_feedbacks"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    default_user = MigrationUser.where(role: 1).order(:id).first

    if default_user.nil?
      raise ActiveRecord::MigrationError,
        "No admin User found — run PR 3 migration (CreateDefaultUserFromAdminUsers) first."
    end

    # Prefer inheriting user_id from the associated expense where available.
    # Fall back to the default admin user for any orphaned or already-null rows.
    ActiveRecord::Base.transaction do
      # Rows whose expense has a user_id — inherit from expense
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE pattern_feedbacks pf
        SET user_id = e.user_id
        FROM expenses e
        WHERE pf.expense_id = e.id
          AND pf.user_id IS NULL
          AND e.user_id IS NOT NULL
      SQL

      # Remaining NULL rows — assign to first admin user
      MigrationPatternFeedback.where(user_id: nil).update_all(user_id: default_user.id)
    end
  end

  # Data migration — cannot safely determine which rows had a NULL user_id
  # before the backfill ran, so reversal would silently destroy ownership data.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillPatternFeedbacksUserId is a one-way data migration. " \
      "Rows cannot be safely reverted to NULL without knowing prior state."
  end
end
