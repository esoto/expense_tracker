# frozen_string_literal: true

class MakeProcessedEmailsUserIdNotNull < ActiveRecord::Migration[8.1]
  # Local anonymous models — PR 14 may remove AdminUser but this migration
  # must still run. Matches the pattern established in the backfill migration.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationProcessedEmail < ActiveRecord::Base
    self.table_name = "processed_emails"
  end

  def up
    # Re-run the backfill immediately before the NOT NULL flip to close the
    # narrow race between the backfill migration and this one. A concurrent
    # insert from an old code path could have written a NULL user_id after
    # the backfill ran but before this migration locks the column.
    null_count = MigrationProcessedEmail.where(user_id: nil).count
    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first
      raise ActiveRecord::MigrationError,
        "Found #{null_count} processed_emails with NULL user_id but no admin User " \
        "exists. Run PR 3 migration first." unless default_user

      # Prefer inheriting from email_account
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE processed_emails pe
        SET user_id = ea.user_id
        FROM email_accounts ea
        WHERE pe.email_account_id = ea.id
          AND pe.user_id IS NULL
          AND ea.user_id IS NOT NULL
      SQL

      MigrationProcessedEmail.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :processed_emails, :user_id, false
  end

  def down
    change_column_null :processed_emails, :user_id, true
  end
end
