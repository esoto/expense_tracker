# frozen_string_literal: true

# Step 3 of 3: Flip `api_tokens.user_id` to NOT NULL.
#
# Includes an inline re-backfill guard: any NULL rows that slipped in after
# the backfill (race window during deploy) are assigned to the first admin
# User before the NOT NULL constraint is applied.
class MakeApiTokensUserIdNotNull < ActiveRecord::Migration[8.1]
  class MigrationApiToken < ActiveRecord::Base
    self.table_name = "api_tokens"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    null_count = MigrationApiToken.where(user_id: nil).count

    if null_count.positive?
      default_user = MigrationUser.where(role: 1).order(:id).first

      raise ActiveRecord::MigrationError,
        "Found #{null_count} api_tokens with NULL user_id but no admin User " \
        "exists. Run PR 3 migration (CreateDefaultUserFromAdminUsers) first." unless default_user

      Rails.logger.warn(
        "[MakeApiTokensUserIdNotNull] #{null_count} NULL user_id rows found " \
        "after backfill — assigning to admin user id=#{default_user.id}."
      )
      MigrationApiToken.where(user_id: nil).update_all(user_id: default_user.id)
    end

    change_column_null :api_tokens, :user_id, false
  end

  def down
    change_column_null :api_tokens, :user_id, true
  end
end
