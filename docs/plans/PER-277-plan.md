# PER-277: Duplicate Expense Race Condition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Use TDD for every task.

**Goal:** Prevent duplicate expense creation when concurrent email-sync jobs process the same transaction, using a three-layer defense: advisory lock (serialize), unique DB constraint (enforce), RecordNotUnique rescue (recover).

**Architecture:** Two `create_expense` methods exist — `Services::EmailProcessing::Parser#create_expense` (with ±1 day soft duplicate check) and `Services::Email::ProcessingService#create_expense` (no duplicate check). Both need advisory lock protection. A unique partial index on `expenses(email_account_id, amount, transaction_date, merchant_name)` WHERE `deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NOT NULL` is the DB-level guarantee. The existing ±1 day range check in Parser stays as a separate business rule for near-duplicate detection.

**Tech Stack:** Rails 8.1.2, PostgreSQL (pg_advisory_xact_lock), RSpec

**Design decisions:**
1. **Keep ±1 day soft check** — the unique index enforces exact-match, the ±1 day range stays as a business-rule near-duplicate detector (Option A)
2. **Protect both create_expense methods** — advisory lock + RecordNotUnique rescue in both Parser and ProcessingService (Option A)
3. **Lock key includes merchant_name** — matches the unique index exactly for narrower locking (Option A)
4. **No gem** — use raw `pg_advisory_xact_lock` via `ActiveRecord::Base.connection.execute`
5. **No model-level validates_uniqueness_of** — redundant with DB constraint + advisory lock, and adds its own race window

**Risks:**
- Existing duplicate data must be cleaned before unique index creation (migration handles this)
- `merchant_name` NULL rows excluded from unique index — advisory lock is the only guard for those
- `transaction_date` is datetime, not date — parser must normalize to date precision for consistent dedup
- Migration must use `disable_ddl_transaction!` + `algorithm: :concurrently`

**Out of scope:**
- Refactoring the two `create_expense` methods into a shared implementation (scope creep — separate ticket)
- Fixing the `processing_service.rb` lack of near-duplicate detection (different concern)
- SoftDelete#restore! collision handling (flagged as existing gap, separate ticket)

---

### Task 1: DB Migration — Unique Partial Index

**Files:**
- Create: `db/migrate/TIMESTAMP_replace_duplicate_check_index_per277.rb`
- Auto-updated: `db/schema.rb`
- Test: `spec/db/duplicate_expense_constraint_spec.rb`

**Context:** Replace the non-unique `idx_expenses_duplicate_check` with a unique partial index. Must handle existing duplicate data first. Uses `disable_ddl_transaction!` + `algorithm: :concurrently` per project convention.

