# QA Remediation Plan - Expense Tracker

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all 110 findings from the QA audit across security, performance, UX, and design — organized into 5 phases from emergency to polish.

**Architecture:** Layered fixes starting with authentication/authorization at the controller level, then performance at the service layer, then UX at the view layer. Each ticket is atomic and independently deployable.

**Tech Stack:** Rails 8.1, PostgreSQL, Redis, ActionCable, Stimulus, Tailwind CSS, RSpec

> **COMMIT CONVENTION REMINDER:** Do NOT include any AI/assistant references in commit messages. Use conventional commits with emojis per project rules. Example: `🔒 fix(auth): add authentication to ApplicationController`

### PR Strategy: Small, Focused Pull Requests

Each phase should produce **one PR per task** (or at most 2-3 tightly related tasks grouped). Small PRs are:
- Easier and faster to review
- Less risky to merge
- Simpler to revert if something breaks
- Better for tracking progress

**PR naming convention:** `qa/<phase>-<task>-<short-description>`
- Example branches: `qa/phase0-auth`, `qa/phase0-csrf`, `qa/phase1-n-plus-one`
- Each PR links back to the relevant finding IDs (S-01, P-3, etc.)
- PRs within a phase can be reviewed and merged independently
- Phase 0 PRs should be merged sequentially (auth first, then others depend on it)
- Phase 1 & 2 PRs can be reviewed in parallel

**PR template:**
```
## Summary
- Fixes: [Finding IDs]
- Phase: [0-5]

## Changes
- [1-3 bullet points]

## Test plan
- [ ] New specs pass
- [ ] Existing specs pass (`bundle exec rspec --tag unit`)
- [ ] Manual verification: [specific check]
```

---

## Phase 0: Emergency Fixes (BEFORE ANY DEPLOYMENT)

These tickets fix critical security vulnerabilities and data-destruction bugs. Each is independently deployable and should be merged immediately.

---

### Task 0.1: Add Authentication to ApplicationController

**Severity:** CRITICAL | **Refs:** S-01, S-12, S-17–S-21, UX-001

**Problem:** `ApplicationController` does not include the `Authentication` concern. Controllers like `EmailAccountsController`, `BudgetsController`, `SyncConflictsController`, `CategoriesController`, and `UndoHistoriesController` inherit from it without any auth — anyone can CRUD email credentials, budgets, and undo operations.

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/admin/sessions_controller.rb` (skip auth for login)
- Modify: `app/controllers/api/v1/base_controller.rb` (skip auth, uses API tokens)
- Modify: `app/controllers/webhooks_controller.rb` (skip auth, uses API tokens)
- Test: `spec/controllers/application_controller_auth_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/controllers/application_controller_auth_spec.rb
require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: "OK"
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users to login" do
      get :index
      expect(response).to redirect_to(admin_login_path)
    end

    it "allows authenticated users" do
      admin = create(:admin_user)
      session[:admin_session_token] = admin.session_token
      get :index
      expect(response).to have_http_status(:ok)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/application_controller_auth_spec.rb -v`
Expected: FAIL — currently no auth redirect happens.

**Step 3: Add Authentication to ApplicationController**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern unless Rails.env.test?
  protect_from_forgery with: :null_session, if: -> { request.format.json? }
end
```

**Step 4: Skip authentication on controllers that handle their own auth**

```ruby
# app/controllers/admin/sessions_controller.rb — add at line 7:
skip_before_action :authenticate_user!

# app/controllers/webhooks_controller.rb — add after class declaration:
skip_before_action :authenticate_user!

# app/controllers/api/v1/base_controller.rb — add after class declaration:
skip_before_action :authenticate_user!
```

**Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/application_controller_auth_spec.rb -v`
Expected: PASS

**Step 6: Run full suite to verify no regressions**

Run: `bundle exec rspec --tag unit`
Expected: All pass (some controller specs may need session setup)

**Step 7: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/admin/sessions_controller.rb app/controllers/webhooks_controller.rb app/controllers/api/v1/base_controller.rb spec/controllers/application_controller_auth_spec.rb
git commit -m "🔒 fix(auth): add authentication to ApplicationController

All controllers now require authentication by default.
Controllers with their own auth (admin login, API, webhooks) skip it explicitly."
```

---

### Task 0.2: Implement SyncAuthorization Ownership Checks

**Severity:** CRITICAL | **Refs:** S-02

**Problem:** Both `sync_access_allowed?` and `sync_session_owner?` in `app/controllers/concerns/sync_authorization.rb` are TODO stubs that always return `true`. Any user can access any sync session.

**Files:**
- Modify: `app/controllers/concerns/sync_authorization.rb:21-26,39-43`
- Test: `spec/controllers/concerns/sync_authorization_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/controllers/concerns/sync_authorization_spec.rb
require "rails_helper"

RSpec.describe SyncAuthorization, type: :controller do
  controller(ApplicationController) do
    include SyncAuthorization

    def index
      render plain: "OK"
    end

    def show
      @sync_session = SyncSession.find(params[:id])
      authorize_sync_session_owner!
      render plain: "OK"
    end
  end

  before do
    routes.draw do
      get "index" => "anonymous#index"
      get "show/:id" => "anonymous#show"
    end
  end

  let(:admin_user) { create(:admin_user) }

  describe "#sync_access_allowed?" do
    it "allows authenticated users" do
      session[:admin_session_token] = admin_user.session_token
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "denies unauthenticated users" do
      get :index
      expect(response).to redirect_to(admin_login_path)
    end
  end

  describe "#sync_session_owner?" do
    it "denies access to sessions owned by other users" do
      other_user = create(:admin_user, email: "other@test.com")
      sync_session = create(:sync_session, user_id: other_user.id)
      session[:admin_session_token] = admin_user.session_token

      get :show, params: { id: sync_session.id }
      expect(response).to redirect_to(sync_sessions_path)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/concerns/sync_authorization_spec.rb -v`
Expected: FAIL — stubs return true

**Step 3: Implement real ownership checks**

```ruby
# app/controllers/concerns/sync_authorization.rb
def sync_access_allowed?
  current_user.present?
end

def sync_session_owner?
  return false unless current_user.present? && @sync_session.present?
  @sync_session.user_id == current_user.id
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/concerns/sync_authorization_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/concerns/sync_authorization.rb spec/controllers/concerns/sync_authorization_spec.rb
git commit -m "🔒 fix(auth): implement real SyncAuthorization ownership checks

Replace TODO stubs with actual user checks.
sync_access_allowed? requires authenticated user.
sync_session_owner? verifies user owns the sync session."
```

