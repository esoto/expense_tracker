# Performance Audit Report - Expense Tracker Application

**Audit Date:** 2026-02-14
**Auditor:** Claude Opus 4.6 (Performance Analyst)
**Application:** Rails 8.1 Expense Tracker
**Scope:** Full-stack performance audit across 6 areas

---

## Executive Summary

This audit identified **32 performance findings** across the application, including **5 CRITICAL**, **10 HIGH**, **12 MEDIUM**, and **5 LOW** severity issues. The most impactful findings are concentrated in the **MetricsCalculator service** (N+1 queries and redundant calculations), **database index over-proliferation**, and **PatternCache's destructive `flushdb` call**.

### Performance Targets vs. Findings

| Target | Current Status | Verdict |
|--------|---------------|---------|
| Database queries < 50ms | At risk - MetricsCalculator fires 20+ queries per dashboard load | FAILING |
| Page load < 200ms initial | At risk - Dashboard triggers 50+ DB queries | AT RISK |
| JS interactions < 16ms | Generally met, except VirtualScrollController innerHTML pattern | PASSING |
| Batch operations < 2s for 100 items | At risk - N+1 queries in BulkCategorizationService | AT RISK |
| WebSocket latency < 100ms | At risk - synchronous sleep in retry backoff | AT RISK |
| Cache hit rate > 80% | Unknown - ExpenseFilterService cache disabled by default | UNKNOWN |

---

## Summary Table

| # | Severity | Area | File | Finding | Est. Impact |
|---|----------|------|------|---------|-------------|
| 1 | CRITICAL | Database | `metrics_calculator.rb:241` | `calculate_trends` calls `calculate_metrics` again, doubling queries | 20+ redundant queries per dashboard load |
| 2 | CRITICAL | Database | `metrics_calculator.rb:379` | `calculate_percentage_of_total` fires N+1 SUM query per category | O(n) queries where n = category count |
| 3 | CRITICAL | Caching | `pattern_cache.rb:232` | `invalidate_all` calls `redis_client.flushdb` destroying entire Redis database | Data loss in all Redis-backed features |
| 4 | CRITICAL | Database | `bulk_categorization_service.rb:291` | `store_bulk_operation` does `Expense.find` per result for amount | O(n) queries where n = bulk operation size |
| 5 | CRITICAL | Database | `expenses_controller.rb:113-169` | Dashboard action fires 50+ queries (batch_calculate + analytics + filter service) | >500ms page load |
| 6 | HIGH | Database | `metrics_calculator.rb:223` | `calculate_metrics` fires ~10 separate aggregate queries on same relation | 10 queries instead of 1 |
| 7 | HIGH | Database | `metrics_calculator.rb:362` | `calculate_median` loads ALL amounts into Ruby memory with `pluck` | Memory spike on large datasets |
| 8 | HIGH | Database | `metrics_calculator.rb:304` | `calculate_trend_data` bypasses memoized `expenses_in_period` | Duplicate query execution |
| 9 | HIGH | Database | `expense.rb:170` | `category_exists_if_provided` runs `Category.exists?` on every save | Extra query on every expense save |
| 10 | HIGH | Caching | `metrics_calculator.rb:66-68` | `clear_cache` uses `delete_matched` which is O(n) on Redis keyspace | Slow cache invalidation |
| 11 | HIGH | Caching | `dashboard_service.rb:32` | `clear_cache` uses `delete_matched("dashboard_*")` on every expense commit | Expensive operation per save |
| 12 | HIGH | Database | `db/schema.rb` | 65+ indexes with significant overlap/duplication across tables | Slower writes, wasted storage |
| 13 | HIGH | ActionCable | `broadcast_reliability_service.rb:48-52` | Debug `puts` statements left in production code | stdout pollution, minor perf overhead |
| 14 | HIGH | Service Layer | `categorization/engine.rb` | ThreadPoolExecutor with 10 threads created per engine instance | Thread leak on repeated instantiation |
| 15 | HIGH | ActionCable | `bulk_operations/categorization_service.rb:97` | `broadcast_categorization_updates` broadcasts per-expense after bulk update | N broadcasts instead of 1 batch |
| 16 | MEDIUM | Database | `dashboard_expense_filter_service.rb:297` | `generate_quick_filters` fires 3 separate COUNT queries for periods | 3 extra queries per dashboard load |
| 17 | MEDIUM | Caching | `expense_filter_service.rb:369` | ExpenseFilterService cache is disabled by default | 0% cache hit rate for filtering |
| 18 | MEDIUM | Database | `expense.rb:27` | `after_commit :clear_dashboard_cache` fires on EVERY expense commit | Cascading cache invalidation |
| 19 | MEDIUM | Backend Jobs | `metrics_calculation_job.rb:129` | Generates up to 19 period/date combinations per account | Excessive job scheduling |
| 20 | MEDIUM | Backend Jobs | `metrics_refresh_job.rb` | Debounce lock uses `unless_exist` which is not atomic in all backends | Race condition potential |
| 21 | MEDIUM | Frontend | `virtual_scroll_controller.js` | Clears `innerHTML` and re-clones nodes on every scroll update | Forced reflow, GC pressure |
| 22 | MEDIUM | Frontend | `chart_controller.js:4` | `Chart.register(...registerables)` registers ALL Chart.js components | Larger JS bundle than needed |
| 23 | MEDIUM | Frontend | `sparkline_controller.js:65` | Polls for Chart.js with setTimeout loop (up to 20 attempts) | 2s worst-case blocking |
| 24 | MEDIUM | Service Layer | `categorization/matchers/fuzzy_matcher.rb:400` | Levenshtein distance creates full 2D matrix O(m*n) | Memory-intensive for long strings |
| 25 | MEDIUM | Service Layer | `pattern_cache.rb:407` | Creates separate Redis connection instead of using Rails.cache | Connection pool fragmentation |
| 26 | MEDIUM | Database | `expenses_controller.rb:14,162` | `current_user_email_accounts.pluck(:id)` called multiple times per request | Redundant queries per request |
| 27 | MEDIUM | Frontend | `sync_sessions_controller.js:223` | `showNotification` appends elements to body without cleanup tracking | DOM node leak |
| 28 | LOW | Database | `dashboard_expense_filter_service.rb:150` | Includes `:ml_suggested_category` even when not needed | Unnecessary eager loading |
| 29 | LOW | ActionCable | `sync_status_channel.rb` | Verbose security logging on every connection/disconnection | Log volume |
| 30 | LOW | Frontend | `batch_selection_controller.js:78` | Global `keydown` listener on `document` | Minor event handling overhead |
| 31 | LOW | Service Layer | `fuzzy_matcher.rb:703` | TextNormalizer `@normalization_cache` only bounds at 1000 but never evicts | Unbounded memory growth |
| 32 | LOW | Backend Jobs | `expense.rb:28` | `trigger_metrics_refresh` schedules job on every expense create/update | Job queue saturation risk |

