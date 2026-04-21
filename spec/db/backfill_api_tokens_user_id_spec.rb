# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_api_tokens_user_id*.rb")].first
require migration_file

# This spec does DDL (change_column_null) that cannot run within a transaction.
# Run it explicitly: TEST_ENV_NUMBER=pr11 bundle exec rspec spec/db/backfill_api_tokens_user_id_spec.rb
RSpec.describe BackfillApiTokensUserId, unit: false, migration: true do
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

  def insert_api_token(name:, user_id: nil)
    conn = ActiveRecord::Base.connection
    token_string = SecureRandom.urlsafe_base64(32)
    digest = BCrypt::Password.create(token_string, cost: BCrypt::Engine::MIN_COST)
    token_hash = Digest::SHA256.hexdigest(token_string)
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO api_tokens
        (name, token_digest, token_hash, active, created_at, updated_at, user_id)
      VALUES
        (#{conn.quote(name)}, #{conn.quote(digest)}, #{conn.quote(token_hash)},
         true, NOW(), NOW(), #{uid_sql})
    SQL
    ApiToken.find_by!(name: name)
  end

  def allow_null_user_id
    # Temporarily relax NOT NULL so tests can insert NULL rows as they would
    # at the migration sequence point between step 1 (nullable) and step 3 (not null).
    ActiveRecord::Base.connection.change_column_null(:api_tokens, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:api_tokens, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    admin = User.where(role: 1).order(:id).first
    if admin
      ActiveRecord::Base.connection.execute(
        "UPDATE api_tokens SET user_id = #{admin.id} WHERE user_id IS NULL"
      )
    end
    ActiveRecord::Base.connection.change_column_null(:api_tokens, :user_id, false)
  end

  def cleanup
    ApiToken.delete_all
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

      it "assigns all NULL user_id api_tokens to the first admin" do
        t1 = insert_api_token(name: "Token One")
        t2 = insert_api_token(name: "Token Two")

        migration.up

        expect(t1.reload.user_id).to eq(admin_user.id)
        expect(t2.reload.user_id).to eq(admin_user.id)
      end

      it "picks the admin with the lowest id when multiple admins exist" do
        second_admin = insert_user(email: "admin2@example.com", role: 1)
        t = insert_api_token(name: "Token X")

        migration.up

        expect(t.reload.user_id).to eq(admin_user.id)
        expect(t.reload.user_id).not_to eq(second_admin.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        assigned_token = insert_api_token(name: "Assigned Token", user_id: other_user.id)
        null_token = insert_api_token(name: "Null Token")

        migration.up

        expect(assigned_token.reload.user_id).to eq(other_user.id)
        expect(null_token.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero api_tokens gracefully (no-op)" do
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