---

### Task 0.3: Remove Admin Login CSRF Skip

**Severity:** CRITICAL | **Refs:** S-03

**Problem:** `Admin::SessionsController` line 6 disables CSRF for the `create` action. This enables login CSRF attacks where an attacker forces a victim to log into the attacker's account.

**Files:**
- Modify: `app/controllers/admin/sessions_controller.rb:6` — remove the line
- Test: `spec/controllers/admin/sessions_controller_spec.rb`

**Step 1: Write the failing test**

```ruby
# In the existing sessions_controller_spec, add:
describe "CSRF protection" do
  it "requires CSRF token for login" do
    # ActionController::Base.allow_forgery_protection must be true
    ActionController::Base.allow_forgery_protection = true
    post :create, params: { admin_user: { email: "test@test.com", password: "password" } }
    expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:redirect)
    ActionController::Base.allow_forgery_protection = false
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/admin/sessions_controller_spec.rb -v`
Expected: FAIL — CSRF is currently skipped

**Step 3: Remove the CSRF skip**

In `app/controllers/admin/sessions_controller.rb`, delete line 6:
```ruby
# DELETE this line:
skip_before_action :verify_authenticity_token, only: [ :create ]
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/admin/sessions_controller_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/admin/sessions_controller.rb spec/controllers/admin/sessions_controller_spec.rb
git commit -m "🔒 fix(auth): restore CSRF protection on admin login

Remove skip_before_action :verify_authenticity_token on create.
Login forms include CSRF tokens via Rails form helpers."
```

---

### Task 0.4: Fix API v1 CategoriesController Inheritance

**Severity:** CRITICAL | **Refs:** S-04

**Problem:** `Api::V1::CategoriesController` inherits from `ApplicationController` instead of `Api::V1::BaseController`, bypassing all API authentication (token-based auth).

**Files:**
- Modify: `app/controllers/api/v1/categories_controller.rb:3`
- Test: `spec/controllers/api/v1/categories_controller_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/controllers/api/v1/categories_controller_spec.rb
require "rails_helper"

RSpec.describe Api::V1::CategoriesController, type: :controller do
  describe "GET #index" do
    it "returns unauthorized without API token" do
      get :index, format: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns categories with valid API token" do
      token = create(:api_token)
      request.headers["Authorization"] = "Bearer #{token.token}"
      get :index, format: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/api/v1/categories_controller_spec.rb -v`
Expected: FAIL — no auth required currently

**Step 3: Fix the inheritance**

```ruby
# app/controllers/api/v1/categories_controller.rb
module Api
  module V1
    class CategoriesController < BaseController
      def index
        categories = Category.all.order(:name)
        render json: categories.map { |c|
          {
            id: c.id,
            name: c.name,
            color: c.color,
            description: c.description
          }
        }
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/api/v1/categories_controller_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/api/v1/categories_controller.rb spec/controllers/api/v1/categories_controller_spec.rb
git commit -m "🔒 fix(api): fix CategoriesController to inherit from BaseController

Was inheriting from ApplicationController, bypassing API token auth.
Now requires valid Bearer token like all other API endpoints."
```

---

### Task 0.5: Replace PatternCache flushdb with Namespaced Deletion

**Severity:** CRITICAL | **Refs:** P-3

**Problem:** `PatternCache#invalidate_all` at line 233 calls `redis_client.flushdb`, which destroys the ENTIRE Redis database — not just pattern cache keys. This wipes all cached metrics, Solid Cache data, Solid Queue jobs, and ActionCable sessions.

**Files:**
- Modify: `app/services/categorization/pattern_cache.rb:228-240`
- Test: `spec/services/categorization/pattern_cache_spec.rb`

**Step 1: Write the failing test**

```ruby
# In spec/services/categorization/pattern_cache_spec.rb, add:
describe "#invalidate_all" do
  it "only deletes pattern cache keys, not all Redis data" do
    # Set a non-pattern-cache key
    redis = Redis.new
    redis.set("other:important:key", "preserve_me")

    # Set a pattern cache key
    described_class.instance.store_pattern("test_merchant", create(:category))

    # Invalidate all pattern cache
    described_class.instance.invalidate_all

    # Verify other keys were NOT destroyed
    expect(redis.get("other:important:key")).to eq("preserve_me")
    redis.del("other:important:key")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/categorization/pattern_cache_spec.rb -v`
Expected: FAIL — flushdb destroys everything

**Step 3: Replace flushdb with namespaced SCAN + DEL**

```ruby
# app/services/categorization/pattern_cache.rb — replace invalidate_all method:
def invalidate_all
  @lock.synchronize do
    @memory_cache.clear

    if @redis_available
      cursor = "0"
      loop do
        cursor, keys = redis_client.scan(cursor, match: "#{CACHE_PREFIX}*", count: 100)
        redis_client.del(*keys) if keys.any?
        break if cursor == "0"
      end
    end

    Rails.logger.info "[PatternCache] All pattern caches cleared"
  end
rescue => e
  Rails.logger.error "[PatternCache] Error clearing caches: #{e.message}"
end
```

Note: You'll need to check what `CACHE_PREFIX` is. Look for the constant in the class — if it doesn't exist, define it as `"pattern_cache:"` and ensure all Redis keys in this class use it.

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/categorization/pattern_cache_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/categorization/pattern_cache.rb spec/services/categorization/pattern_cache_spec.rb
git commit -m "🐛 fix(cache): replace flushdb with namespaced key deletion

PatternCache.invalidate_all was calling redis_client.flushdb which
destroys the entire Redis database. Now uses SCAN + DEL with the
pattern cache prefix to only delete pattern-related keys."
```

---

### Task 0.6: Fix Manual Expense Creation Form

**Severity:** CRITICAL | **Refs:** UX-002

**Problem:** The expense form offers "Entrada manual" (blank `email_account_id`) but `belongs_to :email_account` is required on the model. Selecting manual entry always fails validation.

**Files:**
- Modify: `app/models/expense.rb` — make `email_account` optional
- Modify: `app/views/expenses/_form.html.erb:65-68` — keep the blank option
- Test: `spec/models/expense_spec.rb`

**Step 1: Write the failing test**

```ruby
# In spec/models/expense_spec.rb, add:
describe "manual entry" do
  it "allows creation without email_account (manual entry)" do
    expense = build(:expense, email_account: nil, merchant_name: "Manual", amount: 100)
    expect(expense).to be_valid
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/expense_spec.rb -v`
Expected: FAIL — `email_account must exist`

**Step 3: Make email_account optional**

In `app/models/expense.rb`, change:
```ruby
# FROM:
belongs_to :email_account
# TO:
belongs_to :email_account, optional: true
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/expense_spec.rb -v`
Expected: PASS

**Step 5: Run full suite to check for regressions**

Run: `bundle exec rspec --tag unit`
Expected: All pass

**Step 6: Commit**

```bash
git add app/models/expense.rb spec/models/expense_spec.rb
git commit -m "🐛 fix(model): allow manual expense creation without email account