---

## Detailed Findings

---

### Area 1: Database Performance

#### FINDING #1 - CRITICAL: Redundant Metrics Calculation in `calculate_trends`
- **Epic Affected:** Epic 2 (Metrics & Dashboard)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 241-258
- **Description:** The `calculate_trends` method calls `calculate_metrics` internally (line 242), which is the same method already called by the parent `calculate` method (line 38). This means every metric calculation fires the full set of ~10 aggregate queries TWICE -- once for the current period and then again inside `calculate_trends`.
- **Code:**
  ```ruby
  def calculate_trends
    current_metrics = calculate_metrics  # <-- Recalculates everything!
    previous_expenses = expenses_in_previous_period
    # ...
  end
  ```
- **Expected Impact:** Dashboard load should use cached metrics from the initial `calculate_metrics` call.
- **Actual Impact:** 20+ redundant database queries per dashboard load, doubling query time.
- **Recommended Fix:** Pass the already-calculated metrics hash into `calculate_trends` as a parameter instead of recalculating:
  ```ruby
  def calculate
    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
      metrics = calculate_metrics
      {
        metrics: metrics,
        trends: calculate_trends(metrics),
        # ...
      }
    end
  end

  def calculate_trends(current_metrics)
    previous_expenses = expenses_in_previous_period
    previous_total = previous_expenses.sum(:amount).to_f
    # Use current_metrics directly instead of recalculating
  end
  ```

---

#### FINDING #2 - CRITICAL: N+1 Aggregation in `calculate_percentage_of_total`
- **Epic Affected:** Epic 2 (Metrics & Dashboard)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 379-384
- **Description:** This method is called once per category in `calculate_category_breakdown` (line 281). Each call executes `expenses_in_period.sum(:amount)` which, despite memoization of the relation, still fires a fresh SQL SUM query every time because ActiveRecord relations are lazy and `.sum` triggers a new query.
- **Code:**
  ```ruby
  def calculate_percentage_of_total(amount)
    total = expenses_in_period.sum(:amount).to_f  # Fires a query EACH TIME
    return 0.0 if total.zero?
    ((amount / total) * 100).round(2)
  end
  ```
- **Expected Impact:** Single total query, then percentage calculated in Ruby.
- **Actual Impact:** If there are 15 categories, this fires 15 additional SUM queries.
- **Recommended Fix:** Calculate the total once and pass it in:
  ```ruby
  def calculate_category_breakdown
    total_amount = expenses_in_period.sum(:amount).to_f
    # ... in the map block:
    percentage_of_total: total_amount.zero? ? 0.0 : ((total.to_f / total_amount) * 100).round(2)
  end
  ```

---

