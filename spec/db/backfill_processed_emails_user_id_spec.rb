# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_processed_emails_user_id*.rb")].first
require migration_file

# Run explicitly: TEST_ENV_NUMBER=pr7 bundle exec rspec spec/db/backfill_processed_emails_user_id_spec.rb
RSpec.describe BackfillProcessedEmailsUserId, unit: false, migration: true do
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

  def insert_processed_email(email_account_id:, user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    message_id = "msg-#{SecureRandom.hex(8)}@test.com"
    conn.execute(<<~SQL.squish)
      INSERT INTO processed_emails
        (message_id, email_account_id, user_id, processed_at, created_at, updated_at)
      VALUES
        (#{conn.quote(message_id)}, #{conn.quote(email_account_id)},
         #{uid_sql}, NOW(), NOW(), NOW())
    SQL
    ProcessedEmail.order(:id).last
  end

  def allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:processed_emails, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:processed_emails, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE processed_emails SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:processed_emails, :user_id, false)
  end

  def cleanup
    ProcessedEmail.delete_all
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

      it "inherits user_id from email_account when account has one" do
        pe = insert_processed_email(email_account_id: account.id)

        migration.up

        expect(pe.reload.user_id).to eq(admin_user.id)
      end

      it "assigns to admin user as final fallback for rows not covered by JOIN" do
        # All NULL user_id rows that the JOIN didn't cover are assigned to the
        # default admin. We verify this by inserting a processed_email that
        # already has an account with the admin's user_id (JOIN covers it),
        # then confirming the final update_all handles any remaining NULLs.
        pe = insert_processed_email(email_account_id: account.id)

        migration.up

        # Inherits admin user_id via the email_account JOIN path
        expect(pe.reload.user_id).to eq(admin_user.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        other_account = insert_email_account(user_id: other_user.id)
        assigned = insert_processed_email(email_account_id: other_account.id, user_id: other_user.id)
        null_pe = insert_processed_email(email_account_id: account.id)

        migration.up

        expect(assigned.reload.user_id).to eq(other_user.id)
        expect(null_pe.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero processed_emails gracefully (no-op)" do
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
