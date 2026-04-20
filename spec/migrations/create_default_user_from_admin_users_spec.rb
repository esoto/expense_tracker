# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*create_default_user_from_admin_users*.rb")].first
require migration_file

RSpec.describe CreateDefaultUserFromAdminUsers, :unit do
  # Wipe users and admin_users between examples so each test starts clean.
  # We run the migration directly without the ActiveRecord schema version guard,
  # so we manage our own table state instead of relying on DatabaseCleaner.
  let(:migration) { described_class.new }

  # Helpers that bypass model validations so tests don't depend on password complexity.
  def create_admin_user(email:, role:)
    digest = BCrypt::Password.create("TestPass123!", cost: BCrypt::Engine::MIN_COST)
    AdminUser.connection.execute(<<~SQL.squish)
      INSERT INTO admin_users
        (email, password_digest, name, role, failed_login_attempts, created_at, updated_at)
      VALUES
        ('#{email}', '#{digest}', 'Test Admin', #{role},
         0, NOW(), NOW())
    SQL
    AdminUser.find_by!(email: email)
  end

  def cleanup
    User.delete_all
    AdminUser.delete_all
  end

  before { cleanup }
  after  { cleanup }

  describe "#up" do
    context "with a super_admin AdminUser (role 3)" do
      it "creates a User with role :admin" do
        admin = create_admin_user(email: "super@example.com", role: 3)

        migration.up

        user = User.find_by(email: "super@example.com")
        expect(user).not_to be_nil
        expect(user.role).to eq("admin")
      end
    end

    context "with an admin AdminUser (role 2)" do
      it "creates a User with role :admin" do
        create_admin_user(email: "admin@example.com", role: 2)

        migration.up

        user = User.find_by(email: "admin@example.com")
        expect(user).not_to be_nil
        expect(user.role).to eq("admin")
      end
    end

    context "with a moderator AdminUser (role 1)" do
      it "creates a User with role :admin" do
        create_admin_user(email: "mod@example.com", role: 1)

        migration.up

        user = User.find_by(email: "mod@example.com")
        expect(user).not_to be_nil
        expect(user.role).to eq("admin")
      end
    end

    context "with a read_only AdminUser (role 0)" do
      it "creates a User with role :user" do
        create_admin_user(email: "readonly@example.com", role: 0)

        migration.up

        user = User.find_by(email: "readonly@example.com")
        expect(user).not_to be_nil
        expect(user.role).to eq("user")
      end
    end

    context "idempotency" do
      it "running up twice creates only one User per AdminUser" do
        create_admin_user(email: "idempotent@example.com", role: 2)

        migration.up
        migration.up

        expect(User.where(email: "idempotent@example.com").count).to eq(1)
      end
    end

    context "password_digest preservation" do
      it "copies the BCrypt digest byte-for-byte without re-hashing" do
        admin = create_admin_user(email: "digest@example.com", role: 2)
        original_digest = admin.password_digest

        migration.up

        user = User.find_by(email: "digest@example.com")
        expect(user.password_digest).to eq(original_digest)
      end
    end
  end

  describe "#down" do
    it "raises IrreversibleMigration (one-way data migration)" do
      create_admin_user(email: "x@example.com", role: 2)
      migration.up

      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
      # Rollback must leave the user row in place, not partially remove it.
      expect(User.where(email: "x@example.com").count).to eq(1)
    end
  end

  describe "#up preflight checks" do
    it "aborts when admin_users has case-variant duplicate emails" do
      create_admin_user(email: "dupe@example.com", role: 2)
      create_admin_user(email: "Dupe@Example.com", role: 2)

      expect { migration.up }.to raise_error(
        ActiveRecord::MigrationError, /case-variant duplicate/i
      )
      # No partial write — transaction never opened.
      expect(User.where("lower(email) = ?", "dupe@example.com").count).to eq(0)
    end

    it "aborts when admin_users has a row with blank email" do
      # Bypass the email presence constraint by inserting raw SQL. The real
      # admin_users table enforces NOT NULL but NOT a length check, so an
      # empty string is accepted at the DB level.
      AdminUser.connection.execute(<<~SQL.squish)
        INSERT INTO admin_users
          (email, password_digest, name, role, failed_login_attempts, created_at, updated_at)
        VALUES
          ('', 'digest', 'Blank Email', 2, 0, NOW(), NOW())
      SQL

      expect { migration.up }.to raise_error(
        ActiveRecord::MigrationError, /blank email/i
      )
      expect(User.count).to eq(0)
    end

    it "aborts when admin_users has a row with blank name" do
      AdminUser.connection.execute(<<~SQL.squish)
        INSERT INTO admin_users
          (email, password_digest, name, role, failed_login_attempts, created_at, updated_at)
        VALUES
          ('blankname@example.com', 'digest', '', 2, 0, NOW(), NOW())
      SQL

      expect { migration.up }.to raise_error(
        ActiveRecord::MigrationError, /blank name/i
      )
      expect(User.count).to eq(0)
    end
  end
end
