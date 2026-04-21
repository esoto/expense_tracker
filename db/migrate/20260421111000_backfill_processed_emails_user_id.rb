# frozen_string_literal: true

class BackfillProcessedEmailsUserId < ActiveRecord::Migration[8.1]
  # Local anonymous models isolate this migration from future class changes.
  class MigrationProcessedEmail < ActiveRecord::Base
    self.table_name = "processed_emails"
  end

  class MigrationEmailAccount < ActiveRecord::Base
    self.table_name = "email_accounts"
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

    # Prefer inheriting user_id from the associated email_account where available.
    # Fall back to the default admin user for any orphaned or already-null rows.
    ActiveRecord::Base.transaction do
      # Rows whose email_account has a user_id — inherit from account
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE processed_emails pe
        SET user_id = ea.user_id
        FROM email_accounts ea
        WHERE pe.email_account_id = ea.id
          AND pe.user_id IS NULL
          AND ea.user_id IS NOT NULL
      SQL

      # Remaining NULL rows — assign to first admin user
      MigrationProcessedEmail.where(user_id: nil).update_all(user_id: default_user.id)
    end
  end

  # Data migration — cannot safely determine which rows had a NULL user_id
  # before the backfill ran, so reversal would silently destroy ownership data.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillProcessedEmailsUserId is a one-way data migration. " \
      "Rows cannot be safely reverted to NULL without knowing prior state."
  end
end
