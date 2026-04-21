# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_pattern_feedbacks_user_id*.rb")].first
require migration_file

# Run explicitly: TEST_ENV_NUMBER=pr9 bundle exec rspec spec/db/backfill_pattern_feedbacks_user_id_spec.rb
RSpec.describe BackfillPatternFeedbacksUserId, unit: false, migration: true do
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

  def insert_expense(user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    conn.execute(<<~SQL.squish)
      INSERT INTO expenses
        (description, amount, currency, transaction_date, source, user_id, created_at, updated_at)
      VALUES
        ('Test expense', 10.0, 'USD', NOW(), 'manual', #{uid_sql}, NOW(), NOW())
    SQL
    Expense.order(:id).last
  end

  def insert_category
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL.squish)
      INSERT INTO categories (name, created_at, updated_at)
      VALUES (#{conn.quote("TestCat-#{SecureRandom.hex(4)}")}, NOW(), NOW())
    SQL
    Category.order(:id).last
  end

  def insert_pattern_feedback(expense_id:, user_id: nil)
    conn = ActiveRecord::Base.connection
    uid_sql = user_id.nil? ? "NULL" : conn.quote(user_id)
    category = insert_category
    conn.execute(<<~SQL.squish)
      INSERT INTO pattern_feedbacks
        (expense_id, category_id, feedback_type, user_id, created_at, updated_at)
      VALUES
        (#{conn.quote(expense_id)}, #{conn.quote(category.id)},
         'accepted', #{uid_sql}, NOW(), NOW())
    SQL
    PatternFeedback.order(:id).last
  end

  def allow_null_user_id
    ActiveRecord::Base.connection.change_column_null(:pattern_feedbacks, :user_id, true)
  end

  def enforce_not_null_user_id
    ActiveRecord::Base.connection.change_column_null(:pattern_feedbacks, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute(
      "UPDATE pattern_feedbacks SET user_id = (SELECT id FROM users WHERE role = 1 ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    )
    ActiveRecord::Base.connection.change_column_null(:pattern_feedbacks, :user_id, false)
  end

  def cleanup
    PatternFeedback.delete_all
    Category.delete_all
    Expense.delete_all
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

      it "inherits user_id from the associated expense" do
        other_user = insert_user(email: "owner@example.com", role: 0)
        expense    = insert_expense(user_id: other_user.id)
        feedback   = insert_pattern_feedback(expense_id: expense.id)

        migration.up

        expect(feedback.reload.user_id).to eq(other_user.id)
      end

      it "falls back to admin user when expense has no user_id" do
        expense  = insert_expense(user_id: nil)
        feedback = insert_pattern_feedback(expense_id: expense.id)

        migration.up

        expect(feedback.reload.user_id).to eq(admin_user.id)
      end

      it "does not overwrite already-assigned user_id values" do
        other_user       = insert_user(email: "other@example.com", role: 0)
        expense          = insert_expense(user_id: admin_user.id)
        assigned_expense = insert_expense(user_id: other_user.id)
        assigned         = insert_pattern_feedback(expense_id: assigned_expense.id, user_id: other_user.id)
        null_feedback    = insert_pattern_feedback(expense_id: expense.id)

        migration.up

        expect(assigned.reload.user_id).to eq(other_user.id)
        expect(null_feedback.reload.user_id).to eq(admin_user.id)
      end

      it "handles zero pattern_feedbacks gracefully (no-op)" do
        expect { migration.up }.not_to raise_error
      end

      it "is idempotent — running twice does not change user_id" do
        expense  = insert_expense(user_id: admin_user.id)
        feedback = insert_pattern_feedback(expense_id: expense.id, user_id: admin_user.id)

        migration.up
        migration.up

        expect(feedback.reload.user_id).to eq(admin_user.id)
      end
    end
  end

  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
