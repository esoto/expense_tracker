# frozen_string_literal: true

# Step 2 of 4: Populate `user_bigint_id` by resolving each string `user_id`
# through the AdminUser → User email chain established by PR 3.
#
# Lookup chain per row:
#   1. Parse user_id string as integer → find AdminUser by that id.
#   2. If AdminUser found, look up User by admin_user.email (downcased).
#      This handles the normal case: AdminUser.id 1 → User with same email.
#   3. If AdminUser NOT found (orphan / already-migrated row), try
#      MigrationUser.find_by(id: row.user_id.to_i) directly in case user_id
#      already pointed at a users.id.
#   4. If still unresolved, fall back to the first admin User (role 1) and
#      emit a Rails.logger.warn so the fallback is visible in dev logs.
#      Production should never reach step 4 thanks to PR 3's full backfill.
#
# Raises ActiveRecord::MigrationError if a row cannot be resolved AND no
# fallback admin User exists — prevents a silent NULL FK violation.
class BackfillBulkOperationsUserBigint < ActiveRecord::Migration[8.1]
  # Isolated anonymous models so this migration remains runnable after PR 14
  # removes AdminUser from the app codebase.
  class MigrationBulkOp < ActiveRecord::Base
    self.table_name = "bulk_operations"
  end

  class MigrationAdminUser < ActiveRecord::Base
    self.table_name = "admin_users"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    MigrationBulkOp.where.not(user_id: nil).find_each do |row|
      next if row.user_bigint_id.present? # Already resolved (idempotent)

      resolved_user_id = resolve_user_id(row)
      row.update_columns(user_bigint_id: resolved_user_id)
    end
  end

  # Data migration — resolving in reverse is not deterministic.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "BackfillBulkOperationsUserBigint is a one-way data migration. " \
      "String user_id values cannot be reconstructed from bigint FKs."
  end

  private

  def resolve_user_id(row)
    string_id = row.user_id.to_s.strip
    return nil if string_id.blank?

    int_id = string_id.to_i

    # Step 1: look up AdminUser by the string-as-integer id.
    admin_user = MigrationAdminUser.find_by(id: int_id)

    if admin_user
      # Step 2: find the mirrored User by email (PR 3 used email as the key).
      user = MigrationUser.find_by(email: admin_user.email.to_s.downcase)
      return user.id if user
    end

    # Step 3: maybe user_id already pointed at users.id (e.g. after partial migration).
    direct_user = MigrationUser.find_by(id: int_id)
    return direct_user.id if direct_user

    # No resolution — abort the migration rather than silently reassigning
    # ownership. Codex review flagged that a fallback to the first admin
    # changes who owns the bulk_operation row, which is a data-integrity
    # issue (e.g. another admin's historical bulk ops would be attributed
    # to the lowest-id admin). Better to fail loudly so the operator can
    # investigate the orphan row before deciding how to handle it.
    raise ActiveRecord::MigrationError,
      "bulk_operations##{row.id} user_id='#{row.user_id}' could not be " \
      "resolved to any User. Resolve the orphan row manually (either " \
      "delete it or reassign it to the correct User), then re-run the " \
      "migration. If PR 3 (CreateDefaultUserFromAdminUsers) has not run, " \
      "run it first."
  end
end