#### FINDING #4 - CRITICAL: N+1 in `store_bulk_operation`
- **Epic Affected:** Epic 3 (Bulk Operations)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/bulk_categorization_service.rb`
- **Line:** 285-306
- **Description:** The `total_amount` calculation does `Expense.find(r[:expense_id])` for EACH result in the array to get its amount. If 100 expenses are bulk-categorized, this fires 100 separate SELECT queries.
- **Code:**
  ```ruby
  total_amount: results.sum { |r| Expense.find(r[:expense_id]).amount },
  ```
- **Expected Impact:** A single query to fetch all amounts: `Expense.where(id: result_ids).sum(:amount)`.
- **Actual Impact:** O(n) queries where n = number of results. For 100 items, that is 100 extra queries.
- **Recommended Fix:**
  ```ruby
  expense_ids = results.map { |r| r[:expense_id] }
  total_amount = Expense.where(id: expense_ids).sum(:amount)
  ```

---

#### FINDING #5 - CRITICAL: Dashboard Action Query Explosion
- **Epic Affected:** Epic 2 & 3 (Dashboard)
- **File:** `/Users/esoto/development/expense_tracker/app/controllers/expenses_controller.rb`
- **Line:** 113-211
- **Description:** The `dashboard` action orchestrates three heavy service calls in sequence:
  1. `MetricsCalculator.batch_calculate` for 4 periods (line 122) -- fires ~40 queries (10 per period x 4, doubled by trends)
  2. `DashboardService.new.analytics` (line 141) -- fires ~8 more queries (totals, recent, category, monthly, bank, merchants, accounts, sync)
  3. `DashboardExpenseFilterService.new.call` (line 168) -- fires ~6 more queries (scope, count, summary stats, quick filters)

  Additionally, `current_user_email_accounts.pluck(:id)` is called at lines 14 and 162, firing the same query twice.
- **Expected Impact:** Dashboard should load with < 10 queries total via aggressive caching and consolidated queries.
- **Actual Impact:** 50+ database queries per dashboard load when cache is cold, likely exceeding 200ms target.
- **Recommended Fix:**
  1. Ensure `MetricsCalculator.batch_calculate` preloading actually serves from cache on subsequent period calculations
  2. Consolidate the three service calls or pipeline their caching
  3. Memoize `current_user_email_accounts.pluck(:id)` in a before_action or helper method

---

#### FINDING #6 - HIGH: Multiple Aggregate Queries in `calculate_metrics`
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 223-238
- **Description:** The `calculate_metrics` method fires approximately 10 separate SQL queries against the same `expenses_in_period` relation: `sum(:amount)`, `count`, `minimum(:amount)`, `maximum(:amount)`, `distinct.count(:merchant_name)`, `joins(:category).distinct.count`, `uncategorized.count`, `group(:status).count`, `group(:currency).sum(:amount)`, plus `calculate_average` (which calls `count` + `sum` = 2 more) and `calculate_median` (which calls `pluck`).
- **Expected Impact:** Use `pick` with multiple Arel.sql aggregates (like `DashboardExpenseFilterService.calculate_summary_stats` does correctly on line 261-271) to consolidate into 1-2 queries.
- **Actual Impact:** ~12 queries per period calculation. With 4 periods in batch_calculate, that is ~48 aggregate queries.
- **Recommended Fix:** Consolidate aggregates into a single `pick` call:
  ```ruby
  stats = expenses.pick(
    Arel.sql("SUM(amount)"),
    Arel.sql("COUNT(*)"),
    Arel.sql("AVG(amount)"),
    Arel.sql("MIN(amount)"),
    Arel.sql("MAX(amount)"),
    Arel.sql("COUNT(DISTINCT merchant_name)"),
    Arel.sql("COUNT(DISTINCT category_id)")
  )
  ```

---

#### FINDING #7 - HIGH: Memory-Intensive Median Calculation
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 361-371
- **Description:** `calculate_median` calls `pluck(:amount).map(&:to_f).sort`, loading ALL expense amounts for the period into Ruby memory, converting to floats, and sorting. For a year period with 10,000+ expenses, this creates a large in-memory array.
- **Code:**
  ```ruby
  def calculate_median(expenses_relation)
    amounts = expenses_relation.pluck(:amount).map(&:to_f).sort
  end
  ```
- **Expected Impact:** Use PostgreSQL's `PERCENTILE_CONT(0.5)` window function to calculate median in the database.
- **Actual Impact:** Memory spike proportional to expense count; GC pressure.
- **Recommended Fix:**
  ```ruby
  def calculate_median(expenses_relation)
    result = expenses_relation.pick(
      Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)")
    )
    result&.to_f || 0.0
  end
  ```

---

#### FINDING #8 - HIGH: Bypass of Memoized Relation in `calculate_trend_data`
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 296-343
- **Description:** `calculate_trend_data` queries `email_account.expenses.where(transaction_date: ...)` directly (line 304) instead of using the memoized `expenses_in_period` relation. This fires a completely separate database query that may overlap with data already loaded.
- **Expected Impact:** Reuse the preloaded data or memoized relation.
- **Actual Impact:** Duplicate query that could be avoided.
- **Recommended Fix:** Use `expenses_in_period` with appropriate scoping, or at minimum ensure this query benefits from the `preload_data_for_batch` optimization.

---

#### FINDING #9 - HIGH: Redundant `Category.exists?` Validation
- **Epic Affected:** All Epics
- **File:** `/Users/esoto/development/expense_tracker/app/models/expense.rb`
- **Line:** 169-173
- **Description:** The custom validation `category_exists_if_provided` calls `Category.exists?(category_id)` on every save. Rails' `belongs_to :category` association already validates existence when `optional: false`, and even with `optional: true`, a foreign key constraint at the database level would handle this more efficiently.
- **Code:**
  ```ruby
  def category_exists_if_provided
    if category_id.present? && !Category.exists?(category_id)
      errors.add(:category, "must exist")
    end
  end
  ```
- **Expected Impact:** Zero extra queries for category validation.
- **Actual Impact:** 1 extra SELECT query on every expense save.
- **Recommended Fix:** Remove the custom validation and rely on the database foreign key constraint (already present in schema) plus ActiveRecord's built-in association validation.

---

#### FINDING #12 - HIGH: Database Index Over-Proliferation
- **Epic Affected:** All Epics
- **File:** `/Users/esoto/development/expense_tracker/db/schema.rb`
- **Line:** Various
- **Description:** The database has 65+ indexes across tables with significant overlap:
  - `categorization_patterns`: ~25 indexes, many covering overlapping columns
  - `expenses`: ~25 indexes including duplicate entries (two separate indexes on `[bank_name, transaction_date]`)
  - `merchant_aliases`: Duplicate trigram indexes on `normalized_name`
  - `pattern_feedbacks`: ~15 indexes with significant overlap

  Excessive indexing slows down INSERT/UPDATE operations and wastes storage.
- **Expected Impact:** Strategic, non-overlapping indexes covering actual query patterns.
- **Actual Impact:** Write performance degradation proportional to number of indexes. Each expense INSERT must update 25+ index entries.
- **Recommended Fix:**
  1. Audit actual query patterns with `pg_stat_user_indexes` to identify unused indexes
  2. Remove duplicate indexes (e.g., the duplicate `[bank_name, transaction_date]` index on expenses)
  3. Remove overlapping indexes where a compound index already covers the single-column case
  4. Target: reduce to ~10-12 well-designed indexes per table

---

#### FINDING #16 - MEDIUM: Quick Filter Count Queries
- **Epic Affected:** Epic 3 (Dashboard Filtering)
- **File:** `/Users/esoto/development/expense_tracker/app/services/dashboard_expense_filter_service.rb`
- **Line:** 297-326
- **Description:** `generate_quick_filters` fires 3 separate COUNT queries for period filters (today, week, month) via `count_for_period`, plus 2 GROUP queries for categories and statuses. That is 5 queries just for filter metadata.
- **Expected Impact:** Single query with CASE expressions or lateral joins.
- **Actual Impact:** 5 extra queries per dashboard expense widget load.
- **Recommended Fix:** Use conditional aggregation:
  ```ruby
  scope.pick(
    Arel.sql("COUNT(*) FILTER (WHERE transaction_date = CURRENT_DATE)"),
    Arel.sql("COUNT(*) FILTER (WHERE transaction_date >= date_trunc('week', CURRENT_DATE))"),
    Arel.sql("COUNT(*) FILTER (WHERE transaction_date >= date_trunc('month', CURRENT_DATE))")
  )
  ```

---

#### FINDING #26 - MEDIUM: Redundant `pluck(:id)` Calls
- **Epic Affected:** Epic 3 (Filtering)
- **File:** `/Users/esoto/development/expense_tracker/app/controllers/expenses_controller.rb`
- **Line:** 14, 162
- **Description:** `current_user_email_accounts.pluck(:id)` is called at least twice per dashboard request (once in the index action via filter service, once in dashboard action). Each call fires a separate SELECT query.
- **Expected Impact:** Single query, result memoized.
- **Actual Impact:** 2+ redundant queries per request.
- **Recommended Fix:** Memoize in a helper method:
  ```ruby
  def current_email_account_ids
    @current_email_account_ids ||= current_user_email_accounts.pluck(:id)
  end
  ```

---

### Area 2: Caching Strategy

#### FINDING #3 - CRITICAL: `flushdb` Destroys Entire Redis Database
- **Epic Affected:** Epic 2 (Categorization)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/pattern_cache.rb`
- **Line:** 228-240
- **Description:** The `invalidate_all` method calls `redis_client.flushdb` which deletes ALL keys in the entire Redis database -- not just pattern cache keys. This destroys cached metrics, dashboard cache, session data, Solid Cache entries, and any other Redis-backed data.
- **Code:**
  ```ruby
  def invalidate_all
    @lock.synchronize do
      @memory_cache.clear
      if @redis_available
        redis_client.flushdb  # DESTROYS EVERYTHING IN REDIS
      end
    end
  end
  ```