Make belongs_to :email_account optional so the 'Entrada manual'
form option works. Manual expenses have nil email_account_id."
```

---

### Task 0.7: Remove WebSocket SecureRandom Session Fallback

**Severity:** CRITICAL | **Refs:** S-10

**Problem:** `ApplicationCable::Connection#extract_session_id` at line 58 uses `SecureRandom.hex(16)` as a fallback when no session ID is found. This accepts unauthenticated connections with random session IDs.

**Files:**
- Modify: `app/channels/application_cable/connection.rb:58`
- Test: `spec/channels/connection_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/channels/connection_spec.rb
require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  describe "#connect" do
    it "rejects connection when session has no session_id" do
      # Simulate a hash with no session_id key
      cookies.encrypted[:_expense_tracker_session] = { "some_other_key" => "value" }
      expect { connect }.to have_rejected_connection
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/channels/connection_spec.rb -v`
Expected: FAIL — currently generates random ID instead of rejecting

**Step 3: Remove the SecureRandom fallback**

```ruby
# app/channels/application_cable/connection.rb — line 58, change:
# FROM:
session_data["session_id"] || session_data[:session_id] || SecureRandom.hex(16)
# TO:
session_data["session_id"] || session_data[:session_id]
```

This makes `extract_session_id` return `nil` when no session ID exists, which causes `find_verified_session` to call `reject_unauthorized_connection`.

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/channels/connection_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/channels/application_cable/connection.rb spec/channels/connection_spec.rb
git commit -m "🔒 fix(websocket): remove SecureRandom session ID fallback

Connections without a valid session_id are now rejected instead
of being accepted with a random ID. Prevents unauthenticated
WebSocket connections."
```

---

## Phase 1: Critical Performance

These tickets fix the biggest performance bottlenecks — N+1 queries, duplicated calculations, and debug code left in production.

---

### Task 1.1: Pass Metrics to calculate_trends (Eliminate Double Calculation)

**Severity:** CRITICAL | **Refs:** P-1

**Problem:** `MetricsCalculator#calculate_trends` at line 242 calls `calculate_metrics` again, even though `calculate` at line 38 already called it on line 38. This doubles all the aggregation queries.

**Files:**
- Modify: `app/services/metrics_calculator.rb:31-46,241-258`
- Test: `spec/services/metrics_calculator_spec.rb`

**Step 1: Write the failing test**

```ruby
# In spec/services/metrics_calculator_spec.rb, add:
describe "#calculate" do
  it "does not call calculate_metrics more than once" do
    calculator = described_class.new(email_account: email_account)
    expect(calculator).to receive(:calculate_metrics).once.and_call_original
    calculator.calculate
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: FAIL — `calculate_metrics` called twice

**Step 3: Pass metrics to calculate_trends**

```ruby
# app/services/metrics_calculator.rb — modify calculate method:
def calculate
  Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
    benchmark_calculation do
      metrics = calculate_metrics
      {
        period: period,
        reference_date: reference_date,
        date_range: date_range,
        metrics: metrics,
        trends: calculate_trends(metrics),
        category_breakdown: calculate_category_breakdown,
        daily_breakdown: calculate_daily_breakdown,
        trend_data: calculate_trend_data,
        budgets: calculate_budget_data,
        calculated_at: Time.current
      }
    end
  end
rescue StandardError => e
  handle_calculation_error(e)
end

# Modify calculate_trends to accept pre-calculated metrics:
def calculate_trends(current_metrics = nil)
  current_metrics ||= calculate_metrics
  previous_expenses = expenses_in_previous_period
  # ... rest stays the same, using current_metrics parameter
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/metrics_calculator.rb spec/services/metrics_calculator_spec.rb
git commit -m "⚡ perf(metrics): eliminate double calculation in calculate_trends

Pass pre-calculated metrics to calculate_trends instead of
recalculating. Reduces dashboard query count by ~40%."
```

---

### Task 1.2: Fix N+1 SUM per Category in percentage_of_total

**Severity:** CRITICAL | **Refs:** P-2

**Problem:** `calculate_percentage_of_total` at line 379 runs `expenses_in_period.sum(:amount)` every time it's called — once per category in the breakdown loop. This fires N additional queries where N = number of categories.

**Files:**
- Modify: `app/services/metrics_calculator.rb:379-384` and the caller
- Test: `spec/services/metrics_calculator_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "#calculate_category_breakdown" do
  it "does not fire N+1 queries for percentage calculation" do
    create_list(:expense, 5, email_account: email_account)
    calculator = described_class.new(email_account: email_account)

    query_count = count_queries { calculator.send(:calculate_category_breakdown) }
    # Should be constant, not proportional to category count
    expect(query_count).to be <= 3
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: FAIL — fires N+1 queries

**Step 3: Pre-compute total and pass to percentage method**

```ruby
# Modify calculate_category_breakdown to compute total once:
def calculate_category_breakdown
  total = expenses_in_period.sum(:amount).to_f
  expenses_in_period
    .joins(:category)
    .group("categories.name", "categories.color")
    .sum(:amount)
    .map do |(name, color), amount|
      {
        category: name,
        color: color,
        amount: amount.to_f,
        percentage: total.zero? ? 0.0 : ((amount.to_f / total) * 100).round(2)
      }
    end
    .sort_by { |c| -c[:amount] }
end
```

Remove or deprecate `calculate_percentage_of_total` if it's not used elsewhere.

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/metrics_calculator.rb spec/services/metrics_calculator_spec.rb
git commit -m "⚡ perf(metrics): eliminate N+1 in category percentage calculation