- [ ] **Step 1: Write the failing test**

  Create `spec/db/duplicate_expense_constraint_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require "rails_helper"

  RSpec.describe "Duplicate expense unique constraint", type: :model, unit: true do
    let(:email_account) { create(:email_account) }
    let(:transaction_date) { Time.zone.parse("2026-03-15 12:00:00") }

    describe "unique partial index idx_expenses_duplicate_check" do
      it "prevents inserting two active expenses with same account, amount, date, and merchant" do
        create(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber",
          status: :processed
        )

        duplicate = build(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber",
          status: :pending
        )

        expect { duplicate.save!(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "allows inserting when the existing record is soft-deleted" do
        existing = create(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )
        existing.update_columns(deleted_at: 1.hour.ago)

        new_expense = build(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        expect { new_expense.save!(validate: false) }.not_to raise_error
      end

      it "allows inserting when merchant_name is NULL (excluded from index)" do
        create(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: nil
        )

        duplicate = build(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: nil
        )

        expect { duplicate.save!(validate: false) }.not_to raise_error
      end

      it "allows inserting when email_account_id is NULL (manual expense)" do
        create(:expense,
          email_account: nil,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        duplicate = build(:expense,
          email_account: nil,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        expect { duplicate.save!(validate: false) }.not_to raise_error
      end

      it "allows different amounts for same account, date, and merchant" do
        create(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        different_amount = build(:expense,
          email_account: email_account,
          amount: 30.00,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        expect { different_amount.save!(validate: false) }.not_to raise_error
      end

      it "allows different merchants for same account, date, and amount" do
        create(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Uber"
        )

        different_merchant = build(:expense,
          email_account: email_account,
          amount: 25.50,
          transaction_date: transaction_date,
          merchant_name: "Lyft"
        )

        expect { different_merchant.save!(validate: false) }.not_to raise_error
      end
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `bundle exec rspec spec/db/duplicate_expense_constraint_spec.rb --tag unit`
  Expected: FAIL — first test should NOT raise RecordNotUnique (constraint doesn't exist yet)

- [ ] **Step 3: Write the migration**

  Generate: `bin/rails generate migration ReplaceDuplicateCheckIndexPer277`

  ```ruby
  # frozen_string_literal: true

  class ReplaceDuplicateCheckIndexPer277 < ActiveRecord::Migration[8.1]
    disable_ddl_transaction!

    def up
      # Step 1: Mark existing duplicates before adding unique constraint
      say_with_time "Marking duplicate expenses before adding unique constraint..." do
        execute <<~SQL
          WITH ranked_dupes AS (
            SELECT
              id,
              ROW_NUMBER() OVER (
                PARTITION BY email_account_id, amount, transaction_date, merchant_name
                ORDER BY created_at ASC
              ) AS rn
            FROM expenses
            WHERE deleted_at IS NULL
              AND email_account_id IS NOT NULL
              AND merchant_name IS NOT NULL
          ),
          dupe_ids AS (
            SELECT id FROM ranked_dupes WHERE rn > 1
          )
          UPDATE expenses
          SET status = 3
          WHERE id IN (SELECT id FROM dupe_ids)
            AND status != 3;
        SQL
      end

      # Step 2: Drop the old non-unique index
      if index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
        remove_index :expenses, name: "idx_expenses_duplicate_check", algorithm: :concurrently
      end

      # Step 3: Create unique partial index
      unless index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
        add_index :expenses,
                  %i[email_account_id amount transaction_date merchant_name],
                  name: "idx_expenses_duplicate_check",
                  unique: true,
                  where: "deleted_at IS NULL AND merchant_name IS NOT NULL AND email_account_id IS NOT NULL",
                  algorithm: :concurrently,
                  comment: "Unique partial index preventing duplicate email-sourced expenses (PER-277)"
      end
    end

    def down
      if index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
        remove_index :expenses, name: "idx_expenses_duplicate_check", algorithm: :concurrently
      end

      unless index_exists?(:expenses, %i[email_account_id amount transaction_date merchant_name], name: "idx_expenses_duplicate_check")
        add_index :expenses,
                  %i[email_account_id amount transaction_date merchant_name],
                  name: "idx_expenses_duplicate_check",
                  algorithm: :concurrently,
                  comment: "Index for detecting duplicate transactions"
      end
    end
  end
  ```

- [ ] **Step 4: Run migration**

  Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate`

- [ ] **Step 5: Run test to verify it passes**

  Run: `bundle exec rspec spec/db/duplicate_expense_constraint_spec.rb --tag unit`
  Expected: PASS — all 6 tests green

- [ ] **Step 6: Commit**

  ```bash
  git add db/migrate/*_replace_duplicate_check_index_per277.rb db/schema.rb spec/db/duplicate_expense_constraint_spec.rb
  git commit -m "🗃️ fix(db): replace duplicate check index with unique partial constraint (PER-277)"
  ```

---

### Task 2: Advisory Lock + RecordNotUnique in Parser#create_expense

**Files:**
- Modify: `app/services/email_processing/parser.rb`
- Test: `spec/services/email_processing/unit/parser_duplicate_detection_spec.rb`

**Context:** Wrap the check-then-insert in `create_expense` with a transaction-scoped advisory lock. Add `RecordNotUnique` rescue as defense-in-depth. The lock key uses `(email_account_id, amount, transaction_date, merchant_name)` to match the unique index. The existing ±1 day `find_duplicate_expense` stays as-is — it's a business rule for near-duplicates.