- **Expected Impact:** Only pattern-related cache keys should be invalidated.
- **Actual Impact:** Complete data loss across all Redis-backed features. Any call to `invalidate_all` causes a system-wide cache miss storm.
- **Recommended Fix:** Use namespaced key deletion:
  ```ruby
  def invalidate_all
    @lock.synchronize do
      @memory_cache.clear
      if @redis_available
        keys = redis_client.keys("#{CACHE_PREFIX}*")
        redis_client.del(*keys) if keys.any?
      end
    end
  end
  ```
  Or better yet, use `SCAN` with `DEL` to avoid blocking Redis with `KEYS`.

---

#### FINDING #10 - HIGH: `delete_matched` in MetricsCalculator Cache Clearing
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/services/metrics_calculator.rb`
- **Line:** 64-69
- **Description:** `clear_cache` uses `Rails.cache.delete_matched("metrics_calculator:*")` which performs a `KEYS` or `SCAN` operation on Redis. This is O(n) relative to the total number of keys in the Redis database, not just matching keys.
- **Code:**
  ```ruby
  def self.clear_cache(email_account: nil)
    if email_account
      Rails.cache.delete_matched("metrics_calculator:account_#{email_account.id}:*")
    else
      Rails.cache.delete_matched("metrics_calculator:*")
    end
  end
  ```
- **Expected Impact:** Targeted key deletion using known cache key patterns.
- **Actual Impact:** Slow operation that blocks Redis during scan, especially as the database grows.
- **Recommended Fix:** Maintain an explicit list of cache keys or use a cache version/generation approach:
  ```ruby
  def self.clear_cache(email_account:)
    SUPPORTED_PERIODS.each do |period|
      key = "metrics_calculator:account_#{email_account.id}:#{period}:#{Date.current.iso8601}"
      Rails.cache.delete(key)
    end
  end
  ```

---

#### FINDING #11 - HIGH: Dashboard Cache Cleared on Every Expense Commit
- **Epic Affected:** Epic 2 (Dashboard)
- **File:** `/Users/esoto/development/expense_tracker/app/models/expense.rb` (line 27) + `/Users/esoto/development/expense_tracker/app/services/dashboard_service.rb` (line 32)
- **Description:** Every expense `after_commit` triggers `Services::DashboardService.clear_cache`, which calls `Rails.cache.delete_matched("dashboard_*")`. During bulk imports of 100+ expenses, this fires 100+ `delete_matched` operations on Redis.
- **Expected Impact:** Debounced cache invalidation or event-based invalidation.
- **Actual Impact:** Redis is hammered with expensive SCAN+DEL operations during bulk imports.
- **Recommended Fix:**
  1. Use a cache version key approach: `Rails.cache.increment("dashboard_cache_version")` and include the version in cache keys
  2. Or debounce the invalidation similar to `MetricsRefreshJob`

---

#### FINDING #17 - MEDIUM: ExpenseFilterService Cache Disabled by Default
- **Epic Affected:** Epic 3 (Filtering)
- **File:** `/Users/esoto/development/expense_tracker/app/services/expense_filter_service.rb`
- **Line:** 368-371
- **Description:** The `cache_enabled?` method checks `Rails.configuration.expense_filter_cache_enabled`, but this configuration is not set by default, so caching is always disabled.
- **Code:**
  ```ruby
  def cache_enabled?
    Rails.configuration.respond_to?(:expense_filter_cache_enabled) &&
      Rails.configuration.expense_filter_cache_enabled
  end
  ```
- **Expected Impact:** Caching should be enabled in production for repeated filter queries.
- **Actual Impact:** 0% cache hit rate. Every filter request hits the database.
- **Recommended Fix:** Enable caching by default in production configuration:
  ```ruby
  # config/environments/production.rb
  config.expense_filter_cache_enabled = true
  ```

---

#### FINDING #25 - MEDIUM: Separate Redis Connection in PatternCache
- **Epic Affected:** Epic 2 (Categorization)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/pattern_cache.rb`
- **Line:** ~407
- **Description:** `PatternCache` creates its own Redis connection instead of using the Rails.cache Redis pool. This bypasses connection pooling and can lead to connection exhaustion under load.
- **Expected Impact:** Use `Rails.cache` or a shared Redis connection pool.
- **Actual Impact:** Extra Redis connections per thread/process, potential connection pool fragmentation.
- **Recommended Fix:** Use `Rails.cache.redis` or configure a shared connection pool that PatternCache draws from.

