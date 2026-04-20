# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_email_accounts_user_id*.rb")].first
require migration_file

# This spec does DDL (change_column_null) that cannot run within a transaction.
# The spec/migrations/ directory is auto-tagged :unit by test_tiers.rb, but we
# override that here with unit: false to keep this spec out of the transactional
# unit suite (where DDL auto-commits the wrapping transaction and corrupts other
# examples).  Run it explicitly: TEST_ENV_NUMBER=pr4 bundle exec rspec spec/migrations/
RSpec.describe BackfillEmailAccountsUserId, unit: false, migration: true do
  let(:migration) { described_class.new }

  # Minimal raw SQL helpers that bypass model validations and callbacks.
  # These must work even if the model layer changes in later PRs.
  def insert_user(email:, role: 0)
    digest = BCrypt::Password.create("TestPass123!", cost: BCrypt::Engine::MIN_COST)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO users
        (email, name, password_digest, role, failed_login_attempts, created_at, updated_at)
      VALUES
        ('#{email}', 'Test User', '#{digest}', #{role}, 0, NOW(), NOW())
    SQL
    User.find_by!(email: email)
  end

  # Inserts an email_account row bypassing model validations.
  # Relies on the NOT NULL constraint being relaxed for the duration of the
  # test (managed by the before/after hooks below via allow_null_user_id).
  def insert_email_account(email:, user_id: nil)
    uid_sql = user_id.nil? ? "NULL" : user_id.to_s
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO email_accounts
        (email, provider, bank_name, active, created_at, updated_at, user_id)
      VALUES
        ('#{email}', 'gmail', 'BAC', true, NOW(), NOW(), #{uid_sql})
    SQL
    EmailAccount.find_by!(email: email)
  end

  def allow_null_user_id
    # The backfill migration logically runs between migration 1 (nullable) and
    # migration 3 (not null). We temporarily relax the NOT NULL constraint so
    # tests can insert NULL rows as they would at that migration sequence point.
    # DDL cannot run inside a failed transaction, so we use a fresh connection.
    ActiveRecord::Base.connection.change_column_null(:email_accounts, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:email_accounts, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    # If NULL rows exist (e.g. after a failed test), clean them first.
    ActiveRecord::Base.connection.execute(
      "UPDATE email_accounts SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:email_accounts, :user_id, false)
  end

  def cleanup
    # Must have nullable column to delete without FK issues when user rows go away.
    EmailAccount.delete_all
    User.delete_all
  end

  before do
    allow_null_user_id
    cleanup
  end

  after do
    cleanup
    enforce_not_null_user_id
  end

  describe "#up" do
    context "when no admin User exists" do
      it "raises ActiveRecord::MigrationError" do
        insert_user(email: "regular@example.com", role: 0) # role: user, not admin

        expect { migration.up }.to raise_error(
          ActiveRecord::MigrationError,
          /No admin User found/
        )
      end

      it "raises when users table is completely empty" do
        expect { migration.up }.to raise_error(
          ActiveRecord::MigrationError,
          /No admin User found/
        )
      end
    end

    context "when an admin User exists" do
      let!(:admin_user) { insert_user(email: "admin@example.com", role: 1) }

      it "assigns all NULL user_id email accounts to the first admin" do
        ea1 = insert_email_account(email: "account1@test.com")
        ea2 = insert_email_account(email: "account2@test.com")

        migration.up

        expect(ea1.reload.user_id).to eq(admin_user.id)
        expect(ea2.reload.user_id).to eq(admin_user.id)
      end

      it "picks the admin with the lowest id when multiple admins exist" do
        second_admin = insert_user(email: "admin2@example.com", role: 1)
        ea = insert_email_account(email: "account@test.com")

        migration.up

        expect(ea.reload.user_id).to eq(admin_user.id)
        expect(ea.reload.user_id).not_to eq(second_admin.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        assigned_ea = insert_email_account(email: "assigned@test.com", user_id: other_user.id)
        null_ea = insert_email_account(email: "null@test.com")

        migration.up

        expect(assigned_ea.reload.user_id).to eq(other_user.id)
        expect(null_ea.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero email accounts gracefully (no-op)" do
        expect { migration.up }.not_to raise_error
      end
    end
  end

  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
