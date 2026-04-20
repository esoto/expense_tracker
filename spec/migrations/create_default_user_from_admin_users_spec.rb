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
    it "removes Users whose emails match AdminUsers" do
      create_admin_user(email: "todelete@example.com", role: 2)
      migration.up
      expect(User.where(email: "todelete@example.com").count).to eq(1)

      migration.down

      expect(User.where(email: "todelete@example.com").count).to eq(0)
    end

    it "does not remove Users whose emails do not match any AdminUser" do
      # Create a User that has no corresponding AdminUser
      User.connection.execute(<<~SQL.squish)
        INSERT INTO users
          (email, password_digest, name, role, failed_login_attempts, created_at, updated_at)
        VALUES
          ('unrelated@example.com', 'fakedigest', 'Unrelated', 0, 0, NOW(), NOW())
      SQL

      migration.down

      expect(User.where(email: "unrelated@example.com").count).to eq(1)
    end

    it "removes Users even when the AdminUser email is mixed case" do
      # `up` normalizes emails to lowercase when writing to users.
      # `down` must apply the same normalization so mixed-case AdminUsers
      # can still reverse the migration cleanly.
      create_admin_user(email: "MixedCase@Example.COM", role: 2)
      migration.up
      expect(User.where(email: "mixedcase@example.com").count).to eq(1)

      migration.down

      expect(User.where(email: "mixedcase@example.com").count).to eq(0)
    end
  end
end