---

### Area 3: Background Jobs

#### FINDING #19 - MEDIUM: Excessive Period/Date Combinations in MetricsCalculationJob
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/jobs/metrics_calculation_job.rb`
- **Line:** 129-158
- **Description:** `generate_periods_and_dates` creates up to 19 period/date combinations per email account: 8 days + 5 weeks + 4 months + 2 years = 19. Each combination triggers a separate `MetricsCalculator.new.calculate` call with its own set of ~10+ queries.
- **Expected Impact:** Pre-calculation should focus on the most commonly requested periods (current day, week, month, year = 4 combinations).
- **Actual Impact:** 19 x 10+ queries = 190+ database queries per email account per job run.
- **Recommended Fix:** Reduce to current periods only, and calculate historical periods on-demand:
  ```ruby
  def generate_periods_and_dates(reference_date)
    Services::MetricsCalculator::SUPPORTED_PERIODS.map do |period|
      [period, reference_date]
    end
  end
  ```

---

#### FINDING #20 - MEDIUM: Non-Atomic Debounce Lock
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/jobs/metrics_refresh_job.rb`
- **Line:** ~105
- **Description:** The debounce mechanism uses `Rails.cache.write(key, value, unless_exist: true)` for locking. The `unless_exist` option maps to Redis `NX`, which is atomic in Redis, but may not be atomic in other cache backends (Solid Cache, file store). If the cache backend changes, the debounce could fail.
- **Expected Impact:** Atomic lock acquisition regardless of cache backend.
- **Actual Impact:** Potential race condition with non-Redis cache backends; duplicate job scheduling.
- **Recommended Fix:** Use `Rails.cache.increment` with a TTL or explicitly use Redis `SET NX EX` for the lock.

---

#### FINDING #32 - LOW: Metrics Refresh on Every Expense Create/Update
- **Epic Affected:** Epic 2 (Metrics)
- **File:** `/Users/esoto/development/expense_tracker/app/models/expense.rb`
- **Line:** 28, 179-209
- **Description:** The `trigger_metrics_refresh` callback fires on every expense create and update (when amount, date, category, or status change). During bulk imports, this can schedule hundreds of background jobs, even with the 3-second debounce.
- **Expected Impact:** Bulk operations should use a single post-operation refresh.
- **Actual Impact:** Job queue saturation during bulk imports. Even with debouncing, the cache write/check operations themselves add overhead per save.
- **Recommended Fix:** Add a class-level flag to suppress callbacks during bulk operations:
  ```ruby
  cattr_accessor :suppress_metrics_refresh, default: false

  def trigger_metrics_refresh
    return if self.class.suppress_metrics_refresh
    # ... existing logic
  end
  ```

---

### Area 4: Frontend Performance

#### FINDING #21 - MEDIUM: VirtualScrollController innerHTML Pattern
- **Epic Affected:** Epic 3 (Virtual Scroll)
- **File:** `/Users/esoto/development/expense_tracker/app/javascript/controllers/virtual_scroll_controller.js`
- **Line:** ~221, ~252, ~385
- **Description:** `updateVisibleItems` clears `innerHTML` and re-clones DOM nodes via `cloneNode(true)` on every scroll update. It also dispatches fake `turbo:load` events in `reattachControllers` which is unreliable for Stimulus controller reconnection.
- **Expected Impact:** DOM node recycling pattern (move existing nodes, update content only) as implemented in `dashboard_virtual_scroll_controller.js`.
- **Actual Impact:** Forced layout reflow on every scroll, GC pressure from discarded DOM nodes, potential Stimulus controller lifecycle issues.
- **Recommended Fix:** Adopt the node pool pattern already implemented in `dashboard_virtual_scroll_controller.js`:
  ```javascript
  // Recycle nodes instead of recreating
  node.style.transform = `translateY(${offset}px)`;
  this.updateNodeContent(node, item);
  ```