Pre-compute total amount once and pass to percentage calculation
instead of running SUM query per category."
```

---

### Task 1.3: Consolidate MetricsCalculator Aggregates with pick()

**Severity:** HIGH | **Refs:** P-6

**Problem:** `calculate_metrics` runs 10+ separate aggregation queries (`count`, `sum`, `average`, `minimum`, `maximum`, `distinct.count` × 2, etc.) when many could be consolidated into a single query using `pick()` or `pluck`.

**Files:**
- Modify: `app/services/metrics_calculator.rb:220-238`
- Test: `spec/services/metrics_calculator_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "#calculate_metrics" do
  it "uses consolidated query for aggregate calculations" do
    create_list(:expense, 3, email_account: email_account)
    calculator = described_class.new(email_account: email_account)

    query_count = count_queries { calculator.send(:calculate_metrics) }
    # Consolidated should need at most 4-5 queries (main agg + status + currency + distinct counts)
    expect(query_count).to be <= 5
  end
end
```

**Step 2: Run test to verify it fails**

Expected: FAIL — currently fires 10+ queries

**Step 3: Consolidate aggregates**

```ruby
def calculate_metrics
  expenses = expenses_in_period
  # Single query for main aggregates
  agg = expenses.pick(
    Arel.sql("COUNT(*)"),
    Arel.sql("COALESCE(SUM(amount), 0)"),
    Arel.sql("COALESCE(AVG(amount), 0)"),
    Arel.sql("MIN(amount)"),
    Arel.sql("MAX(amount)")
  )

  count, total, average, min_val, max_val = agg

  {
    total_amount: total.to_f,
    transaction_count: count.to_i,
    average_amount: average.to_f.round(2),
    median_amount: calculate_median(expenses),
    min_amount: min_val.to_f,
    max_amount: max_val.to_f,
    unique_merchants: expenses.distinct.count(:merchant_name),
    unique_categories: expenses.joins(:category).distinct.count("categories.id"),
    uncategorized_count: expenses.uncategorized.count,
    by_status: calculate_status_breakdown(expenses),
    by_currency: calculate_currency_breakdown(expenses)
  }
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/metrics_calculator.rb spec/services/metrics_calculator_spec.rb
git commit -m "⚡ perf(metrics): consolidate 10 aggregates into single pick() query

Reduces MetricsCalculator query count from 10+ to ~5 using
pick() for COUNT, SUM, AVG, MIN, MAX in one database call."
```

---

### Task 1.4: Fix N+1 in store_bulk_operation

**Severity:** CRITICAL | **Refs:** P-4

**Problem:** `BulkCategorizationService#store_bulk_operation` at line 291 calls `Expense.find(r[:expense_id]).amount` per result in a loop — classic N+1.

**Files:**
- Modify: `app/services/categorization/bulk_categorization_service.rb:285-295`
- Test: `spec/services/categorization/bulk_categorization_service_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "#store_bulk_operation" do
  it "does not fire N+1 queries for amount calculation" do
    expenses = create_list(:expense, 10, email_account: email_account)
    results = expenses.map { |e| { expense_id: e.id, status: :success } }

    query_count = count_queries { service.send(:store_bulk_operation, results) }
    # Should be 1 query for SUM, not N queries
    expect(query_count).to be <= 5
  end
end
```

**Step 2: Run test to verify it fails**

Expected: FAIL — fires N queries

**Step 3: Replace loop with single query**

```ruby
# app/services/categorization/bulk_categorization_service.rb:291
# FROM:
total_amount: results.sum { |r| Expense.find(r[:expense_id]).amount },
# TO:
total_amount: Expense.where(id: results.map { |r| r[:expense_id] }).sum(:amount),
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/categorization/bulk_categorization_service_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/categorization/bulk_categorization_service.rb spec/services/categorization/bulk_categorization_service_spec.rb
git commit -m "⚡ perf(bulk): fix N+1 in store_bulk_operation amount calculation

Replace Expense.find per result with single Expense.where.sum query.
For 50 expenses this reduces from 50 queries to 1."
```

---

### Task 1.5: Pass Categories as Local to _expense_row Partial

**Severity:** HIGH | **Refs:** UX-003

**Problem:** `_expense_row.html.erb` line 96 calls `Category.all.order(:name).each` inside the partial. When rendering 50 rows, this fires 50 identical queries.

**Files:**
- Modify: `app/views/expenses/_expense_row.html.erb:96`
- Modify: `app/views/expenses/index.html.erb` — pass `categories` local
- Modify: `app/views/expenses/dashboard.html.erb` — pass `categories` local
- Modify: `app/controllers/expenses_controller.rb` — set `@categories`
- Test: `spec/views/expenses/expense_row_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "expense_row partial" do
  it "uses passed categories instead of querying" do
    categories = create_list(:category, 3)
    expense = create(:expense)

    query_count = count_queries do
      render partial: "expenses/expense_row",
             locals: { expense: expense, categories: categories, context: "index" }
    end
    expect(query_count).to eq(0) # No DB queries in partial
  end
end
```

**Step 2: Run test to verify it fails**

Expected: FAIL — fires Category.all query

**Step 3: Use local variable instead of query**

```erb
<%# app/views/expenses/_expense_row.html.erb — line 96, change: %>
<%# FROM: %>
<% Category.all.order(:name).each do |category| %>
<%# TO: %>
<% (local_assigns[:categories] || Category.all.order(:name)).each do |category| %>
```

Then in parent views, pass the local:
```erb
<%# In index.html.erb: %>
<%= render partial: "expense_row", collection: @expenses, as: :expense,
           locals: { categories: @categories, context: "index" } %>

<%# In dashboard.html.erb: %>
<%= render "expense_row", expense: expense, categories: @categories, context: "dashboard" %>
```

In controller, set `@categories = Category.all.order(:name)` in the relevant actions.

**Step 4: Run tests**

Run: `bundle exec rspec spec/views/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/views/expenses/_expense_row.html.erb app/views/expenses/index.html.erb app/views/expenses/dashboard.html.erb app/controllers/expenses_controller.rb
git commit -m "⚡ perf(views): pass categories as local to expense_row partial

Eliminates N duplicate Category.all queries (one per row).
Categories are now loaded once in the controller and passed as a local."
```

---

### Task 1.6: Use PostgreSQL PERCENTILE_CONT for Median

**Severity:** HIGH | **Refs:** P-7

**Problem:** `calculate_median` loads all expense amounts into Ruby memory to sort and find the middle value. For large datasets this is slow and memory-intensive.

