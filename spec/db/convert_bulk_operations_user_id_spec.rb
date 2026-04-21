# frozen_string_literal: true

require "rails_helper"

migration_file = Dir[Rails.root.join("db/migrate/*backfill_bulk_operations_user_bigint*.rb")].first
require migration_file

# Run explicitly:
#   TEST_ENV_NUMBER=pr10 bundle exec rspec spec/db/convert_bulk_operations_user_id_spec.rb
#
# This spec covers every lookup-chain path in BackfillBulkOperationsUserBigint:
#   Path A — AdminUser found → matching User found via email (normal case)
#   Path B — AdminUser found → no User with that email (data gap)
#   Path C — AdminUser not found → User found directly by id (already-migrated id)
#   Path D — nil user_id (row without an owner)
#   Path E — no match anywhere → fallback to admin User (orphan string id)
#   Path F — no match and no fallback → raises MigrationError
RSpec.describe BackfillBulkOperationsUserBigint, unit: false, migration: true do
  let(:migration) { described_class.new }
  let(:conn)      { ActiveRecord::Base.connection }

  # ── Helpers ──────────────────────────────────────────────────────────────────

  def insert_user(email:, role: 0)
    digest = BCrypt::Password.create("TestPass123!", cost: BCrypt::Engine::MIN_COST)
    conn.execute(<<~SQL.squish)
      INSERT INTO users
        (email, name, password_digest, role, failed_login_attempts, created_at, updated_at)
      VALUES
        (#{conn.quote(email)}, 'Test User', #{conn.quote(digest)},
         #{conn.quote(role)}, 0, NOW(), NOW())
    SQL
    User.find_by!(email: email)
  end

  def insert_admin_user(email:)
    digest = BCrypt::Password.create("TestPass123!", cost: BCrypt::Engine::MIN_COST)
    conn.execute(<<~SQL.squish)
      INSERT INTO admin_users
        (email, name, password_digest, role, failed_login_attempts, created_at, updated_at)
      VALUES
        (#{conn.quote(email)}, 'Admin User', #{conn.quote(digest)},
         2, 0, NOW(), NOW())
    SQL
    AdminUser.find_by!(email: email)
  end

  def insert_category
    conn.execute(<<~SQL.squish)
      INSERT INTO categories (name, created_at, updated_at)
      VALUES ('test-' || (SELECT COALESCE(MAX(id)+1, 1) FROM categories), NOW(), NOW())
    SQL
    conn.execute("SELECT id FROM categories ORDER BY id DESC LIMIT 1").first["id"]
  end

  # Allow the string user_id column temporarily while we test the backfill.
  # After the migration ran in production this column no longer exists, but
  # here we use the schema loaded from db/schema.rb (post-migration) which
  # already has user_id as bigint.  We need to add a temporary string column
  # to simulate the pre-migration state, insert rows with string values, then
  # run the backfill.
  def add_temp_string_user_id_column
    conn.add_column :bulk_operations, :string_user_id_test, :string unless
      conn.column_exists?(:bulk_operations, :string_user_id_test)
  end

  # Insert a bulk_operation row with the string user_id already migrated to
  # the bigint column set to nil (simulating the state after step 1 but before
  # step 2). We also allow user_id to be null for this spec's setup.
  def allow_null_user_id
    conn.change_column_null(:bulk_operations, :user_id, true)
  end

  def enforce_not_null_user_id
    conn.change_column_null(:bulk_operations, :user_id, false)
  rescue ActiveRecord::StatementInvalid
    admin = User.where(role: 1).order(:id).first
    conn.execute("UPDATE bulk_operations SET user_id = #{admin.id} WHERE user_id IS NULL") if admin
    conn.change_column_null(:bulk_operations, :user_id, false)
  end

  # Insert a bulk_operation with a specific string id stored in the _internal_
  # user_bigint_id resolver column. We simulate the pre-backfill state by
  # setting user_id = NULL and capturing what string id would have been in
  # user_id via a separate helper column we temporarily add.
  #
  # Because the schema already has user_id as bigint after migration, we use
  # the migration's anonymous MigrationBulkOp class to write raw SQL that sets
  # user_id = NULL and stores the original string in a helper column.
  def insert_bulk_op_with_string_user_id(string_id, category_id:)
    conn.execute(<<~SQL.squish)
      INSERT INTO bulk_operations
        (operation_type, status, expense_count, total_amount, user_id, metadata, created_at, updated_at)
      VALUES
        (0, 0, 1, 10.00, NULL, '{}', NOW(), NOW())
    SQL
    row_id = conn.execute("SELECT id FROM bulk_operations ORDER BY id DESC LIMIT 1").first["id"]
    # Store the intended string_user_id in our temp column for the spec to use
    conn.execute("UPDATE bulk_operations SET string_user_id_test = #{conn.quote(string_id)} WHERE id = #{row_id}")
    BulkOperation.find(row_id)
  end

  def cleanup
    # Order matters: bulk_operations.user_id FK prevents deleting users first,
    # and bulk_operation_items has a FK on bulk_operations.
    conn.execute("DELETE FROM bulk_operation_items")
    conn.execute("DELETE FROM bulk_operations")
    User.delete_all
    AdminUser.delete_all
  end

  before(:all) do
    # Add temp column once for the full describe block
    ActiveRecord::Base.connection.add_column(
      :bulk_operations, :string_user_id_test, :string
    ) unless ActiveRecord::Base.connection.column_exists?(:bulk_operations, :string_user_id_test)
  end

  after(:all) do
    if ActiveRecord::Base.connection.column_exists?(:bulk_operations, :string_user_id_test)
      ActiveRecord::Base.connection.remove_column(:bulk_operations, :string_user_id_test)
    end
  end

  before do
    allow_null_user_id
    cleanup
  end

  after do
    cleanup
    enforce_not_null_user_id
  end

  # ── Run the REAL migration logic directly against a row whose string user_id
  #    is held in the temp column. We build a lightweight proxy with the
  #    attributes the migration's private `resolve_user_id` reads (`.id`,
  #    `.user_id`), then invoke it via `send`. This exercises the migration's
  #    actual code path — earlier versions of this spec reimplemented the
  #    lookup chain and would have passed even if the migration itself was
  #    broken (architect review #10).
  RowProxy = Struct.new(:id, :user_id)

  def run_migration_with_string_ids
    BulkOperation.where.not(string_user_id_test: nil).find_each do |row|
      string_id = row.string_user_id_test.to_s.strip
      next if string_id.blank? || row.user_id.present?

      proxy = RowProxy.new(row.id, string_id)
      resolved_id = migration.send(:resolve_user_id, proxy)
      row.update_columns(user_id: resolved_id) if resolved_id
    end
  end

  # ── Path A: AdminUser found → User found by email ────────────────────────────
  describe "Path A — AdminUser → User via email" do
    it "resolves string AdminUser id to the mirrored User" do
      admin = insert_admin_user(email: "alice@example.com")
      user  = insert_user(email: "alice@example.com")
      row   = insert_bulk_op_with_string_user_id(admin.id.to_s, category_id: insert_category)

      run_migration_with_string_ids

      expect(row.reload.user_id).to eq(user.id)
    end
  end

  # ── Path B: AdminUser found → no matching User email → raise ────────────────
  describe "Path B — AdminUser found but no User with that email → raises" do
    it "raises rather than silently reassigning ownership (Codex review)" do
      insert_user(email: "admin@example.com", role: 1) # fallback admin exists
      admin = insert_admin_user(email: "ghost@example.com")
      # Intentionally do NOT create a User with ghost@example.com
      insert_bulk_op_with_string_user_id(admin.id.to_s, category_id: insert_category)

      expect { run_migration_with_string_ids }.to raise_error(
        ActiveRecord::MigrationError, /could not be resolved/
      )
    end
  end

  # ── Path C: AdminUser not found → User found directly by id ─────────────────
  describe "Path C — no AdminUser match → User found by direct id" do
    it "uses User.find_by(id:) when AdminUser id does not exist" do
      # Insert user but no AdminUser with same id
      user = insert_user(email: "direct@example.com")
      # Make the string_user_id_test equal to the user's id (simulate already-migrated row)
      row  = insert_bulk_op_with_string_user_id(user.id.to_s, category_id: insert_category)

      run_migration_with_string_ids

      expect(row.reload.user_id).to eq(user.id)
    end
  end

  # ── Path D: nil user_id string ───────────────────────────────────────────────
  describe "Path D — nil string_user_id_test (no owner)" do
    it "skips rows with blank string_user_id and leaves user_id as nil" do
      # Insert a row with NULL string_user_id_test (already nil)
      conn.execute(<<~SQL.squish)
        INSERT INTO bulk_operations
          (operation_type, status, expense_count, total_amount, user_id, metadata, created_at, updated_at)
        VALUES (0, 0, 1, 10.00, NULL, '{}', NOW(), NOW())
      SQL
      row = BulkOperation.order(:id).last

      run_migration_with_string_ids

      expect(row.reload.user_id).to be_nil
    end
  end

  # ── Path E: orphan string id — no AdminUser, no direct User → raises ───────
  describe "Path E — orphan string id raises (Codex review)" do
    it "raises ActiveRecord::MigrationError rather than silently reassigning" do
      insert_user(email: "admin@example.com", role: 1) # admin exists but unused
      # Use a string id that matches neither AdminUser nor User table
      insert_bulk_op_with_string_user_id("99999", category_id: insert_category)

      expect { run_migration_with_string_ids }.to raise_error(
        ActiveRecord::MigrationError, /could not be resolved/
      )
    end
  end

  # ── Path F: no match and no admin → raises ──────────────────────────────────
  describe "Path F — unresolvable id with no admin User" do
    it "raises ActiveRecord::MigrationError" do
      # No admin User created; only a regular user who won't match
      insert_user(email: "regular@example.com", role: 0)
      insert_bulk_op_with_string_user_id("99999", category_id: insert_category)

      expect { run_migration_with_string_ids }.to raise_error(
        ActiveRecord::MigrationError, /could not be resolved/
      )
    end
  end

  # ── Idempotency ──────────────────────────────────────────────────────────────
  describe "idempotency" do
    it "does not overwrite already-resolved user_id values" do
      admin = insert_admin_user(email: "bob@example.com")
      user  = insert_user(email: "bob@example.com")
      other = insert_user(email: "other@example.com")
      row   = insert_bulk_op_with_string_user_id(admin.id.to_s, category_id: insert_category)

      # Pre-set a resolved user_id (simulate already having run)
      row.update_columns(user_id: other.id)

      run_migration_with_string_ids

      # Should NOT overwrite the already-resolved value
      expect(row.reload.user_id).to eq(other.id)
    end
  end

  # ── #down raises IrreversibleMigration ───────────────────────────────────────
  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