---

#### FINDING #22 - MEDIUM: Chart.js Full Bundle Registration
- **Epic Affected:** Epic 2 (Dashboard Charts)
- **File:** `/Users/esoto/development/expense_tracker/app/javascript/controllers/chart_controller.js`
- **Line:** 4
- **Description:** `Chart.register(...registerables)` registers every Chart.js component (all chart types, scales, plugins, elements). The application only uses bar, line, and doughnut charts.
- **Expected Impact:** Register only needed components to reduce JS payload.
- **Actual Impact:** ~60KB of unused Chart.js components loaded and initialized.
- **Recommended Fix:**
  ```javascript
  import { Chart, BarController, LineController, DoughnutController,
           CategoryScale, LinearScale, BarElement, LineElement,
           PointElement, ArcElement, Tooltip, Legend } from 'chart.js';
  Chart.register(BarController, LineController, DoughnutController,
                 CategoryScale, LinearScale, BarElement, LineElement,
                 PointElement, ArcElement, Tooltip, Legend);
  ```
  Note: Since Chart.js is loaded via CDN importmap (line 10 of `config/importmap.rb`), tree-shaking is not available. Consider switching to a self-hosted ESM build for selective imports.

---

#### FINDING #23 - MEDIUM: setTimeout Polling for Chart.js Availability
- **Epic Affected:** Epic 2 (Dashboard Sparklines)
- **File:** `/Users/esoto/development/expense_tracker/app/javascript/controllers/sparkline_controller.js`
- **Line:** ~65
- **Description:** `waitForChartJS` polls with `setTimeout` up to 20 times at 100ms intervals (2 seconds total) waiting for Chart.js to be available. This is a workaround for CDN loading timing.
- **Expected Impact:** Use dynamic `import()` with a promise, or ensure Chart.js is loaded before Stimulus controllers connect.
- **Actual Impact:** 2-second worst-case delay before sparklines render; CPU overhead from repeated checks.
- **Recommended Fix:** Use `import()` to dynamically load and chain:
  ```javascript
  async connect() {
    const { Chart } = await import("chart.js");
    this.renderSparkline(Chart);
  }
  ```

---

#### FINDING #27 - MEDIUM: DOM Node Leak in Notification Appending
- **Epic Affected:** Epic 3 (Sync Sessions)
- **File:** `/Users/esoto/development/expense_tracker/app/javascript/controllers/sync_sessions_controller.js`
- **Line:** ~223
- **Description:** `showNotification` appends notification elements to `document.body` but does not track them for cleanup in `disconnect`. If the controller connects/disconnects multiple times or receives many sync events, notification DOM nodes accumulate.
- **Expected Impact:** Notifications should be cleaned up on controller disconnect or use a dedicated container with `innerHTML` replacement.
- **Actual Impact:** Gradual DOM node accumulation over long sessions.
- **Recommended Fix:** Track created notification elements and remove them in `disconnect()`, or use a fixed notification container.

---

#### FINDING #30 - LOW: Global Keyboard Listener
- **Epic Affected:** Epic 3 (Batch Selection)
- **File:** `/Users/esoto/development/expense_tracker/app/javascript/controllers/batch_selection_controller.js`
- **Line:** 78
- **Description:** `setupKeyboardNavigation` adds a `keydown` listener to `document`. While the cleanup is properly handled in `disconnect`, having a global listener processes every keypress even when batch selection is not the user's focus.
- **Expected Impact:** Scope the listener to the controller's element.
- **Actual Impact:** Minor overhead; event handler fires on every keypress globally.
- **Recommended Fix:** Use Stimulus's built-in `data-action="keydown@document->batch-selection#handleKeydown"` or scope to the controller element.

---

### Area 5: ActionCable Performance

#### FINDING #13 - HIGH: Debug `puts` Statements in Production Code
- **Epic Affected:** Epic 3 (Broadcasting)
- **File:** `/Users/esoto/development/expense_tracker/app/services/broadcast_reliability_service.rb`
- **Line:** 48-52
- **Description:** Multiple `puts` statements are left in the `broadcast_with_retry` method. These write directly to stdout on every broadcast attempt, bypassing log levels and adding unnecessary I/O overhead in production.
- **Code:**
  ```ruby
  puts "[BROADCAST_DEBUG] Starting broadcast_with_retry with priority: #{priority}"
  # ...
  puts "[BROADCAST_DEBUG] Priority validated"
  ```
- **Expected Impact:** No stdout output; use `Rails.logger.debug` only (which is already present on the adjacent lines).
- **Actual Impact:** Stdout pollution; minor I/O overhead per broadcast; string interpolation cost.
- **Recommended Fix:** Remove all `puts` statements. The `Rails.logger.debug` calls on lines 49 and 52 already serve the same purpose.

---

#### FINDING #15 - HIGH: Per-Expense Broadcasting After Bulk Update
- **Epic Affected:** Epic 3 (Bulk Operations)
- **File:** `/Users/esoto/development/expense_tracker/app/services/bulk_operations/categorization_service.rb`
- **Line:** 95-110
- **Description:** After performing a bulk `update_all` (which is efficient), the service then calls `find_each` to load and broadcast each expense individually via ActionCable. For 100 expenses, this fires 100 separate broadcasts.
- **Code:**
  ```ruby
  def broadcast_categorization_updates(expenses)
    expenses.includes(:category).find_each do |expense|
      ActionCable.server.broadcast("expenses_#{expense.email_account_id}", {
        action: "categorized",
        expense_id: expense.id,
        # ...
      })
    end
  end
  ```