**Files:**
- Modify: `app/services/metrics_calculator.rb` — the `calculate_median` method
- Test: `spec/services/metrics_calculator_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "#calculate_median" do
  it "calculates median correctly using SQL" do
    [10, 20, 30, 40, 50].each { |amt| create(:expense, amount: amt, email_account: email_account) }
    calculator = described_class.new(email_account: email_account)
    result = calculator.calculate

    expect(result[:metrics][:median_amount]).to eq(30.0)
  end
end
```

**Step 2: Implement PostgreSQL PERCENTILE_CONT**

```ruby
def calculate_median(expenses)
  result = expenses.pick(Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)"))
  result&.to_f&.round(2) || 0.0
end
```

**Step 3: Run tests**

Run: `bundle exec rspec spec/services/metrics_calculator_spec.rb -v`
Expected: PASS

**Step 4: Commit**

```bash
git add app/services/metrics_calculator.rb spec/services/metrics_calculator_spec.rb
git commit -m "⚡ perf(metrics): use PostgreSQL PERCENTILE_CONT for median

Replace Ruby in-memory median calculation with SQL aggregate.
Eliminates loading all amounts into memory for large datasets."
```

---

### Task 1.7: Batch Broadcast for Bulk Operations

**Severity:** HIGH | **Refs:** P-15

**Problem:** After bulk categorization, the service broadcasts an ActionCable update per expense instead of batching them into a single broadcast.

**Files:**
- Modify: `app/services/categorization/bulk_categorization_service.rb` — broadcast section
- Test: `spec/services/categorization/bulk_categorization_service_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "broadcasting" do
  it "sends a single broadcast after bulk operation" do
    expenses = create_list(:expense, 10, email_account: email_account)
    expect(ActionCable.server).to receive(:broadcast).at_most(2).times
    service.categorize(expenses.map(&:id), category.id)
  end
end
```

**Step 2: Implement batch broadcasting**

Replace per-expense broadcasts with a single summary broadcast after all updates complete:
```ruby
# After all expenses are updated, broadcast once:
broadcast_bulk_update(results)

private

def broadcast_bulk_update(results)
  ActionCable.server.broadcast(
    "expenses_channel",
    { type: "bulk_categorization", count: results.size, category_id: category_id }
  )
end
```

**Step 3: Run tests**

Run: `bundle exec rspec spec/services/categorization/bulk_categorization_service_spec.rb -v`
Expected: PASS

**Step 4: Commit**

```bash
git add app/services/categorization/bulk_categorization_service.rb spec/services/categorization/bulk_categorization_service_spec.rb
git commit -m "⚡ perf(broadcast): batch bulk categorization broadcasts

Send single ActionCable broadcast after bulk operation completes
instead of per-expense broadcasts. Reduces WebSocket traffic."
```

---

### Task 1.8: Remove Debug puts Statements

**Severity:** HIGH | **Refs:** P-13

**Problem:** `BroadcastReliabilityService` has `puts` statements at lines 48, 51 that output to stdout in production.

**Files:**
- Modify: `app/services/broadcast_reliability_service.rb:48,51`
- Test: `spec/services/broadcast_reliability_service_spec.rb`

**Step 1: Write the failing test**

```ruby
describe "#broadcast_with_retry" do
  it "does not write to stdout" do
    expect { service.broadcast_with_retry(channel: "test", target: "t", data: {}) }
      .not_to output.to_stdout
  end
end
```

**Step 2: Remove puts statements**

```ruby
# app/services/broadcast_reliability_service.rb
# DELETE line 48:
puts "[BROADCAST_DEBUG] Starting broadcast_with_retry with priority: #{priority}"
# DELETE line 51:
puts "[BROADCAST_DEBUG] Priority validated"
```

Keep the `Rails.logger.debug` lines — those are appropriate.

**Step 3: Run tests**

Run: `bundle exec rspec spec/services/broadcast_reliability_service_spec.rb -v`
Expected: PASS

**Step 4: Commit**

```bash
git add app/services/broadcast_reliability_service.rb spec/services/broadcast_reliability_service_spec.rb
git commit -m "🧹 chore(broadcast): remove debug puts statements

Remove puts debug output from BroadcastReliabilityService.
Rails.logger.debug calls are retained for proper logging."
```

---

## Phase 2: Security Hardening

These tickets address HIGH-severity security issues that should be fixed before production use.

---

### Task 2.1: Use secure_compare for Admin Key Comparison

**Severity:** HIGH | **Refs:** S-06

**Problem:** `Api::QueueController` line 258 uses `provided_key == admin_key` which is vulnerable to timing attacks. Also line 262 bypasses auth entirely in development/test.

**Files:**
- Modify: `app/controllers/api/queue_controller.rb:255-262`
- Test: `spec/controllers/api/queue_controller_spec.rb`

**Step 1: Write the test**

```ruby
describe "admin key authentication" do
  it "uses timing-safe comparison" do
    # Verify the method uses secure_compare, not ==
    expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_return(true)
    get :index, params: { admin_key: "test_key" }
  end
end
```

**Step 2: Fix the comparison**

```ruby
# app/controllers/api/queue_controller.rb:258, change:
# FROM:
return true if provided_key == admin_key
# TO:
return true if provided_key.present? && ActiveSupport::SecurityUtils.secure_compare(provided_key, admin_key)
```

Also remove or restrict the dev/test bypass:
```ruby
# FROM (line 262):
return true if Rails.env.development? || Rails.env.test?
# TO:
return true if Rails.env.development?
```

**Step 3: Run tests, commit**

```bash
git add app/controllers/api/queue_controller.rb spec/controllers/api/queue_controller_spec.rb
git commit -m "🔒 fix(security): use timing-safe comparison for admin key

Replace == with ActiveSupport::SecurityUtils.secure_compare
to prevent timing attacks on admin key authentication."
```

---

### Task 2.2: Require Sidekiq Credentials in Production

**Severity:** HIGH | **Refs:** S-07

**Problem:** `config/routes.rb` lines 15-16 use `ENV.fetch("SIDEKIQ_WEB_PASSWORD", "change_me_in_production")` — if env vars aren't set, default credentials work.

**Files:**
- Modify: `config/routes.rb:13-17`
- Test: Manual verification

**Step 1: Require env vars with no default**

