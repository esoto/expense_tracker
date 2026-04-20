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

  def up
    return unless connection.data_source_exists?("admin_users")

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

  def down
    return unless connection.data_source_exists?("admin_users")

    MigrationUser
      .where(email: MigrationAdminUser.pluck(:email))
      .delete_all
  end
end