- **Expected Impact:** Single batch broadcast with all affected expense IDs.
- **Actual Impact:** N ActionCable broadcasts instead of 1, plus N database reads via `find_each`.
- **Recommended Fix:**
  ```ruby
  def broadcast_categorization_updates(expenses)
    grouped = expenses.group_by(&:email_account_id)
    grouped.each do |account_id, account_expenses|
      ActionCable.server.broadcast("expenses_#{account_id}", {
        action: "bulk_categorized",
        expense_ids: account_expenses.map(&:id),
        category_id: category_id,
        category_name: Category.find(category_id)&.name
      })
    end
  end
  ```

---

#### FINDING #29 - LOW: Verbose Connection Logging in SyncStatusChannel
- **Epic Affected:** Epic 3 (Sync)
- **File:** `/Users/esoto/development/expense_tracker/app/channels/sync_status_channel.rb`
- **Line:** Various
- **Description:** Security logging fires on every WebSocket connection and disconnection event. While good for audit trails, the volume can impact log storage and parsing.
- **Expected Impact:** Log at `debug` level for connection events, `info` for security-relevant events only.
- **Actual Impact:** High log volume in production.
- **Recommended Fix:** Reduce logging verbosity; use `debug` level for routine connection/disconnection events.

---

### Area 6: Service Layer

#### FINDING #14 - HIGH: ThreadPoolExecutor Created Per Engine Instance
- **Epic Affected:** Epic 2 (Categorization)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/engine.rb`
- **Line:** ~432
- **Description:** The Categorization Engine creates a `Concurrent::ThreadPoolExecutor` with up to 10 threads each time an engine instance is created. If the engine is instantiated per-request or per-job, this leads to thread accumulation and resource exhaustion.
- **Expected Impact:** Thread pool should be a singleton or class-level resource with proper lifecycle management.
- **Actual Impact:** Potential thread leak; each engine instance reserves up to 10 OS threads.
- **Recommended Fix:** Use a class-level thread pool:
  ```ruby
  class Engine
    THREAD_POOL = Concurrent::ThreadPoolExecutor.new(
      min_threads: 2,
      max_threads: 10,
      max_queue: 100,
      fallback_policy: :caller_runs
    )

    def initialize
      @thread_pool = THREAD_POOL
    end
  end
  ```

---

#### FINDING #18 - MEDIUM: Cascading Cache Invalidation on Expense Commit
- **Epic Affected:** All Epics
- **File:** `/Users/esoto/development/expense_tracker/app/models/expense.rb`
- **Line:** 27-29
- **Description:** Every expense `after_commit` fires three cascading operations:
  1. `clear_dashboard_cache` -- calls `delete_matched("dashboard_*")`
  2. `trigger_metrics_refresh` -- schedules a background job
  3. (on update with `deleted_at` change) `trigger_metrics_refresh_for_deletion`

  These fire regardless of whether the expense change is actually visible on the dashboard.
- **Expected Impact:** Targeted invalidation based on what actually changed.
- **Actual Impact:** Excessive cache thrashing and job scheduling on every expense modification.
- **Recommended Fix:** Use conditional invalidation:
  ```ruby
  after_commit :clear_dashboard_cache, if: :dashboard_relevant_change?

  def dashboard_relevant_change?
    saved_change_to_amount? || saved_change_to_transaction_date? ||
      saved_change_to_category_id? || saved_change_to_status?
  end
  ```

---

#### FINDING #24 - MEDIUM: O(m*n) Memory in Levenshtein Distance
- **Epic Affected:** Epic 2 (Categorization)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/matchers/fuzzy_matcher.rb`
- **Line:** ~400
- **Description:** The `levenshtein_distance` method creates a full 2D matrix `Array.new(m+1) { Array.new(n+1) }`. For two strings of length 100, this allocates a 101x101 matrix (10,201 cells). The standard optimization uses only two rows.
- **Expected Impact:** O(min(m,n)) memory using two-row approach.
- **Actual Impact:** Memory proportional to product of string lengths. For merchant names this is typically small, but could spike for longer descriptions.
- **Recommended Fix:** Use the two-row optimization:
  ```ruby
  def levenshtein_distance(s, t)
    m, n = s.length, t.length
    return m if n.zero?
    return n if m.zero?

    prev_row = (0..n).to_a
    curr_row = Array.new(n + 1, 0)

    (1..m).each do |i|
      curr_row[0] = i
      (1..n).each do |j|
        cost = s[i-1] == t[j-1] ? 0 : 1
        curr_row[j] = [curr_row[j-1] + 1, prev_row[j] + 1, prev_row[j-1] + cost].min
      end
      prev_row, curr_row = curr_row, prev_row
    end
    prev_row[n]
  end
  ```

---

#### FINDING #28 - LOW: Unnecessary Eager Loading of `ml_suggested_category`
- **Epic Affected:** Epic 3 (Dashboard)
- **File:** `/Users/esoto/development/expense_tracker/app/services/dashboard_expense_filter_service.rb`
- **Line:** 150
- **Description:** `build_dashboard_scope` includes `:ml_suggested_category` in the eager loading, but this association is only accessed in the expanded view mode, not in the default compact view.
- **Code:**
  ```ruby
  .includes(:category, :email_account, :ml_suggested_category)
  ```