```ruby
# config/routes.rb — change:
Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  sidekiq_username = ENV["SIDEKIQ_WEB_USERNAME"]
  sidekiq_password = ENV["SIDEKIQ_WEB_PASSWORD"]

  if sidekiq_username.blank? || sidekiq_password.blank?
    Rails.logger.error "[SECURITY] Sidekiq Web credentials not configured"
    false
  else
    ActiveSupport::SecurityUtils.secure_compare(username, sidekiq_username) &&
      ActiveSupport::SecurityUtils.secure_compare(password, sidekiq_password)
  end
end
```

**Step 2: Commit**

```bash
git add config/routes.rb
git commit -m "🔒 fix(security): require Sidekiq credentials, remove defaults

Remove fallback credentials for Sidekiq Web UI.
In production, SIDEKIQ_WEB_USERNAME and SIDEKIQ_WEB_PASSWORD
must be set or access is denied."
```

---

### Task 2.3: Fix MonitoringController Auth Method

**Severity:** HIGH | **Refs:** S-08

**Problem:** `MonitoringController` has a broken token lookup — the method name or parameter doesn't match what's expected, so auth silently fails.

**Files:**
- Modify: `app/controllers/monitoring_controller.rb`
- Test: `spec/controllers/monitoring_controller_spec.rb`

**Step 1: Investigate the exact issue**

Read `app/controllers/monitoring_controller.rb` to identify the broken auth method. Fix the token lookup to use the correct method/parameter.

**Step 2: Write test, fix, commit**

Pattern follows previous tasks. Fix the authentication method to properly validate the monitoring token.

---

### Task 2.4: Authenticate Client Errors Endpoint

**Severity:** HIGH | **Refs:** S-09

**Problem:** The client errors endpoint accepts unauthenticated POST requests, enabling DoS via error log flooding.

**Files:**
- Modify: Controller handling client errors
- Test: Corresponding spec

**Step 1: Add rate limiting and basic authentication**

Require either a session or API token. Add rate limiting (e.g., 10 errors per minute per IP).

**Step 2: Write test, implement, commit**

---

### Task 2.5: Add User Scoping to QueueChannel

**Severity:** HIGH | **Refs:** S-11

**Problem:** `QueueChannel` broadcasts to all subscribers without user scoping. Every connected user sees every other user's queue updates.

**Files:**
- Modify: `app/channels/queue_channel.rb`
- Test: `spec/channels/queue_channel_spec.rb`

**Step 1: Scope broadcasts to user**

```ruby
# Instead of:
stream_from "queue_channel"
# Use:
stream_from "queue_channel_#{current_session_info[:session_id]}"
```

Update all broadcast calls to include the user/session scope.

**Step 2: Write test, implement, commit**

---

### Task 2.6: Fix html_safe Usage in Helpers

**Severity:** HIGH | **Refs:** S-13

**Problem:** `accessibility_helper.rb` and `analytics_helper.rb` use `html_safe` on joined content that could include user-influenced data (e.g., category names, merchant names).

**Files:**
- Modify: `app/helpers/accessibility_helper.rb:64,96,135,148,178`
- Modify: `app/helpers/analytics_helper.rb:141,149,151`
- Test: Corresponding helper specs

**Step 1: Audit each html_safe call**

For lines 64 and 96 in `accessibility_helper.rb`, the content is hardcoded strings from `content_tag` — these are safe. For line 148, `label_text` could contain user data — use `sanitize` instead. For analytics helper, check if category names or amounts are involved.

**Step 2: Replace unsafe calls**

```ruby
# Where content is from content_tag (safe, Rails auto-escapes):
# Lines 64, 96 — these are joining content_tag outputs, which are already safe
# Can use safe_join instead:
safe_join(array_of_content_tags)

# Where user data is involved:
# Use sanitize() or ERB::Util.html_escape before html_safe
```

**Step 3: Write test, implement, commit**

---

### Task 2.7: Remove PatternManagement Permission Override

**Severity:** HIGH | **Refs:** S-14

**Problem:** Permission check in PatternManagement always returns true, similar to SyncAuthorization.

**Files:**
- Modify: `app/controllers/concerns/pattern_management.rb`
- Test: Corresponding spec

**Step 1: Implement real permission check based on current_user**

**Step 2: Write test, implement, commit**

---

### Task 2.8: Enable Content Security Policy

**Severity:** MEDIUM | **Refs:** S-15

**Problem:** `config/initializers/content_security_policy.rb` is entirely commented out — no CSP headers are sent.

**Files:**
- Modify: `config/initializers/content_security_policy.rb`
- Test: `spec/requests/csp_headers_spec.rb`

**Step 1: Uncomment and configure CSP**

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, "'unsafe-inline'" # Tailwind needs inline styles
    policy.connect_src :self, "ws://localhost:*", "wss://localhost:*" # ActionCable
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Start in report-only mode
  config.content_security_policy_report_only = true
end
```

**Step 2: Write test**

```ruby
# spec/requests/csp_headers_spec.rb
RSpec.describe "Content Security Policy", type: :request do
  it "includes CSP header" do
    get root_path
    expect(response.headers["Content-Security-Policy-Report-Only"]).to be_present
  end
end
```

**Step 3: Commit**

```bash
git add config/initializers/content_security_policy.rb spec/requests/csp_headers_spec.rb
git commit -m "🔒 feat(security): enable Content Security Policy in report-only mode

