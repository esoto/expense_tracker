# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_sync_conflicts_user_id*.rb")].first
require migration_file

# Run explicitly: TEST_ENV_NUMBER=pr7 bundle exec rspec spec/db/backfill_sync_conflicts_user_id_spec.rb
RSpec.describe BackfillSyncConflictsUserId, unit: false, migration: true do
  let(:migration) { described_class.new }

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

  def insert_sync_session(user_id:)
    conn = ActiveRecord::Base.connection
    token = SecureRandom.urlsafe_base64(16)
    conn.execute(<<~SQL.squish)
      INSERT INTO sync_sessions
        (status, total_emails, processed_emails, detected_expenses, session_token,
         user_id, created_at, updated_at)
      VALUES
        ('pending', 0, 0, 0, #{conn.quote(token)},
         #{conn.quote(user_id)}, NOW(), NOW())
    SQL
    SyncSession.order(:id).last
  end

  def insert_email_account(user_id:)
    conn = ActiveRecord::Base.connection
    email = "account-#{user_id}-#{rand(9999)}@example.com"
    conn.execute(<<~SQL.squish)
      INSERT INTO email_accounts
        (email, provider, bank_name, active, user_id, created_at, updated_at)
      VALUES
        (#{conn.quote(email)}, 'gmail', 'Test Bank',
         true, #{conn.quote(user_id)}, NOW(), NOW())
    SQL
    EmailAccount.order(:id).last
  end

  def insert_expense(email_account_id:, user_id:)
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL.squish)
      INSERT INTO expenses
        (amount, transaction_date, email_account_id, user_id,
         status, created_at, updated_at)
      VALUES
        (10000.00, #{conn.quote(Date.current.to_s)},
         #{conn.quote(email_account_id)}, #{conn.quote(user_id)},
         'pending', NOW(), NOW())
    SQL
    Expense.order(:id).last
  end

  def insert_sync_conflict(sync_session_id:, existing_expense_id:, user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO sync_conflicts
        (sync_session_id, existing_expense_id, conflict_type, status,
         priority, user_id, created_at, updated_at)
      VALUES
        (#{conn.quote(sync_session_id)}, #{conn.quote(existing_expense_id)},
         'duplicate', 'pending', 1, #{uid_sql}, NOW(), NOW())
    SQL
    SyncConflict.order(:id).last
  end

  def allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:sync_conflicts, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:sync_conflicts, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE sync_conflicts SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:sync_conflicts, :user_id, false)
  end

  def cleanup
    SyncConflict.delete_all
    Expense.delete_all
    SyncSession.delete_all
    EmailAccount.delete_all
    User.delete_all
  end

  before do
    allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:sync_sessions, :user_id, true)
    cleanup
  end

  after do
    cleanup
    enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:sync_sessions, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE sync_sessions SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:sync_sessions, :user_id, false)
  end

  describe "#up" do
    context "when no admin User exists" do
      it "raises ActiveRecord::MigrationError" do
        insert_user(email: "regular@example.com", role: 0)
        expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /No admin User found/)
      end

      it "raises when users table is completely empty" do
        expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /No admin User found/)
      end
    end

    context "when an admin User exists" do
      let!(:admin_user) { insert_user(email: "admin@example.com", role: 1) }
      let!(:account) { insert_email_account(user_id: admin_user.id) }
      let!(:session) { insert_sync_session(user_id: admin_user.id) }
      let!(:expense) { insert_expense(email_account_id: account.id, user_id: admin_user.id) }

      it "inherits user_id from sync_session when session has one" do
        conflict = insert_sync_conflict(sync_session_id: session.id, existing_expense_id: expense.id)

        migration.up

        expect(conflict.reload.user_id).to eq(admin_user.id)
      end

      it "assigns to admin user for orphaned conflicts" do
        conn = ActiveRecord::Base.connection
        token = SecureRandom.urlsafe_base64(16)
        conn.execute(<<~SQL.squish)
          INSERT INTO sync_sessions
            (status, total_emails, processed_emails, detected_expenses,
             session_token, user_id, created_at, updated_at)
          VALUES ('pending', 0, 0, 0, #{conn.quote(token)}, NULL, NOW(), NOW())
        SQL
        orphaned_session = SyncSession.order(:id).last
        conflict = insert_sync_conflict(sync_session_id: orphaned_session.id, existing_expense_id: expense.id)

        migration.up

        expect(conflict.reload.user_id).to eq(admin_user.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        assigned = insert_sync_conflict(sync_session_id: session.id,
                                       existing_expense_id: expense.id,
                                       user_id: other_user.id)
        null_conflict = insert_sync_conflict(sync_session_id: session.id, existing_expense_id: expense.id)

        migration.up

        expect(assigned.reload.user_id).to eq(other_user.id)
        expect(null_conflict.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero sync_conflicts gracefully (no-op)" do
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