- [ ] **Step 1: Write failing tests**

  Add to `spec/services/email_processing/unit/parser_duplicate_detection_spec.rb`:

  ```ruby
  describe "#create_expense advisory lock protection" do
    let(:parsed_data) do
      {
        amount: BigDecimal("25.50"),
        transaction_date: Date.new(2026, 3, 15),
        merchant_name: "Uber",
        description: "Ride to airport"
      }
    end

    it "acquires pg_advisory_xact_lock before duplicate check" do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(connection).to receive(:execute)
      allow(parser).to receive(:find_duplicate_expense).and_return(nil)

      expense = instance_double(Expense, save: true, persisted?: true)
      allow(Expense).to receive(:new).and_return(expense)
      allow(expense).to receive(:update)
      allow(expense).to receive(:category=)
      allow(expense).to receive(:formatted_amount).and_return("$25.50")

      parser.send(:create_expense, parsed_data)

      expect(connection).to have_received(:execute)
        .with(/SELECT pg_advisory_xact_lock/)
    end

    it "rescues ActiveRecord::RecordNotUnique and returns existing duplicate" do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(connection).to receive(:execute)
      allow(parser).to receive(:find_duplicate_expense).and_return(nil)

      expense = instance_double(Expense)
      allow(Expense).to receive(:new).and_return(expense)
      allow(expense).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      existing = instance_double(Expense, update: true)
      allow(Expense).to receive(:where).and_return(double(first: existing))

      result = parser.send(:create_expense, parsed_data)

      expect(existing).to have_received(:update).with(status: :duplicate)
      expect(result).to eq(existing)
    end

    it "skips advisory lock when email_account is nil" do
      allow(parser).to receive(:email_account).and_return(nil)
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

      allow(parser).to receive(:find_duplicate_expense).and_return(nil)
      expense = instance_double(Expense, save: true, persisted?: true)
      allow(Expense).to receive(:new).and_return(expense)
      allow(expense).to receive(:update)
      allow(expense).to receive(:category=)
      allow(expense).to receive(:formatted_amount).and_return("$25.50")

      parser.send(:create_expense, parsed_data)

      expect(connection).not_to have_received(:execute)
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `bundle exec rspec spec/services/email_processing/unit/parser_duplicate_detection_spec.rb --tag unit -e "advisory lock"`
  Expected: FAIL — advisory lock not implemented yet

- [ ] **Step 3: Implement advisory lock in Parser#create_expense**

  Modify `app/services/email_processing/parser.rb`:

  Add private helper method:

  ```ruby
  def advisory_lock_key(email_account_id, amount, transaction_date, merchant_name)
    raw = "#{email_account_id}:#{amount}:#{transaction_date.to_date}:#{merchant_name.to_s.downcase.strip}"
    Digest::SHA256.hexdigest(raw).to_i(16) % (2**63 - 1)
  end

  def acquire_expense_advisory_lock(parsed_data)
    return unless email_account

    lock_key = advisory_lock_key(
      email_account.id,
      parsed_data[:amount],
      parsed_data[:transaction_date],
      parsed_data[:merchant_name]
    )
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_xact_lock(#{lock_key})"
    )
  end
  ```

  Modify `create_expense` to wrap in transaction with advisory lock:

  ```ruby
  def create_expense(parsed_data)
    ActiveRecord::Base.transaction do
      acquire_expense_advisory_lock(parsed_data)

      begin
        existing_expense = find_duplicate_expense(parsed_data)
      rescue ActiveRecord::RecordNotFound, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementTimeout => e
        add_error("Database error during duplicate check: #{e.message}")
        return nil
      end

      if existing_expense
        existing_expense.update(status: :duplicate)
        add_error("Duplicate expense found")
        return existing_expense
      end

      expense = Expense.new(
        email_account: email_account,
        amount: parsed_data[:amount],
        transaction_date: parsed_data[:transaction_date],
        merchant_name: parsed_data[:merchant_name],
        description: parsed_data[:description],
        raw_email_content: email_content,
        parsed_data: parsed_data.to_json,
        status: :pending,
        email_body: email_data[:body].to_s,
        bank_name: email_account&.bank_name
      )

      begin
        set_currency(expense, parsed_data)
      rescue StandardError => e
        add_error("Currency detection failed: #{e.message}")
      end

      begin
        expense.category = guess_category(expense)
      rescue StandardError => e
        add_error("Category guess failed: #{e.message}")
      end

      if expense.save
        expense.update(status: :processed)
        Rails.logger.info "Created expense: #{expense.formatted_amount} from #{email_account.email}"
        expense
      else
        add_error("Failed to save expense: #{expense.errors.full_messages.join(", ")}")
        nil
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Unique constraint caught a race condition — find and return the winner
    existing = Expense.where(
      email_account: email_account,
      amount: parsed_data[:amount],
      transaction_date: parsed_data[:transaction_date],
      merchant_name: parsed_data[:merchant_name]
    ).first

    if existing
      existing.update(status: :duplicate)
      add_error("Duplicate expense found")
      existing
    else
      add_error("Duplicate constraint violation but original record not found")
      nil
    end
  end
  ```

- [ ] **Step 4: Run tests to verify they pass**

  Run: `bundle exec rspec spec/services/email_processing/unit/parser_duplicate_detection_spec.rb --tag unit`
  Expected: PASS — all existing tests + new advisory lock tests pass

- [ ] **Step 5: Commit**

  ```bash
  git add app/services/email_processing/parser.rb spec/services/email_processing/unit/parser_duplicate_detection_spec.rb
  git commit -m "🔒 fix(parser): add advisory lock and RecordNotUnique rescue to create_expense (PER-277)"
  ```

---

### Task 3: Advisory Lock + RecordNotUnique in ProcessingService#create_expense

**Files:**
- Modify: `app/services/email/processing_service.rb`
- Test: `spec/services/email/processing_service/expense_creation_spec.rb`

**Context:** The second `create_expense` at `processing_service.rb:403` has zero duplicate protection. Add the same advisory lock + RecordNotUnique pattern. This method uses `save!` (bang), so RecordNotUnique will propagate unless rescued.

- [ ] **Step 1: Write failing tests**

  Create or update `spec/services/email/processing_service/expense_creation_spec.rb` with advisory lock tests:

  ```ruby
  describe "#create_expense advisory lock protection" do
    let(:expense_data) do
      {
        amount: "25.50",
        description: "Ride to airport",
        date: Date.new(2026, 3, 15),
        merchant: "Uber",
        currency: "usd",
        raw_text: "raw email text"
      }
    end

    it "acquires pg_advisory_xact_lock before saving" do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(connection).to receive(:execute)

      expense = instance_double(Expense, persisted?: true, id: 1, reload: nil)
      allow(email_account).to receive_message_chain(:expenses, :build).and_return(expense)
      allow(expense).to receive(:save!)

      service.send(:create_expense, expense_data)

      expect(connection).to have_received(:execute)
        .with(/SELECT pg_advisory_xact_lock/)
    end

    it "rescues ActiveRecord::RecordNotUnique and returns nil" do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(connection).to receive(:execute)

      expense = instance_double(Expense)
      allow(email_account).to receive_message_chain(:expenses, :build).and_return(expense)
      allow(expense).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      result = service.send(:create_expense, expense_data)

      expect(result).to be_nil
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `bundle exec rspec spec/services/email/processing_service/expense_creation_spec.rb --tag unit -e "advisory lock"`
  Expected: FAIL