- **Expected Impact:** Conditionally include based on view mode.
- **Actual Impact:** Extra JOIN or subquery for data that may not be rendered.
- **Recommended Fix:**
  ```ruby
  includes_list = [:category, :email_account]
  includes_list << :ml_suggested_category if @view_mode == "expanded"
  Expense.for_list_display.includes(*includes_list).where(...)
  ```

---

#### FINDING #31 - LOW: Unbounded Normalization Cache in FuzzyMatcher
- **Epic Affected:** Epic 2 (Categorization)
- **File:** `/Users/esoto/development/expense_tracker/app/services/categorization/matchers/fuzzy_matcher.rb`
- **Line:** ~703
- **Description:** `TextNormalizer` maintains an `@normalization_cache` hash that checks `size < 1000` before adding entries but never evicts old entries. Once it reaches 1000, it simply stops caching new entries, leaving potentially stale entries in memory indefinitely.
- **Expected Impact:** LRU eviction policy or bounded cache with proper eviction.
- **Actual Impact:** Memory stays allocated for up to 1000 cached normalizations; no eviction means older patterns are never replaced with more relevant ones.
- **Recommended Fix:** Use an LRU cache implementation or reset the cache periodically:
  ```ruby
  def normalize(text)
    if @cache.size >= MAX_CACHE_SIZE
      @cache.shift # Remove oldest entry (Ruby hashes maintain insertion order)
    end
    @cache[text] ||= perform_normalization(text)
  end
  ```

---

## Priority Remediation Plan

### Phase 1: Quick Wins (1-2 days)
1. **FINDING #3** -- Replace `flushdb` with namespaced key deletion (prevents data loss)
2. **FINDING #13** -- Remove debug `puts` statements
3. **FINDING #9** -- Remove redundant `Category.exists?` validation
4. **FINDING #17** -- Enable ExpenseFilterService caching in production
5. **FINDING #26** -- Memoize `current_user_email_accounts.pluck(:id)`

### Phase 2: High-Impact Fixes (3-5 days)
6. **FINDING #1** -- Pass metrics to `calculate_trends` instead of recalculating
7. **FINDING #2** -- Pre-calculate total for percentage_of_total
8. **FINDING #6** -- Consolidate aggregate queries with `pick`
9. **FINDING #4** -- Fix N+1 in `store_bulk_operation`
10. **FINDING #7** -- Use PostgreSQL `PERCENTILE_CONT` for median
11. **FINDING #15** -- Batch broadcast instead of per-expense

### Phase 3: Architectural Improvements (1-2 weeks)
12. **FINDING #5** -- Refactor dashboard action to reduce query count
13. **FINDING #10, #11** -- Implement cache version key approach
14. **FINDING #12** -- Audit and prune database indexes
15. **FINDING #14** -- Make ThreadPoolExecutor a singleton
16. **FINDING #19** -- Reduce MetricsCalculationJob period combinations
17. **FINDING #18** -- Conditional cache invalidation

### Phase 4: Frontend Optimization (1 week)
18. **FINDING #21** -- Adopt node pool pattern in VirtualScrollController
19. **FINDING #22** -- Selective Chart.js component registration
20. **FINDING #23** -- Replace setTimeout polling with dynamic import

---

## Appendix: Files Audited

| File | Lines | Area |
|------|-------|------|
| `app/services/metrics_calculator.rb` | 562 | Database, Caching |
| `app/services/dashboard_service.rb` | 135 | Database, Caching |
| `app/services/expense_filter_service.rb` | 449 | Database, Caching |
| `app/services/dashboard_expense_filter_service.rb` | 429 | Database, Caching |
| `app/services/categorization/bulk_categorization_service.rb` | ~350 | Database, Service Layer |
| `app/services/categorization/engine.rb` | 1047 | Service Layer |
| `app/services/categorization/matchers/fuzzy_matcher.rb` | 853 | Service Layer |
| `app/services/categorization/pattern_cache.rb` | ~450 | Caching |
| `app/services/bulk_operations/categorization_service.rb` | 113 | Database, ActionCable |
| `app/services/broadcast_reliability_service.rb` | ~200 | ActionCable |
| `app/controllers/expenses_controller.rb` | 895 | Database, Frontend |
| `app/models/expense.rb` | 239 | Database, Caching |
| `app/models/category.rb` | ~60 | Database |
| `app/models/concerns/expense_query_optimizer.rb` | ~80 | Database |
| `app/channels/sync_status_channel.rb` | ~200 | ActionCable |
| `app/jobs/metrics_calculation_job.rb` | ~250 | Background Jobs |
| `app/jobs/metrics_refresh_job.rb` | ~150 | Background Jobs |
| `app/javascript/controllers/virtual_scroll_controller.js` | ~400 | Frontend |
| `app/javascript/controllers/dashboard_virtual_scroll_controller.js` | ~350 | Frontend |
| `app/javascript/controllers/chart_controller.js` | ~100 | Frontend |
| `app/javascript/controllers/sparkline_controller.js` | ~120 | Frontend |
| `app/javascript/controllers/batch_selection_controller.js` | ~250 | Frontend |
| `app/javascript/controllers/sync_sessions_controller.js` | ~250 | Frontend |
| `db/schema.rb` | 765 | Database |
| `config/importmap.rb` | 13 | Frontend |

---

*Report generated by Claude Opus 4.6 Performance Analyst on 2026-02-14*
