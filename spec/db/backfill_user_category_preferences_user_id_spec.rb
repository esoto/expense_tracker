# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_user_category_preferences_user_id*.rb")].first
require migration_file

# Run explicitly: TEST_ENV_NUMBER=pr8 bundle exec rspec spec/db/backfill_user_category_preferences_user_id_spec.rb
RSpec.describe BackfillUserCategoryPreferencesUserId, unit: false, migration: true do
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

  def insert_category
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL.squish)
      INSERT INTO categories (name, color, created_at, updated_at)
      VALUES ('Test Category', '#000000', NOW(), NOW())
    SQL
    Category.order(:id).last
  end

  def insert_user_category_preference(email_account_id:, category_id:, user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO user_category_preferences
        (email_account_id, category_id, context_type, context_value,
         preference_weight, usage_count, user_id, created_at, updated_at)
      VALUES
        (#{conn.quote(email_account_id)}, #{conn.quote(category_id)},
         'merchant', 'test_merchant', 1, 0,
         #{uid_sql}, NOW(), NOW())
    SQL
    UserCategoryPreference.order(:id).last
  end

  def allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:user_category_preferences, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:user_category_preferences, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE user_category_preferences SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:user_category_preferences, :user_id, false)
  end

  def cleanup
    UserCategoryPreference.delete_all
    Category.delete_all
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
      let!(:account)    { insert_email_account(user_id: admin_user.id) }
      let!(:category)   { insert_category }

      it "inherits user_id from email_account when account has one" do
        pref = insert_user_category_preference(email_account_id: account.id, category_id: category.id)

        migration.up

        expect(pref.reload.user_id).to eq(admin_user.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user    = insert_user(email: "other@example.com", role: 0)
        other_account = insert_email_account(user_id: other_user.id)
        assigned      = insert_user_category_preference(
          email_account_id: other_account.id, category_id: category.id, user_id: other_user.id
        )
        null_pref = insert_user_category_preference(email_account_id: account.id, category_id: category.id)

        migration.up

        expect(assigned.reload.user_id).to eq(other_user.id)
        expect(null_pref.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero user_category_preferences gracefully (no-op)" do
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