- [ ] **Step 3: Implement advisory lock in ProcessingService#create_expense**

  Modify `app/services/email/processing_service.rb`:

  Add the same `advisory_lock_key` helper (private):

  ```ruby
  def advisory_lock_key(email_account_id, amount, transaction_date, merchant_name)
    raw = "#{email_account_id}:#{amount}:#{transaction_date.to_date}:#{merchant_name.to_s.downcase.strip}"
    Digest::SHA256.hexdigest(raw).to_i(16) % (2**63 - 1)
  end
  ```

  Modify `create_expense`:

  ```ruby
  def create_expense(expense_data)
    # Acquire advisory lock to serialize concurrent inserts for same expense
    lock_key = advisory_lock_key(
      email_account.id,
      expense_data[:amount],
      expense_data[:date],
      expense_data[:merchant]
    )
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_xact_lock(#{lock_key})"
    )

    expense = email_account.expenses.build(
      amount: expense_data[:amount],
      description: expense_data[:description],
      transaction_date: expense_data[:date] || Date.current,
      merchant_name: expense_data[:merchant],
      merchant_normalized: expense_data[:merchant]&.downcase&.strip,
      currency: expense_data[:currency]&.downcase || "usd",
      raw_email_content: expense_data[:raw_text],
      bank_name: email_account.bank_name,
      status: "pending"
    )

    expense.save!

    if options[:auto_categorize]
      category = suggest_category(expense)
      if category
        begin
          expense.reload.update!(
            category: category,
            auto_categorized: true,
            categorization_confidence: last_categorization_confidence,
            categorization_method: last_categorization_method,
            categorized_at: Time.current
          )
        rescue ActiveRecord::StaleObjectError
          Rails.logger.warn "Skipped auto-categorization for expense #{expense.id} due to concurrent modification"
        end
      end
    end

    expense
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn "[EmailProcessing] Duplicate expense rejected by DB constraint: " \
                      "account=#{email_account.id} amount=#{expense_data[:amount]} " \
                      "date=#{expense_data[:date]} merchant=#{expense_data[:merchant]}"
    nil
  end
  ```

  Also update the caller to handle nil return — find the line that calls `create_expense` and ensure it uses safe navigation (`expense&.persisted?` or nil check).

