# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_budgets_user_id*.rb")].first
require migration_file

# This spec does DDL (change_column_null) that cannot run within a transaction.
# Run it explicitly: TEST_ENV_NUMBER=pr6 bundle exec rspec spec/db/backfill_budgets_user_id_spec.rb
RSpec.describe BackfillBudgetsUserId, unit: false, migration: true do
  let(:migration) { described_class.new }

  # Minimal raw SQL helpers that bypass model validations and callbacks.
  # These must work even if the model layer changes in later PRs.
  # Uses connection.quote on every interpolated value to defuse any SQL
  # injection risk in the template — even though test inputs are controlled,
  # this is the shape PRs 5-10 will copy so it must be safe by default.
  def insert_user(email:, role: 0)
    digest = BCrypt::Password.create("TestPass123!", cost: BCrypt::Engine::MIN_COST)
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL.squish)
      INSERT INTO users
        (email, name, password_digest, role, failed_login_attempts, created_at, updated_at)
      VALUES
        (#{conn.quote(email)}, #{conn.quote("Test User")}, #{conn.quote(digest)},
         #{conn.quote(role)}, 0, NOW(), NOW())
    SQL
    User.find_by!(email: email)
  end

  # Inserts an email_account row needed as FK for budget.
  def insert_email_account(user_id:)
    conn = ActiveRecord::Base.connection
    email = "account-#{user_id}-#{rand(9999)}@example.com"
    conn.execute(<<~SQL.squish)
      INSERT INTO email_accounts
        (email, provider, bank_name, active, user_id, created_at, updated_at)
      VALUES
        (#{conn.quote(email)}, #{conn.quote("gmail")}, #{conn.quote("Test Bank")},
         true, #{conn.quote(user_id)}, NOW(), NOW())
    SQL
    EmailAccount.where(user_id: user_id).order(:id).last
  end

  # Inserts a budget row bypassing model validations.
  # Relies on the NOT NULL constraint being relaxed for the duration of the
  # test (managed by the before/after hooks below via allow_null_user_id).
  def insert_budget(name:, email_account_id:, user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO budgets
        (name, amount, period, currency, active, start_date,
         email_account_id, warning_threshold, critical_threshold,
         created_at, updated_at, user_id)
      VALUES
        (#{conn.quote(name)}, 500000.00, 2, #{conn.quote("CRC")},
         true, #{conn.quote(Date.current.to_s)},
         #{conn.quote(email_account_id)}, 70, 90,
         NOW(), NOW(), #{uid_sql})
    SQL
    Budget.find_by!(name: name)
  end

  def allow_null_user_id
    # The backfill migration logically runs between migration 1 (nullable) and
    # migration 3 (not null). We temporarily relax the NOT NULL constraint so
    # tests can insert NULL rows as they would at that migration sequence point.
    ActiveRecord::Base.connection.change_column_null(:budgets, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:budgets, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    # If NULL rows exist (e.g. after a failed test), clean them first.
    ActiveRecord::Base.connection.execute(
      "UPDATE budgets SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:budgets, :user_id, false)
  end

  def cleanup
    # Must have nullable column to delete without FK issues when user rows go away.
    Budget.delete_all
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

      it "assigns all NULL user_id budgets to the first admin" do
        account = insert_email_account(user_id: admin_user.id)
        b1 = insert_budget(name: "Budget One", email_account_id: account.id)
        b2 = insert_budget(name: "Budget Two", email_account_id: account.id)

        migration.up

        expect(b1.reload.user_id).to eq(admin_user.id)
        expect(b2.reload.user_id).to eq(admin_user.id)
      end

      it "picks the admin with the lowest id when multiple admins exist" do
        second_admin = insert_user(email: "admin2@example.com", role: 1)
        account = insert_email_account(user_id: admin_user.id)
        b = insert_budget(name: "Budget X", email_account_id: account.id)

        migration.up

        expect(b.reload.user_id).to eq(admin_user.id)
        expect(b.reload.user_id).not_to eq(second_admin.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        account_admin = insert_email_account(user_id: admin_user.id)
        account_other = insert_email_account(user_id: other_user.id)
        assigned_budget = insert_budget(name: "Assigned Budget", email_account_id: account_other.id, user_id: other_user.id)
        null_budget = insert_budget(name: "Null Budget", email_account_id: account_admin.id)

        migration.up

        expect(assigned_budget.reload.user_id).to eq(other_user.id)
        expect(null_budget.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero budgets gracefully (no-op)" do
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
