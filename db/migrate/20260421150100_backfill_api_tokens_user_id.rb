# frozen_string_literal: true

# Step 2 of 3: Backfill `api_tokens.user_id`.
#
# All api_tokens are system tokens (iPhone Shortcuts, etc.) — there is no
# per-user mapping at this stage. Assign every token to the first admin User.
# If no admin User exists, raise MigrationError so the operator is alerted
# rather than leaving NULLs that would block step 3.
class BackfillApiTokensUserId < ActiveRecord::Migration[8.1]
  # Isolated anonymous models so this migration stays runnable after any future
  # refactor or removal of these classes from the app codebase.
  class MigrationApiToken < ActiveRecord::Base
    self.table_name = "api_tokens"
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
      MigrationApiToken.where(user_id: nil).update_all(user_id: default_user.id)
    end
  end

  # Data migration — cannot determine which rows were NULL before the backfill,
  # so reversal would silently destroy ownership data.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillApiTokensUserId is a one-way data migration. " \
      "Rows cannot be safely reverted to NULL without knowing prior state."
  end
end
