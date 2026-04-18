# Salary Calculator Integration — expense_tracker side

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Connect salary_calc's monthly budget to expense_tracker so synced `BudgetItem`s become local `Budget` rows that track spend through the existing `calculate_current_spend!` machinery.

**Architecture:** OAuth authorization-code flow links one salary_calc user to one `EmailAccount` via a new `ExternalBudgetSource` (encrypted token). Daily `ExternalBudgets::PullJob` calls `GET /api/v1/monthly_budgets/current`, upserts `Budget` rows keyed by `(external_source, external_id)`, preserves user-set `category_id`. Category mapping stays manual for phase 1.

**Tech Stack:** Rails 8.1.2, PostgreSQL, RSpec + WebMock, Solid Queue (recurring jobs), Hotwire, Tailwind.

**Design doc:** `/Users/esoto/development/salary_calculator/docs/plans/2026-04-17-salary-calc-expense-tracker-integration-design.md`

**Reference (salary_calc API):**
- Base URL: `https://salary-calc.estebansoto.dev`
- `GET /oauth/authorize?redirect_uri=<uri>&state=<csrf>&scopes=budget:read` → consent page
- `POST /oauth/token` with `grant_type=authorization_code&code=<code>&redirect_uri=<uri>` → `{access_token, token_type, scope}`
- `GET /api/v1/monthly_budgets/current` (Bearer auth) — supports `If-Modified-Since`

---

## PR Stacking Plan

Each PR is independently reviewable, CI-green, and mergeable to `main`. Later PRs branch from the merged predecessor.

| PR | Branch | Scope | Est LOC |
|----|--------|-------|---------|
| 1 | `feat/salary-calc-foundation` | `ExternalBudgetSource` model, Budget columns, encryption, model specs | ~300 |
| 2 | `feat/salary-calc-oauth-link` | OAuth callback controller, state storage, `Oauth::TokenExchanger` service, Settings→External Sources page | ~350 |
| 3 | `feat/salary-calc-sync` | `ExternalBudgets::SyncService`, `PullJob`, error paths, Solid Queue cron | ~350 |
| 4 | `feat/salary-calc-budget-ui` | Budget index "from salary_calc" badge, unmapped banner + category picker, empty-state CTA | ~300 |

**Per-PR workflow** (strict, non-negotiable):
1. Branch from current `main` (first PR) or the previous merged PR's branch head after merge.
2. TDD: write failing spec → verify fail → minimal implementation → verify pass → commit.
3. `bundle exec rubocop -a` and `bundle exec rspec` locally green.
4. Push → open PR → `/review-pr` skill → fix all findings (push immediately, no asking) → CI green → merge with `--admin` and `pr-NNN.review` marker in Clio vault.
5. `/mem-search` and claude-mem observations captured.

---

## Pre-flight (run once at session start)

**Step PF-1: Verify main is pulled and worktree exists**

```bash
cd /Users/esoto/development/expense_tracker
git fetch origin main && git checkout main && git pull --ff-only origin main
git worktree list | grep salary-calc-integration || git worktree add .worktrees/salary-calc-integration -b feat/salary-calc-integration main
cd .worktrees/salary-calc-integration
```

Expected: no errors, worktree present.

**Step PF-2: Isolate test DB for this worktree (CLAUDE.md requirement — do NOT commit)**

Edit `config/database.yml` — change the `test:` section database name to `expense_tracker_test_salary_calc<%= ENV['TEST_ENV_NUMBER'] %>`. Then:

```bash
RAILS_ENV=test bin/rails db:create
RAILS_ENV=test bin/rails db:schema:load
```

Expected: new DB created and schema loaded, no deadlock with concurrent sessions.

**Step PF-3: Confirm ENV config locations**