Uncomment and configure CSP. Starts in report-only mode to identify
violations before enforcing. Allows self, data URIs for fonts/images,
and WebSocket connections for ActionCable."
```

---

## Phase 3: UX & Design

These tickets address user-facing issues — broken navigation, missing translations, misleading messages.

---

### Task 3.1: Add Responsive Navigation Hamburger Menu

**Severity:** CRITICAL | **Refs:** D-4, UX-015

**Problem:** Navigation has 8 links that overflow on mobile — no hamburger menu or mobile-friendly layout.

**Files:**
- Modify: `app/views/layouts/application.html.erb:49-93`
- Create: `app/javascript/controllers/mobile_nav_controller.js`
- Test: System test

**Step 1: Create Stimulus controller**

```javascript
// app/javascript/controllers/mobile_nav_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
    const expanded = this.buttonTarget.getAttribute("aria-expanded") === "true"
    this.buttonTarget.setAttribute("aria-expanded", !expanded)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }
}
```

**Step 2: Update navigation HTML**

Add hamburger button visible on mobile (`md:hidden`), hide nav links on mobile (`hidden md:flex`), add mobile dropdown menu.

**Step 3: Write system test, commit**

---

### Task 3.2: Translate Admin Patterns Pages to Spanish

**Severity:** CRITICAL | **Refs:** D-2

**Problem:** Admin pattern management pages are entirely in English despite the app being in Spanish.

**Files:**
- Modify: All views in `app/views/admin/patterns/`
- Modify: JS strings in `app/javascript/controllers/` related to patterns

**Step 1: Identify all English strings**

Search all pattern-related views and JS files for English text.

**Step 2: Translate each file**

Replace English strings with Spanish equivalents. Examples:
- "Pattern Management" → "Gestión de Patrones"
- "Create Pattern" → "Crear Patrón"
- "Edit" → "Editar"
- "Delete" → "Eliminar"
- "Name" → "Nombre"
- "Category" → "Categoría"
- "Confidence" → "Confianza"

**Step 3: Commit**

```bash
git commit -m "🌐 feat(i18n): translate admin patterns pages to Spanish"
```

---

### Task 3.3: Translate Analytics Dashboard to Spanish

**Severity:** CRITICAL | **Refs:** D-3

**Problem:** Analytics dashboard is entirely in English.

**Files:**
- Modify: `app/views/analytics/` views
- Modify: Related JS controllers

Follow same pattern as Task 3.2.

---

### Task 3.4: Translate Bulk Categorization to Spanish

**Severity:** HIGH | **Refs:** D-6

**Files:**
- Modify: `app/views/categorization/` or related bulk operation views

Follow same pattern as Task 3.2.

---

### Task 3.5: Translate Queue Visualization to Spanish

**Severity:** HIGH | **Refs:** D-8

**Files:**
- Modify: `app/views/queue/` or queue-related views
- Modify: `app/javascript/controllers/queue_monitor_controller.js`

Follow same pattern as Task 3.2.

---

### Task 3.6: Fix Delete Confirmation Text for Soft Delete

**Severity:** HIGH | **Refs:** UX-004

**Problem:** Delete confirmation says "esta acción no se puede deshacer" ("cannot be undone") but soft-delete IS undoable.

**Files:**
- Modify: Views/JS that show the delete confirmation dialog
- Test: System test

**Step 1: Find and fix the misleading text**

```ruby
# Change confirmation text from:
"¿Estás seguro? Esta acción no se puede deshacer."
# To:
"¿Estás seguro de eliminar este gasto? Podrás restaurarlo desde el historial."
```

**Step 2: Commit**

```bash
git commit -m "📝 fix(ux): update delete confirmation to reflect soft-delete behavior"
```

---

### Task 3.7: Add Pagination to Expenses Index

**Severity:** HIGH | **Refs:** UX-006

**Problem:** Expenses index only shows first 50 records with no way to navigate to older expenses.

**Files:**
- Modify: `app/controllers/expenses_controller.rb`
- Modify: `app/views/expenses/index.html.erb:194-197`
- Create: `app/views/shared/_pagination.html.erb` (or use kaminari/pagy gem)
- Test: `spec/views/expenses/index_spec.rb`

**Step 1: Add pagy gem (lightweight pagination)**

```ruby
# Gemfile
gem "pagy"

# app/controllers/expenses_controller.rb
include Pagy::Backend

def index
  @pagy, @expenses = pagy(@expenses_scope, items: 50)
end
```

```erb
<%# app/views/expenses/index.html.erb — after table: %>
<%== pagy_nav(@pagy) %>
```

**Step 2: Write test, commit**

---

### Task 3.8: Integrate Undo with Single-Expense Delete

**Severity:** HIGH | **Refs:** UX-005

**Problem:** Dashboard delete doesn't offer undo notification despite the system supporting soft-delete with undo.

**Files:**
- Modify: `app/controllers/expenses_controller.rb#destroy`
- Modify: Flash/notification to include undo link
- Test: Controller spec

**Step 1: Return undo information from destroy**

```ruby
def destroy
  @expense.soft_delete!
  undo_entry = UndoHistory.last_for(@expense)

  respond_to do |format|
    format.html {
      redirect_to expenses_path,
        notice: "Gasto eliminado. ",
        flash: { undo_id: undo_entry&.id }
    }
    format.turbo_stream {
      render turbo_stream: turbo_stream.remove("expense_row_#{@expense.id}")
    }
  end
end
```

**Step 2: Write test, commit**

---

### Task 3.9: Auto-Dismiss Flash Messages

**Severity:** MEDIUM | **Refs:** UX-010

**Problem:** Flash messages never auto-dismiss — they stay on screen until page reload.

**Files:**
- Modify: `app/views/layouts/application.html.erb:96-110` or flash partial
- Create: `app/javascript/controllers/flash_controller.js`

**Step 1: Create Stimulus controller**

```javascript
// app/javascript/controllers/flash_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "transition-opacity", "duration-300")
    setTimeout(() => this.element.remove(), 300)
  }
}
```

**Step 2: Wire up to flash HTML**

```erb
<div data-controller="flash" data-flash-delay-value="5000" class="...">
  <%= message %>
  <button data-action="click->flash#dismiss" class="ml-2">✕</button>
</div>
```

**Step 3: Commit**

```bash
git commit -m "✨ feat(ux): add auto-dismiss and close button to flash messages"
```

---

### Task 3.10: Standardize Keyboard Shortcuts

**Severity:** MEDIUM | **Refs:** UX-013

**Problem:** Multiple Stimulus controllers define conflicting keyboard shortcuts.

**Files:**
- Audit: `app/javascript/controllers/` — find all `keydown` handlers
- Modify: Controllers with conflicting shortcuts

**Step 1: Audit all shortcuts and create a map**

**Step 2: Resolve conflicts by scoping shortcuts to the active context**

**Step 3: Document the final shortcut map in a comment or README**

---

## Phase 4: Performance Polish

---

### Task 4.1: Refactor Dashboard Query Consolidation

**Severity:** CRITICAL | **Refs:** P-5

**Problem:** Dashboard action chains 3 heavy service calls sequentially, firing 50+ total queries.

**Files:**
- Modify: `app/controllers/expenses_controller.rb#dashboard`
- Modify: Related services

**Step 1: Profile the dashboard action**

Use `ActiveSupport::Notifications` to log all queries during a dashboard load.

**Step 2: Consolidate into fewer queries**

Combine overlapping service calls. Consider a `DashboardDataService` that runs all calculations in a single pass.

**Step 3: Cache aggressively**