- [ ] **Step 4: Run tests to verify they pass**

  Run: `bundle exec rspec spec/services/email/processing_service/ --tag unit`
  Expected: PASS

- [ ] **Step 5: Commit**

  ```bash
  git add app/services/email/processing_service.rb spec/services/email/processing_service/expense_creation_spec.rb
  git commit -m "🔒 fix(email): add advisory lock and RecordNotUnique rescue to ProcessingService#create_expense (PER-277)"
  ```

---

### Task 4: Integration Test — Concurrent Duplicate Prevention

**Files:**
- Create: `spec/services/email_processing/unit/parser_concurrent_spec.rb`
- Modify: `spec/db/duplicate_expense_constraint_spec.rb` (if needed)

**Context:** Verify end-to-end that the advisory lock + unique constraint actually prevents duplicate creation under concurrent access. This uses real DB (not mocks) to test the constraint.

- [ ] **Step 1: Write the concurrent access test**

  Create `spec/services/email_processing/unit/parser_concurrent_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require "rails_helper"

  RSpec.describe "Concurrent duplicate expense prevention", type: :model, unit: true do
    let(:email_account) { create(:email_account) }

    it "creates exactly one expense when two threads attempt the same insert" do
      transaction_date = Time.zone.parse("2026-03-15 12:00:00")
      results = []
      errors = []

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            expense = Expense.new(
              email_account: email_account,
              amount: 25.50,
              transaction_date: transaction_date,
              merchant_name: "Uber",
              description: "Ride",
              status: :pending
            )
            expense.save!
            results << expense
          rescue ActiveRecord::RecordNotUnique => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      expect(results.size + errors.size).to eq(2)
      expect(results.size).to eq(1)
      expect(errors.size).to eq(1)

      expect(Expense.where(
        email_account: email_account,
        amount: 25.50,
        transaction_date: transaction_date,
        merchant_name: "Uber"
      ).count).to eq(1)
    end
  end
  ```

- [ ] **Step 2: Run test**

  Run: `bundle exec rspec spec/services/email_processing/unit/parser_concurrent_spec.rb --tag unit`
  Expected: PASS — unique constraint prevents the second insert

- [ ] **Step 3: Run full affected spec suites for regressions**

  Run: `bundle exec rspec spec/services/email_processing/ spec/services/email/ spec/db/ --tag unit`
  Expected: PASS — all existing tests still pass

- [ ] **Step 4: Commit**

  ```bash
  git add spec/services/email_processing/unit/parser_concurrent_spec.rb
  git commit -m "✅ test(concurrency): add concurrent duplicate prevention spec (PER-277)"
  ```

---

## Verification Script

After all tasks, run this verification:

```bash
#!/bin/bash
echo "=== PER-277 Verification ==="

echo "1. Checking unique index exists..."
bin/rails runner "
  idx = ActiveRecord::Base.connection.indexes(:expenses).find { |i| i.name == 'idx_expenses_duplicate_check' }
  puts idx ? \"PASS: Index exists, unique=#{idx.unique}\" : 'FAIL: Index not found'
  puts idx&.unique ? 'PASS: Index is unique' : 'FAIL: Index is not unique'
  puts idx&.where&.include?('deleted_at IS NULL') ? 'PASS: Partial index excludes soft-deleted' : 'FAIL: Missing partial condition'
"

echo "2. Checking advisory lock in Parser..."
grep -n "pg_advisory_xact_lock" app/services/email_processing/parser.rb && echo "PASS" || echo "FAIL"

echo "3. Checking advisory lock in ProcessingService..."
grep -n "pg_advisory_xact_lock" app/services/email/processing_service.rb && echo "PASS" || echo "FAIL"

echo "4. Checking RecordNotUnique rescue in Parser..."
grep -n "RecordNotUnique" app/services/email_processing/parser.rb && echo "PASS" || echo "FAIL"

echo "5. Checking RecordNotUnique rescue in ProcessingService..."
grep -n "RecordNotUnique" app/services/email/processing_service.rb && echo "PASS" || echo "FAIL"

echo "6. Running all affected specs..."
bundle exec rspec spec/db/duplicate_expense_constraint_spec.rb spec/services/email_processing/unit/parser_duplicate_detection_spec.rb spec/services/email_processing/unit/parser_concurrent_spec.rb --tag unit --format progress

echo "=== Done ==="
```