We will need two new ENV keys:
- `SALARY_CALC_BASE_URL` (default: `https://salary-calc.estebansoto.dev`)
- `SALARY_CALC_OAUTH_ALLOWLISTED_CALLBACK` (for local dev; prod is set on salary_calc's side — we only send our URL, salary_calc validates it)

Document these in `.kamal/secrets.example` (if present) and `README.md` → new section "Salary Calculator Integration". Do NOT commit secrets.

**Step PF-4: Register our callback URL on salary_calc**

Out-of-band step: add `https://expense-tracker.estebansoto.dev/external_sources/callback` (prod) and `http://localhost:3000/external_sources/callback` (dev) to salary_calc's `OAUTH_REDIRECT_URI_ALLOWLIST`. **This must be done before PR 2 is testable end-to-end.**

---

## PR 1 — Foundation (models + migrations)

**Branch:** `feat/salary-calc-foundation` from `main`.

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_external_budget_sources.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_add_external_source_columns_to_budgets.rb`
- Create: `app/models/external_budget_source.rb`
- Modify: `app/models/budget.rb` (add scopes + helper predicates)
- Modify: `app/models/email_account.rb` (add `has_one :external_budget_source`)
- Create: `spec/models/external_budget_source_spec.rb`
- Modify: `spec/models/budget_spec.rb` (new context for synced Budgets)
- Modify: `spec/factories/budgets.rb`, `spec/factories/external_budget_sources.rb` (new)

### Task 1.1 — Migrations

**Step 1: Generate + hand-edit `create_external_budget_sources`**

```ruby
class CreateExternalBudgetSources < ActiveRecord::Migration[8.1]
  def change
    create_table :external_budget_sources do |t|
      t.references :email_account, null: false, foreign_key: true, index: { unique: true }
      t.string :source_type, null: false, default: "salary_calculator"
      t.string :base_url, null: false
      t.text :api_token  # encrypted via Rails `encrypts`
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :external_budget_sources, [:email_account_id, :active], name: "idx_ebs_on_account_active"
  end
end
```

**Step 2: Generate + hand-edit `add_external_source_columns_to_budgets`**

```ruby
class AddExternalSourceColumnsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :external_source, :string
    add_column :budgets, :external_id, :bigint
    add_column :budgets, :external_synced_at, :datetime
    add_index :budgets, [:external_source, :external_id],
              unique: true,
              where: "external_source IS NOT NULL",
              name: "idx_budgets_external_unique"
    add_index :budgets, :external_source, where: "external_source IS NOT NULL"
  end
end
```

**Step 3: Run migrations**

```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```

Expected: schema updated, `db/schema.rb` reflects new columns.

**Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat(external-sources): add ExternalBudgetSource table + Budget external columns"
```

### Task 1.2 — `ExternalBudgetSource` model (TDD)

**Step 1: Factory first**

Create `spec/factories/external_budget_sources.rb`:

```ruby
FactoryBot.define do
  factory :external_budget_source do
    association :email_account
    source_type { "salary_calculator" }
    base_url { "https://salary-calc.estebansoto.dev" }
    api_token { "fake-token-#{SecureRandom.hex(8)}" }
    active { true }
  end
end
```

**Step 2: Write failing spec**

`spec/models/external_budget_source_spec.rb` — cover:
- belongs_to :email_account (required)
- validates `source_type` inclusion in `%w[salary_calculator]`
- validates `base_url` presence + URL format (`URI.parse` succeeds + http(s) scheme)
- `api_token` is encrypted (write a token, read raw from DB via `Model.where(...).pick(:api_token)`, assert not equal)
- scope `.active` filters `active: true`
- `#mark_failed!(error:)` method sets `active: false`, `last_sync_status: "failed"`, `last_sync_error: error`
- `#mark_succeeded!` sets `last_synced_at: Time.current`, `last_sync_status: "ok"`, `last_sync_error: nil`
- unique email_account_id (second insert for same account raises)

Run: `bundle exec rspec spec/models/external_budget_source_spec.rb -f doc`
Expected: all fail with "uninitialized constant" / validation errors missing.

**Step 3: Implement model**

```ruby
# app/models/external_budget_source.rb
class ExternalBudgetSource < ApplicationRecord
  SOURCE_TYPES = %w[salary_calculator].freeze

  encrypts :api_token

  belongs_to :email_account

  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :base_url, presence: true
  validate :base_url_must_be_http
  validates :email_account_id, uniqueness: true

  scope :active, -> { where(active: true) }

  def mark_succeeded!
    update!(last_synced_at: Time.current, last_sync_status: "ok", last_sync_error: nil)
  end

  def mark_failed!(error:)
    update!(active: false, last_sync_status: "failed", last_sync_error: error.to_s.truncate(1000))
  end

  private

  def base_url_must_be_http
    uri = URI.parse(base_url.to_s)
    errors.add(:base_url, "must be http(s)") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end
end
```

**Step 4: Verify specs pass**

Run: `bundle exec rspec spec/models/external_budget_source_spec.rb`
Expected: all green.

**Step 5: EmailAccount association**

Modify `app/models/email_account.rb` — add `has_one :external_budget_source, dependent: :destroy`. Add spec case verifying the association.

**Step 6: Commit**

```bash
git add app/models spec/models spec/factories
git commit -m "feat(external-sources): add ExternalBudgetSource model with encrypted token"
```

### Task 1.3 — Budget scopes + predicates for synced state (TDD)

**Step 1: Write failing spec** in `spec/models/budget_spec.rb`:

- `Budget.external` returns rows with `external_source` set.
- `Budget.native` returns rows without `external_source`.
- `Budget.synced_unmapped` returns external rows with `category_id: nil`.
- `budget.external?` predicate.
- `budget.unmapped?` predicate (external AND no category).
- `Budget#calculate_current_spend!` returns `0.0` early for unmapped external rows (preserve existing behavior for native + mapped-external).

**Step 2: Run, verify fail.**

**Step 3: Implement** in `app/models/budget.rb`:

```ruby
scope :external, -> { where.not(external_source: nil) }
scope :native,   -> { where(external_source: nil) }
scope :synced_unmapped, -> { external.where(category_id: nil) }

def external?
  external_source.present?
end

def unmapped?
  external? && category_id.nil?
end
```

Then early-return in `calculate_current_spend!`:

```ruby
def calculate_current_spend!
  return 0.0 unless active?
  return 0.0 if unmapped?  # NEW
  ...
end
```

**Step 4: Verify specs pass.**

**Step 5: Commit**

```bash
git add app/models spec/models
git commit -m "feat(budgets): add external/native scopes and skip spend calc for unmapped synced rows"
```

### Task 1.4 — Rubocop + full test suite

```bash
bundle exec rubocop -a app/models spec/models db/migrate
bundle exec rspec spec/models
```

### Task 1.5 — Open PR 1

```bash
git push -u origin feat/salary-calc-foundation
```

Use `draft-pr` skill. Title: `feat(external-sources): foundation models + migrations`. Body outlines the 4-PR stack and cites the design doc.

Then `/review-pr` → fix findings → merge.

---

## PR 2 — OAuth linking + Settings page

**Branch:** `feat/salary-calc-oauth-link` from merged PR 1 head.

**Files:**
- Create: `app/controllers/external_sources_controller.rb`
- Create: `app/services/oauth/token_exchanger.rb`
- Create: `app/views/external_sources/show.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/_nav_links.html.erb` (add "External Sources" under Settings dropdown)
- Create: `spec/requests/external_sources_spec.rb`
- Create: `spec/services/oauth/token_exchanger_spec.rb`
- Create: `spec/system/external_sources_flow_spec.rb`

### Task 2.1 — Routes

**Step 1:** Add to `config/routes.rb` at top level:

```ruby
resource :external_source, only: [:show, :destroy], controller: "external_sources" do
  get  :connect  # GET /external_source/connect — initiate OAuth
  get  :callback # GET /external_source/callback — OAuth redirect target
  post :sync_now
end
```

Verify: `bin/rails routes | grep external_source`
Expected: 5 routes.

**Step 2:** Commit.

### Task 2.2 — `Oauth::TokenExchanger` service (TDD)

**Step 1: Spec** (`spec/services/oauth/token_exchanger_spec.rb`):

- Happy path: POST to `https://salary-calc.estebansoto.dev/oauth/token` with correct params → returns `{access_token:, scope:}` on 200.
- Non-200 → raises `Oauth::TokenExchanger::Error` with status + body.
- Network error → raises `Oauth::TokenExchanger::Error`.

Use WebMock stubs.

**Step 2:** Run, verify fail.

**Step 3:** Implement:

```ruby
# app/services/oauth/token_exchanger.rb
module Oauth
  class TokenExchanger
    class Error < StandardError; end

    TOKEN_PATH = "/oauth/token"
    TIMEOUT = 10 # seconds

    def initialize(base_url:, code:, redirect_uri:)
      @base_url = base_url
      @code = code
      @redirect_uri = redirect_uri
    end

    def call
      uri = URI.join(@base_url, TOKEN_PATH)
      resp = Net::HTTP.post_form(uri, {
        grant_type: "authorization_code",
        code: @code,
        redirect_uri: @redirect_uri
      })
      raise Error, "status=#{resp.code} body=#{resp.body.truncate(500)}" unless resp.code.to_i == 200
      JSON.parse(resp.body).symbolize_keys
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "network: #{e.message}"
    rescue JSON::ParserError => e
      raise Error, "invalid JSON: #{e.message}"
    end
  end
end
```

**Step 4:** Verify specs pass.

**Step 5:** Commit.

### Task 2.3 — `ExternalSourcesController` (TDD, request specs)

**Step 1: Request spec** (`spec/requests/external_sources_spec.rb`) — scenarios:

- `GET /external_source/connect`
  - Without `current_email_account_id` in session → redirects to email accounts index with notice.
  - With one active email_account → generates + stores `oauth_state` in session, 302 to `https://salary-calc.estebansoto.dev/oauth/authorize` with `state`, `redirect_uri`, `scopes=budget:read`.
- `GET /external_source/callback`
  - State mismatch → redirect to `external_source_path` with alert.
  - State missing → same.
  - State valid → calls `Oauth::TokenExchanger` (stubbed via WebMock), creates `ExternalBudgetSource`, enqueues `ExternalBudgets::PullJob`, redirects to `external_source_path` with success flash.
  - Token exchange fails → redirect with alert, no source created.
- `GET /external_source` (show)
  - No source → renders "not connected" state (assert text).
  - Source present → renders "connected" + last synced time.
  - Source inactive (failed auth) → renders yellow "Reconnect required" banner.
- `POST /external_source/sync_now` — enqueues `PullJob`, redirects back.
- `DELETE /external_source` — destroys source, redirects with notice.

**Step 2:** Run, verify fail.

**Step 3: Implement controller**

```ruby
# app/controllers/external_sources_controller.rb
class ExternalSourcesController < ApplicationController
  before_action :set_email_account

  def show
    @source = @email_account&.external_budget_source
  end

  def connect
    return redirect_to email_accounts_path, alert: t("external_sources.no_account") unless @email_account
    state = SecureRandom.urlsafe_base64(24)
    session[:external_oauth_state] = { "state" => state, "email_account_id" => @email_account.id, "expires_at" => 10.minutes.from_now.iso8601 }
    uri = URI.parse(URI.join(base_url, "/oauth/authorize").to_s)
    uri.query = URI.encode_www_form(redirect_uri: callback_url, state: state, scopes: "budget:read")
    redirect_to uri.to_s, allow_other_host: true
  end

  def callback
    stored = session.delete(:external_oauth_state) || {}
    return fail_callback(t("external_sources.state_mismatch")) if stored["state"].blank? || stored["state"] != params[:state]
    return fail_callback(t("external_sources.state_expired")) if Time.parse(stored["expires_at"].to_s) < Time.current
    account = EmailAccount.find_by(id: stored["email_account_id"])
    return fail_callback(t("external_sources.no_account")) unless account

    tokens = Oauth::TokenExchanger.new(base_url: base_url, code: params[:code].to_s, redirect_uri: callback_url).call
    source = account.build_external_budget_source(
      source_type: "salary_calculator",
      base_url: base_url,
      api_token: tokens[:access_token],
      active: true
    )
    source.save!
    ExternalBudgets::PullJob.perform_later(source.id)
    redirect_to external_source_path, notice: t("external_sources.connected")
  rescue Oauth::TokenExchanger::Error => e
    Rails.logger.warn("[oauth] token exchange failed: #{e.message}")
    fail_callback(t("external_sources.exchange_failed"))
  end

  def sync_now
    source = @email_account&.external_budget_source
    return redirect_to external_source_path, alert: t("external_sources.not_connected") unless source
    ExternalBudgets::PullJob.perform_later(source.id)
    redirect_to external_source_path, notice: t("external_sources.sync_queued")
  end

  def destroy
    @email_account&.external_budget_source&.destroy
    redirect_to external_source_path, notice: t("external_sources.disconnected")
  end

  private

  def set_email_account
    @email_account = EmailAccount.active.first  # phase 1: single-account assumption
  end

  def base_url
    ENV.fetch("SALARY_CALC_BASE_URL", "https://salary-calc.estebansoto.dev")
  end

  def callback_url
    external_source_callback_url
  end

  def fail_callback(message)
    redirect_to external_source_path, alert: message
  end
end
```

**Step 4: View** — `app/views/external_sources/show.html.erb`:

- Card layout per design system (teal primary, amber warning, rose error).
- Not connected: heading + blurb + `[Connect salary_calc]` button linking to `external_source_connect_path`.
- Connected active: "Connected • last synced Xm ago" + `[Sync now]` (POST `sync_now_external_source_path`) + `[Disconnect]` (DELETE `external_source_path`).
- Connected but `active: false`: amber banner "Reconnect required" + `[Reconnect]` (same connect path) + `[Disconnect]`.

**Step 5: Nav link** — add under Settings dropdown in `app/views/layouts/_nav_links.html.erb` (both mobile and desktop branches), pointing to `external_source_path` with i18n key `nav.external_sources`.

**Step 6: i18n** — add keys under `config/locales/en.yml` and `es.yml`:

```yaml
external_sources:
  title: "External Sources"
  connected: "Connected to salary_calc"
  disconnected: "Disconnected from salary_calc"
  sync_queued: "Sync queued"
  not_connected: "Not connected"
  state_mismatch: "Security check failed — please try again"
  state_expired: "Link request expired — please try again"
  exchange_failed: "Could not exchange authorization — please reconnect"
  no_account: "Add an email account first"
  reconnect_required: "Reconnect required"
nav:
  external_sources: "External Sources"
```

**Step 7:** Verify request specs pass, add system spec using Capybara + stubbed external via WebMock.

**Step 8:** Commit.

### Task 2.4 — Rubocop + PR 2 open/review/merge

```bash
bundle exec rubocop -a
bundle exec rspec spec/requests/external_sources_spec.rb spec/services/oauth spec/system/external_sources_flow_spec.rb
git push -u origin feat/salary-calc-oauth-link
```

Open PR → `/review-pr` → fix → merge.

---

## PR 3 — Sync service + job

**Branch:** `feat/salary-calc-sync` from merged PR 2.

**Files:**
- Create: `app/services/external_budgets/sync_service.rb`
- Create: `app/services/external_budgets/api_client.rb`
- Create: `app/jobs/external_budgets/pull_job.rb`
- Modify: `config/recurring.yml` (daily cron entry)
- Create: `spec/services/external_budgets/sync_service_spec.rb`
- Create: `spec/services/external_budgets/api_client_spec.rb`
- Create: `spec/jobs/external_budgets/pull_job_spec.rb`

### Task 3.1 — `ExternalBudgets::ApiClient` (TDD)

Thin HTTP wrapper. Responsibilities: set Bearer header, honor `If-Modified-Since`, return a small struct.

**Step 1: Spec** — happy path (200), 304 (no-content), 401 (raises `UnauthorizedError`), 404 (raises `NotFoundError`), 5xx (raises `ServerError`), network timeout (raises `NetworkError`).

**Step 2: Implement:**

```ruby
# app/services/external_budgets/api_client.rb
module ExternalBudgets
  class ApiClient
    class Error < StandardError; end
    class UnauthorizedError < Error; end
    class NotFoundError < Error; end
    class ServerError < Error; end
    class NetworkError < Error; end

    Result = Struct.new(:status, :body, keyword_init: true) do
      def not_modified? = status == 304
      def ok? = status == 200
    end

    TIMEOUT = 10

    def initialize(source:)
      @source = source
    end

    def fetch_current_budget(if_modified_since: nil)
      uri = URI.join(@source.base_url, "/api/v1/monthly_budgets/current")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@source.api_token}"
      req["Accept"] = "application/json"
      req["If-Modified-Since"] = if_modified_since.httpdate if if_modified_since

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(req)
      end

      case resp.code.to_i
      when 200 then Result.new(status: 200, body: JSON.parse(resp.body))
      when 304 then Result.new(status: 304, body: nil)
      when 401 then raise UnauthorizedError, resp.body.to_s.truncate(500)
      when 404 then raise NotFoundError
      when 500..599 then raise ServerError, "status=#{resp.code}"
      else raise Error, "unexpected status=#{resp.code}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise NetworkError, e.message
    end
  end
end
```

**Step 3:** Verify, commit.

### Task 3.2 — `ExternalBudgets::SyncService` (TDD)

Responsibilities (from design doc §sync mechanics):

1. Call `ApiClient#fetch_current_budget`.
2. For each `budget_item`: upsert local Budget keyed by `(external_source: "salary_calculator", external_id: item.id)`.
3. Budgets previously synced but missing from response → `active: false`.
4. Preserve `category_id` on update.
5. Map `currency` ∈ (`USD`, `CRC`) → Budget's `currency` column (both already supported).
6. Period = `:monthly`. `start_date`/`end_date` = first/last day of `monthly_budget.year/month`.
7. Update `source.mark_succeeded!` on happy-path, `mark_failed!` on 401.

**Step 1: Spec** — scenarios:

- New item → creates Budget with `external_source:"salary_calculator"`, `external_id`, `amount`, `currency`, `name`, `period: :monthly`, `start_date`/`end_date` matching month, `category_id: nil`, `active: true`, `external_synced_at` set.
- Existing item (same `external_id`) → updates `amount`, `name`, `currency`, preserves `category_id` and `active`.
- Previously synced item dropped → `active: false` on that row, others untouched.
- API returns 304 → no writes, `mark_succeeded!` still called (confirms reachability).
- API returns 404 → no writes, `mark_succeeded!` called (no budget this month yet — silent success).
- API returns 401 → `source.mark_failed!(error: ...)`, raises nothing to caller (caller's job handles logging).
- API returns 5xx → raises `ApiClient::ServerError` (job layer retries).

**Step 2:** Implement:

```ruby
# app/services/external_budgets/sync_service.rb
module ExternalBudgets
  class SyncService
    SOURCE_KEY = "salary_calculator"

    def initialize(source:)
      @source = source
    end

    def call
      result = ApiClient.new(source: @source).fetch_current_budget(if_modified_since: @source.last_synced_at)

      if result.ok?
        apply_payload(result.body)
      end
      # 304 and ok? both treated as success
      @source.mark_succeeded!
      true
    rescue ApiClient::NotFoundError
      @source.mark_succeeded!
      true
    rescue ApiClient::UnauthorizedError => e
      @source.mark_failed!(error: "unauthorized: #{e.message}")
      false
    end

    private

    def apply_payload(body)
      monthly = body.fetch("monthly_budget")
      items   = body.fetch("budget_items", [])
      year    = monthly.fetch("year").to_i
      month   = monthly.fetch("month").to_i
      period_start = Date.new(year, month, 1)
      period_end   = period_start.end_of_month
      account = @source.email_account
      present_ids = items.map { |i| i["id"] }

      ActiveRecord::Base.transaction do
        items.each { |item| upsert_budget(account, item, period_start, period_end) }
        # Deactivate dropped items (but only those from this source)
        account.budgets.where(external_source: SOURCE_KEY).where.not(external_id: present_ids).update_all(active: false)
      end
    end

    def upsert_budget(account, item, period_start, period_end)
      budget = account.budgets.find_or_initialize_by(external_source: SOURCE_KEY, external_id: item["id"])
      budget.assign_attributes(
        name: item["name"],
        amount: item["amount"],
        currency: item["currency"],
        period: :monthly,
        start_date: period_start,
        end_date: period_end,
        external_synced_at: Time.current,
        active: budget.new_record? ? true : budget.active
      )
      budget.save!
    end
  end
end
```

**Step 3:** Verify specs pass. Commit.

### Task 3.3 — `ExternalBudgets::PullJob` (TDD)

Responsibilities:
- `perform(source_id)` → load source, call SyncService.
- Retry on `NetworkError`, `ServerError` with exponential backoff, max 3 attempts.
- Any other exception after retries → log + swallow (don't crash queue).

**Step 1: Spec** — enqueues, calls service, retries twice on ServerError (use `perform_enqueued_jobs` matcher + WebMock), stops retrying on 401 (handled by service).

**Step 2:** Implement:

```ruby
# app/jobs/external_budgets/pull_job.rb
module ExternalBudgets
  class PullJob < ApplicationJob
    queue_as :default

    retry_on ApiClient::NetworkError, wait: :exponentially_longer, attempts: 3
    retry_on ApiClient::ServerError,  wait: :exponentially_longer, attempts: 3

    def perform(source_id)
      source = ExternalBudgetSource.find_by(id: source_id)
      return unless source&.active?

      SyncService.new(source: source).call
    end
  end
end
```

**Step 3:** Verify. Commit.

### Task 3.4 — Solid Queue cron

Add to `config/recurring.yml` under `default:`:

```yaml
external_budgets_daily_sync:
  command: "ExternalBudgetSource.active.find_each { |s| ExternalBudgets::PullJob.perform_later(s.id) }"
  queue: default
  schedule: every day at 6am
  description: "Pull latest monthly budget from each active external source"
```

Commit.

### Task 3.5 — PR 3

Rubocop + full service/job specs. Push. Open PR. `/review-pr` → fix → merge.

---

## PR 4 — Budget UI + empty state

**Branch:** `feat/salary-calc-budget-ui` from merged PR 3.

**Files:**
- Modify: `app/views/budgets/index.html.erb`
- Create: `app/views/budgets/_budget_card.html.erb` (extract, add badge/banner logic)
- Create: `app/views/budgets/_unmapped_banner.html.erb`
- Create: `app/views/budgets/_external_source_empty_state.html.erb`
- Modify: `app/controllers/budgets_controller.rb` (expose `@has_external_source`, `@unmapped_budgets`)
- Modify: `config/locales/en.yml`, `es.yml`
- Modify: `spec/requests/budgets_spec.rb` or add new `spec/requests/budgets_external_source_spec.rb`
- Add: `spec/system/budgets_external_source_ui_spec.rb` (Capybara, stubbed external)

### Task 4.1 — Controller changes (TDD)

**Step 1: Spec** — request spec cases:

- `GET /budgets` with no `ExternalBudgetSource` and **zero** budgets → renders empty-state CTA "Connect salary_calc" linking to `external_source_connect_path`.
- `GET /budgets` with a source but no synced budgets → renders "No budgets yet — sync in progress" (standard empty state).
- `GET /budgets` with external budgets including one unmapped → renders warning banner for that card.
- `GET /budgets` with external mapped budget → renders "from salary_calc" badge, no unmapped banner.

**Step 2:** Update controller:

```ruby
def index
  @budgets = @email_account.budgets.includes(:category).order(active: :desc, period: :asc, created_at: :desc)
  @has_external_source = @email_account.external_budget_source&.active?
  @unmapped_count = @budgets.count { |b| b.unmapped? }
  @budgets_by_period = @budgets.group_by(&:period)
  @overall_health = calculate_overall_budget_health
end
```

**Step 3:** Extract view. Budgets index renders `_budget_card` which checks `budget.external?` for badge and `budget.unmapped?` for banner + inline category picker (form posting to `budget_path(budget)` PATCH with `category_id`). Empty-state partial renders when `!@has_external_source && @budgets.none?`.

**Step 4: Category picker form** — inline `form_with(model: budget, method: :patch, local: true)` with `select :category_id`, options from the account's categories, submit button "Set category". Existing `update` action handles it.

**Step 5:** System spec — visit `/budgets` with WebMock-stubbed external source, assert badge, pick a category, reload, assert badge remains + banner gone.

### Task 4.2 — i18n

```yaml
budgets:
  external_badge: "from salary_calc"
  unmapped_banner: "Pick a category to start tracking spend"
  empty_state:
    heading: "Connect salary_calc"
    body: "Pull in your monthly budget to see planned vs actual spend."
    cta: "Connect salary_calc"
```

### Task 4.3 — Rubocop + full suite + PR 4

Push, open PR, `/review-pr`, merge.

---

## Post-merge verification

After PR 4 is on main:

1. **Manual end-to-end test in development** (salary_calc must be running locally on a reachable URL OR use ngrok to hit prod from dev):
   - Visit `/external_source` → "Not connected".
   - Click Connect → redirected to salary_calc → Authorize.
   - Returned → "Connected", first sync kicked off.
   - After sync: `/budgets` shows unmapped banner.
   - Pick category → banner gone, spend calc runs on next `calculate_current_spend!`.
   - Click Sync now → no errors.
   - Disconnect → source gone, Budget rows go `active: false` next sync (or immediately if we choose to; design says sync-driven).

2. **Claude-mem observation**: capture full merge + deploy readiness.

3. **Linear ticket**: close whichever ticket tracks this epic (create one if absent).

---

## Out-of-scope reminders (design-confirmed)

- Write endpoints back to salary_calc.
- Income sources, graphs, multi-account.
- Auto-suggest category mapping (phase 2).
- Webhook push sync (phase 2).
- PKCE on OAuth (phase 2 — single-user personal app).

---

## Hard guardrails (DO NOT VIOLATE)

- Never `--no-verify` a commit.
- Never push to main — all four PRs open + review + merge.
- Never add `Co-Authored-By:` trailers.
- Complex-tier ticket → `/review-pr` for each PR (Codex review is insufficient for this multi-ticket scope).
- TDD strictly: spec fails first, then implementation.
- 4 PRs, 200–400 LOC each. If a PR balloons past 500 LOC, split.