Use fragment caching for metric cards and category breakdown sections.

**Step 4: Write performance test, commit**

---

### Task 4.2: Implement Cache Version Key Approach

**Severity:** HIGH | **Refs:** P-10, P-11

**Problem:** `delete_matched` on Redis is O(n) on the entire keyspace. Every cache invalidation scans all keys.

**Files:**
- Modify: Cache invalidation code across services

**Step 1: Use cache version keys instead of delete_matched**

```ruby
# Instead of:
Rails.cache.delete_matched("metrics:*")
# Use:
Rails.cache.increment("metrics:version")
# And include version in cache keys:
def cache_key
  version = Rails.cache.read("metrics:version") || 0
  "metrics:v#{version}:#{email_account.id}:#{period}"
end
```

**Step 2: Write test, commit**

---

### Task 4.3: Audit and Prune Duplicate Indexes

**Severity:** HIGH | **Refs:** P-12

**Problem:** Database has 65+ indexes with significant overlap, wasting disk space and slowing writes.

**Files:**
- Create: Migration to remove duplicate indexes
- Analyze: `db/schema.rb` for overlapping indexes

**Step 1: Identify duplicates**

Run: `SELECT * FROM pg_indexes WHERE tablename = 'expenses' ORDER BY indexname;`
Look for indexes where one is a prefix of another.

**Step 2: Create migration to remove redundant indexes**

**Step 3: Write test, commit**

---

### Task 4.4: Make ThreadPoolExecutor a Singleton

**Severity:** HIGH | **Refs:** P-14

**Problem:** A `ThreadPoolExecutor` is created per engine instance, leaking threads.

**Files:**
- Modify: The service creating ThreadPoolExecutor

**Step 1: Convert to singleton or class-level instance**

```ruby
THREAD_POOL = Concurrent::ThreadPoolExecutor.new(
  min_threads: 2,
  max_threads: 5,
  max_queue: 100,
  fallback_policy: :caller_runs
)
```

**Step 2: Write test, commit**

---

### Task 4.5: Enable ExpenseFilterService Caching

**Severity:** MEDIUM | **Refs:** P-17

**Files:**
- Modify: `app/services/expense_filter_service.rb`

Add cache layer for repeated filter queries with same params.

---

### Task 4.6: Conditional Cache Invalidation on Expense Commit

**Severity:** MEDIUM | **Refs:** P-18

**Files:**
- Modify: Expense model callbacks

Only invalidate cache when expense attributes that affect metrics change (amount, category, date) — not on every save.

---

## Phase 5: Cleanup & Polish

---

### Task 5.1: Delete or Fix Mockup Files with Forbidden Blue Classes

**Severity:** MEDIUM | **Refs:** D-1

**Problem:** Mockup/demo files use `blue-600`, `blue-500` classes that violate the Financial Confidence palette.

**Files:**
- Identify: `grep -r "blue-" app/views/`
- Modify or Delete: Mockup files

**Step 1: Find all violations**

```bash
grep -rn "blue-[0-9]" app/views/ app/helpers/ app/javascript/
```

**Step 2: Replace with palette colors (teal-700, slate-600, etc.) or delete mockup files**

---

### Task 5.2: Fix Remaining English Strings

**Severity:** LOW-MEDIUM | **Refs:** D-7, D-9, D-11, D-12, D-13

**Files:**
- Search all views for English strings
- Translate to Spanish

---

### Task 5.3: Dynamic Bank Filter Dropdown

**Severity:** MEDIUM | **Refs:** UX-014

**Problem:** Bank filter in `index.html.erb` line 66 is hardcoded to `["BAC", "BAC"], ["Manual Entry", "Manual Entry"]`.

**Files:**
- Modify: `app/views/expenses/index.html.erb:66`
- Modify: `app/controllers/expenses_controller.rb`

**Step 1: Replace with dynamic query**

```erb
<%= select_tag :bank, options_for_select(
  @banks.map { |b| [b, b] }, params[:bank]
), include_blank: "Todos los bancos" %>
```

```ruby
# In controller:
@banks = Expense.distinct.pluck(:bank_name).compact.sort
```

---

### Task 5.4: Mobile Table/Card Layout for Expenses

**Severity:** MEDIUM | **Refs:** D-4

**Files:**
- Modify: `app/views/expenses/index.html.erb`
- Modify: `app/views/expenses/_expense_row.html.erb`

Add responsive breakpoints: table on desktop, card layout on mobile.

---

### Task 5.5: Fix Email Account Cascade to Nullify

**Severity:** MEDIUM | **Refs:** UX-008

**Problem:** Deleting an email account cascades to delete ALL associated expenses. Should nullify instead.

**Files:**
- Modify: `app/models/email_account.rb` — change `dependent: :destroy` to `dependent: :nullify`
- Create: Migration if needed
- Test: `spec/models/email_account_spec.rb`

**Step 1: Write failing test**

```ruby
describe "dependent behavior" do
  it "nullifies expenses instead of destroying them" do
    account = create(:email_account)
    expense = create(:expense, email_account: account)
    account.destroy
    expect(expense.reload.email_account_id).to be_nil
  end
end
```

**Step 2: Change association**

```ruby
has_many :expenses, dependent: :nullify
```

**Step 3: Commit**

```bash
git commit -m "🐛 fix(model): nullify expenses on email account deletion

Change dependent: :destroy to dependent: :nullify so deleting
an email account preserves its expenses with nil email_account_id."
```

---

## Summary

| Phase | Tickets | Priority |
|-------|---------|----------|
| Phase 0 | 7 tasks | CRITICAL — do before any deployment |
| Phase 1 | 8 tasks | CRITICAL/HIGH — performance fixes |
| Phase 2 | 8 tasks | HIGH — security hardening |
| Phase 3 | 10 tasks | CRITICAL/HIGH/MEDIUM — UX & design |
| Phase 4 | 6 tasks | HIGH/MEDIUM — performance polish |
| Phase 5 | 5 tasks | MEDIUM/LOW — cleanup |
| **Total** | **44 tasks** | |

### Execution Order

1. Phase 0 first — every task is independently deployable
2. Phase 1 and Phase 2 can run in parallel (different code areas)
3. Phase 3 after Phase 0 (auth must work before fixing UX)
4. Phase 4 and 5 are iterative polish

> **REMINDER:** Do NOT include any AI/assistant/Claude references in commit messages. Use conventional commits with emojis per project `rules/commit.md`.
