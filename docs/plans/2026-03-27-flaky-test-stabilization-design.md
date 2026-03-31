# Flaky Test Stabilization Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate 5 flaky tests that block commits ~30% of the time by consolidating DatabaseCleaner configuration, making performance thresholds configurable, and fixing two isolated test bugs.

**Architecture:** Single canonical DatabaseCleaner config using transaction strategy for all tests except system tests (which use deletion). Configurable performance auto-fail threshold via ENV. Targeted fixes for ENV stub and budget test.

**Tech Stack:** RSpec, DatabaseCleaner, Rails 8.1.2 transactional fixtures

---

## Task 1: Create canonical DatabaseCleaner config

**Files:**
- Create: `spec/support/database_cleaner.rb`

**Step 1: Write the new config file**

```ruby
# frozen_string_literal: true

# Canonical DatabaseCleaner configuration.
# Replaces conflicting configs that were spread across 3 files.
#
# Strategy:
#   - Transaction for everything (fast, isolated)
#   - Deletion for system tests (browser needs committed data)
#   - Suite-level deletion excludes seed tables
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:deletion, except: %w[
      ar_internal_metadata schema_migrations categories admin_users
    ])
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :deletion
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
```

**Step 2: Verify file exists and is loadable**

Run: `ruby -c spec/support/database_cleaner.rb`
Expected: `Syntax OK`

---

## Task 2: Remove conflicting DatabaseCleaner configs

**Files:**
- Modify: `spec/support/configs/test_tiers.rb`
- Modify: `spec/support/configs/integration_test_config.rb`
- Modify: `spec/support/performance_optimizations.rb`

**Step 1: Remove from test_tiers.rb**

Remove:
- The `before(:suite)` block containing `DatabaseCleaner.clean_with(:truncation)`
- The `around(:each, :performance)` block that toggles `use_transactional_fixtures` and uses `DatabaseCleaner.cleaning`
- The `around(:each, :system)` block that does the same

Keep: test type auto-tagging logic, performance summary hooks, any non-DatabaseCleaner configuration.

**Step 2: Remove from integration_test_config.rb**

Remove:
- The `before(:each, integration: true)` block that sets `DatabaseCleaner.strategy = :truncation`
- The `after(:each, integration: true)` block that calls `DatabaseCleaner.clean`

Keep: any non-DatabaseCleaner integration test setup.

**Step 3: Remove from performance_optimizations.rb**

Remove:
- The `before(:each, :needs_commit)` block that sets `DatabaseCleaner.strategy = :truncation`
- The `after(:each, :needs_commit)` block that calls `DatabaseCleaner.clean` and resets to `:transaction`

Keep: any non-DatabaseCleaner performance optimizations.

---

## Task 3: Make performance threshold configurable

**Files:**
- Modify: `spec/support/performance_monitor.rb`

**Step 1: Replace hard-coded AUTO_FAIL_THRESHOLD**

Change:
```ruby
AUTO_FAIL_THRESHOLD = 10.0
```

To:
```ruby
AUTO_FAIL_THRESHOLD = ENV.fetch('TEST_AUTO_FAIL_THRESHOLD', 30).to_f
```

**Step 2: Add skip_performance_monitor tag support**

In the `around(:each)` hook (around line 236), add early return:

```ruby
config.around(:each) do |example|
  if example.metadata[:skip_performance_monitor]
    example.run
  else
    # existing timing/recording logic
  end
end
```

**Step 3: Tag the known slow test**

In `spec/services/email/integration/processing_service_integration_spec.rb`, add `skip_performance_monitor: true` to the "maintains reasonable memory usage" example.

---

## Task 4: Fix ENV stub in queue_controller_spec

**Files:**
- Modify: `spec/controllers/api/queue_controller_spec.rb`

**Step 1: Add and_call_original fallback**

At line ~441, before the specific ENV stub, add:

```ruby
allow(ENV).to receive(:[]).and_call_original
```

So the block becomes:
```ruby
allow(ENV).to receive(:[]).and_call_original
allow(ENV).to receive(:[]).with("ADMIN_KEY").and_return(nil)
```

---

## Task 5: Fix budget test isolation

**Files:**
- Modify: `spec/models/budget_unit_spec.rb`

**Step 1: Use unique category in concurrent test**

At line ~838, change:
```ruby
budget = create(:budget, email_account: email_account)
```

To:
```ruby
unique_category = create(:category, name: "concurrent-test-#{SecureRandom.hex(4)}")
budget = create(:budget, email_account: email_account, category: unique_category)
```

---

## Task 6: Verify all tests pass

**Step 1: Run full unit suite 3 times with different seeds**

```bash
bundle exec rspec --tag unit --order random --seed 12345
bundle exec rspec --tag unit --order random --seed 54321
bundle exec rspec --tag unit --order random --seed 99999
```

All 3 runs must pass with 0 failures.

**Step 2: Run system tests (if any exist)**

```bash
bundle exec rspec --tag system
```

Verify system tests still work with the new deletion strategy.

**Step 3: Commit**

```bash
git commit -m "🧪 fix(tests): stabilize flaky tests — consolidate DatabaseCleaner, configurable thresholds (PER-FLAKY)"
```
