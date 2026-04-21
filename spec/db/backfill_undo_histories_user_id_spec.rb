# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_undo_histories_user_id*.rb")].first
require migration_file

# Run explicitly: TEST_ENV_NUMBER=pr8 bundle exec rspec spec/db/backfill_undo_histories_user_id_spec.rb
RSpec.describe BackfillUndoHistoriesUserId, unit: false, migration: true do
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

  def insert_undo_history(user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO undo_histories
        (action_type, undoable_type, record_data, user_id, is_bulk, affected_count, created_at, updated_at)
      VALUES
        (0, 'Expense', '{}', #{uid_sql}, false, 1, NOW(), NOW())
    SQL
    UndoHistory.order(:id).last
  end

  def allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:undo_histories, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:undo_histories, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE undo_histories SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:undo_histories, :user_id, false)
  end

  def cleanup
    UndoHistory.delete_all
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

      it "assigns NULL user_id rows to the admin user" do
        history = insert_undo_history

        migration.up

        expect(history.reload.user_id).to eq(admin_user.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user = insert_user(email: "other@example.com", role: 0)
        assigned   = insert_undo_history(user_id: other_user.id)
        null_hist  = insert_undo_history

        migration.up

        expect(assigned.reload.user_id).to eq(other_user.id)
        expect(null_hist.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero undo_histories gracefully (no-op)" do
        expect { migration.up }.not_to raise_error
      end

      it "is idempotent — running twice does not change user_id" do
        history = insert_undo_history(user_id: admin_user.id)

        migration.up
        migration.up

        expect(history.reload.user_id).to eq(admin_user.id)
      end
    end
  end

  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
