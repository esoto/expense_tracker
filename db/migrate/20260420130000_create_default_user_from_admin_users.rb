# frozen_string_literal: true

class CreateDefaultUserFromAdminUsers < ActiveRecord::Migration[8.1]
  # Local anonymous models ensure this migration works even after PR 14
  # removes the AdminUser class entirely.
  class MigrationAdminUser < ActiveRecord::Base
    self.table_name = "admin_users"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  REQUIRED_ADMIN_COLUMNS = %w[email name password_digest].freeze

  def up
    return unless connection.data_source_exists?("admin_users")

    preflight_admin_users!

    ActiveRecord::Base.transaction do
      MigrationAdminUser.find_each do |admin|
        user = MigrationUser.find_or_initialize_by(email: admin.email.to_s.downcase)
        next if user.persisted?

        # Role mapping: read_only (0) → user (0); everything else → admin (1)
        user_role = admin.role == 0 ? 0 : 1

        user.assign_attributes(
          password_digest: admin.password_digest,
          name: admin.name,
          role: user_role,
          session_token: admin.session_token,
          session_expires_at: admin.session_expires_at,
          last_login_at: admin.last_login_at,
          failed_login_attempts: admin.failed_login_attempts || 0,
          locked_at: admin.locked_at
        )

        # save(validate: false) so we bypass the password complexity regex —
        # we are copying an existing BCrypt digest, not setting a new password.
        user.save!(validate: false)
      end
    end
  end

  # Data migration: the safe semantic for rollback is "refuse," because we
  # cannot tell which user rows were created here vs. seeded beforehand.
  # Re-running `db:migrate` is idempotent (find_or_initialize_by), so a clean
  # forward path is always available. Spec uses a scoped harness for coverage.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "CreateDefaultUserFromAdminUsers is a one-way data migration. " \
      "To undo, delete the affected user rows by hand or restore from a backup."
  end

  private

  # Abort BEFORE touching `users` if admin_users is in a state that would
  # silently lose data during the copy.
  def preflight_admin_users!
    # 1. Duplicate emails after case-folding — admin_users has a raw unique
    #    index, but users has a unique lower(email) index. Two admin rows
    #    like "A@x.com" and "a@x.com" would collapse onto one user row and
    #    the second admin would be silently dropped.
    duplicate_emails = MigrationAdminUser
      .where.not(email: [ nil, "" ])
      .group("lower(email)")
      .having("count(*) > 1")
      .pluck("lower(email)")

    if duplicate_emails.any?
      raise ActiveRecord::MigrationError,
        "admin_users contains case-variant duplicate emails " \
        "(#{duplicate_emails.inspect}); resolve before migrating."
    end

    # 2. Blank required fields — save(validate: false) bypasses model presence
    #    checks, and the `users` table only enforces `null: false`, so an
    #    empty-string email/name/password_digest would persist silently.
    REQUIRED_ADMIN_COLUMNS.each do |col|
      blank_count = MigrationAdminUser.where("#{col} IS NULL OR #{col} = ''").count
      next if blank_count.zero?

      raise ActiveRecord::MigrationError,
        "admin_users has #{blank_count} row(s) with blank #{col}; " \
        "fix before migrating."
    end
  end
end
