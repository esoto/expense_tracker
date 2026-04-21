# frozen_string_literal: true

class BackfillBudgetsUserId < ActiveRecord::Migration[8.1]
  # Local anonymous models isolate this migration from future class changes.
  class MigrationBudget < ActiveRecord::Base
    self.table_name = "budgets"
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

    ActiveRecord::Base.transaction do
      MigrationBudget.where(user_id: nil).update_all(user_id: default_user.id)
    end
  end

  # Data migration — cannot safely determine which rows had a NULL user_id
  # before the backfill ran, so reversal would silently destroy ownership data.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillBudgetsUserId is a one-way data migration. " \
      "Rows cannot be safely reverted to NULL without knowing prior state."
  end
end
