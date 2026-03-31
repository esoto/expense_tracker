I now have a comprehensive view of the entire application. Here is the complete end-to-end testing scenario inventory.

---

# Complete End-to-End Testing Scenario Inventory

**Application:** Expense Tracker (Rails 8.1.2)
**Total Estimated Scenarios:** ~320
**Testing Surface:** 38 controllers, 49 Stimulus controllers, 3 API namespaces, full admin panel

---

## 1. Authentication & Authorization

**Pages/Routes:** `GET /admin/login`, `POST /admin/login`, `DELETE /admin/logout`, `GET /admin/logout`
**Priority:** Critical
**Estimated scenarios:** 22

### Scenarios:
1. Admin user visits `/admin/login` and sees the login form rendered under the `admin_login` layout
2. Admin user submits valid credentials and is redirected to `/admin/patterns` (the admin root)
3. Admin user submits an invalid email or wrong password and sees the "Invalid email or password" flash alert inline on the login page
4. Admin user submits credentials for a locked account and sees the account-locked message
5. Admin user who is already signed in navigates to `/admin/login` and is redirected away with "already signed in" notice
6. Admin user clicks the logout link and is redirected back to `/admin/login` with "signed out" notice, session destroyed
7. Admin user's session expires (SESSION_DURATION = 2 hours) and they are redirected to login on next request
8. Unauthenticated user visits any protected main app route (e.g., `/expenses`) and is redirected to `/admin/login` with "Please sign in to continue" alert; original URL is preserved and user is redirected there after successful login
9. Admin user triggers failed login 5 times in a row (MAX_FAILED_LOGIN_ATTEMPTS) and account becomes locked
10. Locked account automatically unlocks after LOCK_DURATION (30 minutes) and login succeeds
11. Rate limiter blocks login after 10 attempts from the same IP within 15 minutes; user sees "Too many login attempts" message
12. Admin user with `read_only` role accesses a write-only admin action (e.g., create pattern) and is blocked with a permission error
13. Admin user with `moderator` role accesses statistics/analytics and is allowed
14. Admin user with `admin` role can perform all CRUD and management operations
15. Admin user with `super_admin` role can access all features
16. Login form remembers email value when submission fails (password wrong but email preserved)
17. Session token is regenerated on successful login (session fixation prevention: `reset_session` is called)
18. GET logout also destroys the session (useful for link-based logout)
19. Visiting admin root `/admin` while unauthenticated redirects to login
20. Visiting analytics dashboard while unauthenticated redirects to login
21. Admin user with password shorter than 12 characters cannot be created (validation enforced)
22. Admin user password must include uppercase, lowercase, digit, and special character (validation enforced)

---

## 2. Dashboard

**Pages/Routes:** `GET /` (root), `GET /expenses/dashboard`
**Priority:** Critical
**Estimated scenarios:** 24

### Scenarios:
1. Authenticated user visits root `/` and is served the dashboard page
2. Dashboard displays four metric cards: yearly total, monthly total, weekly total, and daily total
3. Dashboard metrics display correct formatted amounts for CRC, USD, and EUR currencies
4. Dashboard shows a "Recent Expenses" widget with up to 15 expenses by default
5. Dashboard shows category breakdown list with amounts per category
6. Dashboard shows monthly trend chart (Chart.js) with the last 12 months of data
7. Dashboard shows bank breakdown totals grouped by bank name
8. Dashboard shows top merchants list
9. Dashboard shows sync status widget reflecting the last completed or active sync session
10. User clicks a metric card (e.g., "this month") and is navigated to `/expenses?period=month&filter_type=dashboard_metric`; the expense list reflects the period filter
11. Dashboard expense widget supports compact and expanded view modes via the view toggle button
12. Dashboard "Recent Expenses" list reflects currently applied period and category filters from the dashboard filter chips
13. Dashboard loads when no email account exists (all metric values default to zero, no errors)
14. Dashboard loads when no expenses exist yet (zero state with empty charts and list)
15. Dashboard filter chips update the expense list below via Turbo Streams without a full page reload
16. Dashboard filter persistence: filter selection survives a page refresh (via `filter_persistence_controller`)
17. Budget indicators appear on the dashboard when active budgets exist for the current period
18. Animated metric counters play on page load (`animated_metric_controller`)
19. Sparkline charts render correctly in summary cards
20. Tooltip controller shows tooltips on metric card hover
21. Dashboard AJAX request for partial update (`?partial=expenses_list`) returns only the expense list partial
22. Dashboard loads within 200ms initial page load (performance benchmark)
23. Dashboard correctly displays trend arrows (up/down) comparing current period to previous period
24. Dashboard sync widget shows "in progress" state when an active sync session exists

---

## 3. Expense CRUD

**Pages/Routes:** `GET /expenses`, `GET /expenses/new`, `POST /expenses`, `GET /expenses/:id`, `GET /expenses/:id/edit`, `PATCH/PUT /expenses/:id`, `DELETE /expenses/:id`, `POST /expenses/:id/duplicate`
**Priority:** Critical
**Estimated scenarios:** 30

### Scenarios:
1. User visits `/expenses/new` and sees the form with fields: amount, currency, transaction date, merchant name, description, category (dropdown), email account (dropdown), notes
2. User submits the new expense form with all valid fields and is redirected to the expense show page with a "created" flash notice
3. New manually created expense has `bank_name` set to "Manual Entry" and `status` set to "processed" automatically
4. New expense defaults to CRC currency if no currency is specified
5. User submits the new expense form with a blank amount and sees the validation error inline
6. User submits with a negative or zero amount and sees the "must be greater than 0" validation error
7. User submits with a blank transaction date and sees the validation error
8. User submits with an invalid (non-existent) category ID and sees the "category must exist" validation error
9. User visits an expense show page (`/expenses/:id`) and sees all expense fields, category, ML confidence, and inline actions
10. User visits the expense edit form and updates the amount, then is redirected to show page with "updated" flash notice
11. User updates the merchant name and the `merchant_normalized` field is automatically normalized (lowercase, no special chars)
12. User updates the transaction date and the metrics refresh job is enqueued for both old and new dates
13. User deletes an expense; the expense is soft-deleted (not hard deleted) and an undo entry is created in `undo_histories`
14. After deletion, user sees the undo notification in the flash with a countdown timer
15. User clicks the undo link within the time window and the expense is restored; expense list refreshes via Turbo Stream
16. User attempts to delete an expense belonging to another user's email account and is blocked with "not authorized"
17. User attempts to access an expense that does not exist and is redirected to the expense list with "not found" flash
18. User duplicates an expense via `POST /expenses/:id/duplicate`; a new expense is created with today's date, `pending` status, and ML fields cleared
19. Duplicate action via Turbo Stream prepends the new row to the expense table without a full page reload
20. Expense show page correctly displays the ML confidence badge at each confidence level: none, high (>=85%), medium (>=70%), low (>=50%), very low (<50%)
21. User can update an expense status to `pending`, `processed`, `failed`, or `duplicate` via the inline status update form
22. Inline status update via Turbo Stream replaces the status badge and actions partial without a full page reload
23. Submitting an invalid status value (e.g., `?status=unknown`) returns a validation error, no state change
24. Expense with `email_account_id: nil` (orphaned or manual) is accessible and editable by any authenticated user
25. Category field in the expense form shows all categories sorted by name
26. Email account field in the form shows all accounts sorted by email
27. Expense with long description (over 100 characters) is handled gracefully in the JSON virtual scroll response (truncated to 100 chars)
28. User navigates from the dashboard card to the expense list; the `@from_dashboard` flag is set and filter description is displayed
29. Expense list renders correctly with both HTML and JSON format responses
30. Creating expense with `currency: ""` defaults to CRC, not a validation error

---

## 4. Expense List — Index, Filtering, Sorting, Pagination

**Pages/Routes:** `GET /expenses`, `GET /expenses/virtual_scroll`
**Priority:** Critical
**Estimated scenarios:** 28

### Scenarios:
1. User visits `/expenses` and sees a paginated list (50 per page by default) with summary stats displayed
2. Expense list shows total count, sum of amounts, and category breakdown for current filter set
3. User applies a category filter via the filter chips UI and the list reloads via Turbo Stream showing only matching expenses
4. User applies a bank filter and the list filters to expenses from that bank
5. User applies a date range filter (`start_date` + `end_date`) and sees only expenses in that range
6. User applies a period filter (`period=month`) and sees expenses for the current month
7. User applies a text search query (`search_query`) and sees only matching expenses
8. User applies a minimum amount filter and sees only expenses above that threshold
9. User applies a maximum amount filter and sees only expenses below that threshold
10. User applies multiple filters simultaneously (category + bank + date range) and the combination works correctly
11. User applies a status filter (`status=pending`) and sees only pending expenses
12. User clears all filters and the full unfiltered list is restored
13. User sorts expenses by date (ascending and descending) and list reorders correctly
14. User sorts by amount (ascending and descending)
15. User navigates to page 2 of paginated results and sees the correct set of expenses
16. Pagy navigation controls (previous/next, page numbers) are rendered and functional
17. With zero expenses matching filters, an appropriate empty state is shown (not an error page)
18. Filter description string is rendered correctly in the UI when filters are active (e.g., "Gastos de este mes • Categoría: Supermercado")
19. `GET /expenses/virtual_scroll` with cursor-based pagination returns up to 30 items with `has_more` and `next_cursor` in JSON
20. Virtual scroll endpoint returns `total_count` and performance metrics (`query_time_ms`, `index_used`) in response
21. Virtual scroll endpoint with an invalid cursor gracefully falls back to the first page
22. Filter persistence controller saves and restores active filters from session storage across navigation
23. Filter chips show the active filter tags with a remove button for each active filter
24. Category filter accepts an array of category IDs (`category_ids[]`) for multi-category filtering
25. Bank filter accepts an array of bank names (`banks[]`) for multi-bank filtering
26. Single `category` query param (legacy) is converted to a `category_ids` array internally
27. Single `bank` query param (legacy) is appended to the `banks` array internally
28. Scroll-to-specific-expense behavior works when `scroll_to` param is provided (expense row highlighted)

---

## 5. Mobile Card Layout (PER-133 — New Feature)

**Pages/Routes:** `GET /expenses`, `GET /expenses/dashboard`
**Priority:** Critical (new feature — the primary ticket)
**Estimated scenarios:** 20

### Scenarios:
1. On a mobile viewport (below 768px), the expense list switches from a table layout to a card-based layout
2. Each expense card on mobile displays: merchant name, amount, category badge, date, and status badge
3. On desktop (768px and above), the table layout is rendered; cards are not visible
4. Mobile card layout uses the Financial Confidence color palette (teal primary, no blue colors)
5. Mobile cards match the card component style: `bg-white rounded-xl shadow-sm border border-slate-200`
6. Mobile card for an uncategorized expense shows a visual indicator for the missing category
7. Tapping a mobile card navigates to the expense show page
8. Inline actions (edit, delete) on mobile cards are accessible via a touch-friendly interaction (tap to reveal or visible buttons)
9. Category confidence badge is rendered correctly on mobile cards at each confidence level
10. Mobile card layout correctly handles long merchant names without breaking the layout (overflow handling)
11. Mobile card layout correctly handles very large CRC amounts (e.g., ₡1,500,000) without truncation
12. View toggle button on the expense list works on mobile (compact vs. expanded within card layout context)
13. Batch selection checkboxes on mobile card layout are tappable and correctly sized for touch
14. Selecting a card updates the batch selection toolbar count
15. Dashboard's "Recent Expenses" widget on mobile renders in card layout, not table layout
16. Mobile card layout is accessible: cards have appropriate ARIA roles and labels
17. Mobile card layout maintains keyboard navigation support (Tab key to cycle through cards, Enter to open)
18. Swiping or scrolling a long list of mobile cards performs smoothly (no jank)
19. Filter chips UI on mobile collapses into a scrollable horizontal row without overflow
20. After applying a filter on mobile, the card list updates via Turbo Stream without a full page reload

---

## 6. Bulk Operations (Expense List)

**Pages/Routes:** `POST /expenses/bulk_categorize`, `POST /expenses/bulk_update_status`, `DELETE /expenses/bulk_destroy`
**Priority:** High
**Estimated scenarios:** 24

### Scenarios:
1. User selects individual expense checkboxes via the batch selection controller; the selection counter and toolbar appear
2. User clicks the master checkbox to select all visible expenses; all rows are selected and counter shows total
3. User deselects the master checkbox; all selections are cleared and toolbar hides
4. User clears selection via the "Clear selection" button in the toolbar
5. Selection state is maintained when the user toggles between compact and expanded view modes
6. `POST /expenses/bulk_categorize` with valid `expense_ids` and `category_id` updates categories and returns success JSON with `affected_count`
7. Bulk categorize with ML correction tracking creates pattern learning events for each affected expense
8. Bulk categorize with more than a threshold count is processed as a background job (returns `background: true` and `job_id`)
9. `POST /expenses/bulk_categorize` with an empty `expense_ids` array returns an error response
10. `POST /expenses/bulk_categorize` with a non-existent category ID returns an error
11. `POST /expenses/bulk_update_status` with valid `expense_ids` and `status=processed` updates all statuses
12. `POST /expenses/bulk_update_status` with an invalid status value returns an error
13. `DELETE /expenses/bulk_destroy` soft-deletes all selected expenses and returns `undo_id` in JSON
14. After bulk delete, an undo notification is shown; clicking undo restores all deleted expenses
15. Bulk operation with expense IDs that partially belong to another user's account fails for unauthorized IDs only
16. Unauthenticated request to any bulk operation endpoint returns a 401 JSON response
17. Bulk operation where all expense IDs are valid processes all successfully (no partial failures)
18. Bulk operation returns `failures` array for any expenses that could not be processed
19. Bulk categorize broadcasts WebSocket updates for each successfully categorized expense
20. Bulk delete broadcasts WebSocket updates for each deleted expense
21. Keyboard shortcut to open bulk actions menu works when expenses are selected
22. `Escape` key clears the selection toolbar
23. Bulk operations modal displays the correct count of selected expenses before confirming
24. After a bulk operation completes, the expense list refreshes and selection is cleared

---

## 7. ML Categorization — Inline Actions

**Pages/Routes:** `POST /expenses/:id/correct_category`, `POST /expenses/:id/accept_suggestion`, `POST /expenses/:id/reject_suggestion`
**Priority:** High
**Estimated scenarios:** 18

### Scenarios:
1. Expense with an ML suggested category shows an "Accept" and "Reject" button in the inline actions area
2. User clicks "Accept suggestion" — expense's `category_id` is updated to `ml_suggested_category_id`, confidence set to 1.0, correction count incremented
3. After accepting, the category partial is replaced via Turbo Stream with the updated category badge
4. User clicks "Accept suggestion" on an expense with no ML suggestion and sees the "no suggestion available" error
5. User clicks "Reject suggestion" — `ml_suggested_category_id` is cleared, expense remains with its existing category
6. After rejecting, the category partial is replaced via Turbo Stream
7. User submits "Correct category" with a valid category ID — `reject_ml_suggestion!` is called, a `PatternLearningEvent` is created, confidence set to 1.0
8. Correct category with a blank category ID returns the "category ID required" error
9. Correct category with a non-existent category ID returns the "invalid category ID" error and no changes are made
10. Correct category via Turbo Stream replaces the category partial inline without a page reload
11. Correct category via JSON format returns `{ success: true, expense: {...}, color: "..." }`
12. Correct category via HTML format redirects back to the expense page with a success notice
13. ML confidence badge displays "high confidence" styling for ml_confidence >= 0.85
14. ML confidence badge displays "medium" for ml_confidence >= 0.70
15. ML confidence badge displays "low" for ml_confidence >= 0.50
16. ML confidence badge displays "very low" for ml_confidence < 0.50
17. Expense with `needs_review?` flag shows a visual "needs review" indicator
18. After correcting a category, the expense's `ml_last_corrected_at` timestamp is updated

---

## 8. Bulk Categorization Workflow

**Pages/Routes:** `GET /bulk_categorizations`, `GET /bulk_categorizations/:id`, `POST /bulk_categorizations/categorize`, `POST /bulk_categorizations/suggest`, `POST /bulk_categorizations/preview`, `POST /bulk_categorizations/auto_categorize`, `GET /bulk_categorizations/export`, `POST /bulk_categorizations/:id/undo`
**Priority:** High
**Estimated scenarios:** 18

### Scenarios:
1. User visits `/bulk_categorizations` and sees uncategorized expenses grouped by similarity
2. Grouped expenses display: group name, count of expenses, total amount, and confidence score
3. High-confidence groups (>0.8) have a visual indicator distinguishing them from low-confidence groups
4. Bulk categorization index shows statistics: total groups, total expenses, high-confidence group count, and total amount
5. When no uncategorized expenses exist, an appropriate empty state message is shown
6. When a grouping error occurs, the page degrades gracefully showing an ungrouped list and a warning flash
7. User submits a category assignment for a group of expenses; all expenses in the group are categorized
8. `POST /bulk_categorizations/suggest` returns ML category suggestions for a set of expense IDs
9. `POST /bulk_categorizations/preview` returns a preview of what would be categorized without making changes
10. `POST /bulk_categorizations/auto_categorize` runs auto-categorization for all uncategorized expenses and shows a result summary
11. User exports the bulk categorization results via `GET /bulk_categorizations/export`; a downloadable file is returned
12. User views a specific bulk operation record at `/bulk_categorizations/:id` showing affected expenses and their new categories
13. `POST /bulk_categorizations/:id/undo` reverses a completed bulk categorization, restoring original (null) categories
14. After undo, the affected expenses return to "uncategorized" state
15. Pagination applies when more than 100 uncategorized expenses exist (`page` parameter)
16. Expense grouping uses the `BulkCategorization::GroupingService` — groups with similar merchants or descriptions are combined
17. Category dropdown in the bulk categorization form includes parent category hierarchy
18. User selects a category and submits; a loading indicator is shown while processing

---

## 9. Email Accounts

**Pages/Routes:** `GET /email_accounts`, `GET /email_accounts/new`, `POST /email_accounts`, `GET /email_accounts/:id`, `GET /email_accounts/:id/edit`, `PATCH/PUT /email_accounts/:id`, `DELETE /email_accounts/:id`
**Priority:** High
**Estimated scenarios:** 14

### Scenarios:
1. User visits `/email_accounts` and sees a list of all configured email accounts
2. User visits the new email account form and sees fields for email, bank name, provider, active status, password, server, and port
3. User submits a new account with a password; `encrypted_password` is saved (not plaintext)
4. User submits a new account with custom IMAP server and port; these are stored in the `settings` JSON field
5. User submits a new account without custom server/port; IMAP settings block is not added to `settings`
6. User submits the form with a missing required field and sees the validation error
7. User visits the show page for an email account and sees account details
8. User updates the email account; if a new password is provided, `encrypted_password` is updated
9. User updates the account without providing a new password; the existing encrypted password is preserved
10. User updates custom IMAP settings by providing server and port; existing settings are merged (not replaced)
11. User deletes an email account and is redirected to the accounts list with a success notice
12. Deleting an email account nullifies `email_account_id` on its associated expenses (they become orphaned/manual expenses)
13. Email account with `active: false` does not appear in the bank names dropdown on the expense list
14. Email accounts with `active: true` appear in the bank filter dropdown on the expense list

---

## 10. Email Sync — Sync Sessions

**Pages/Routes:** `GET /sync_sessions`, `GET /sync_sessions/:id`, `POST /sync_sessions`, `POST /sync_sessions/:id/cancel`, `POST /sync_sessions/:id/retry`, `GET /sync_sessions/status`, `POST /expenses/sync_emails`
**Priority:** High
**Estimated scenarios:** 20

### Scenarios:
1. User visits `/sync_sessions` and sees the active sync session (if any), recent sessions list, email accounts, and summary stats
2. Sync sessions index shows today's sync count, monthly expenses detected, and last completed session
3. User creates a new sync session via `POST /sync_sessions` with an `email_account_id`; session is created and the sync widget updates via Turbo Stream
4. User creates a sync session without specifying an `email_account_id` (syncs all active accounts)
5. Creating a sync session when the sync limit is exceeded returns a rate limit error; user sees appropriate message
6. User views a sync session detail page (`/sync_sessions/:id`) and sees per-account progress details
7. Sync session detail page is only accessible to the session's owner (authorization check)
8. User cancels an active sync session; status changes to "cancelled" and the UI updates
9. Attempting to cancel an already-completed (non-active) session redirects with "not active" error
10. User retries a failed sync session; a new session is created and the user is redirected to the sessions list
11. `GET /sync_sessions/status` returns the current status of the most recent session
12. `GET /api/sync_sessions/:id/status` (API) returns JSON with progress percentage, processed/total email counts, time remaining, and per-account breakdown
13. Sync status response is cached for 5 seconds (race condition TTL = 2 seconds)
14. `POST /expenses/sync_emails` triggers `SyncService.sync_emails` and redirects to dashboard with success notice
15. `POST /expenses/sync_emails` with a sync error redirects with the error message from `SyncService::SyncError`
16. The sync widget (`_unified_widget.html.erb`) shows in-progress state with a progress bar when session is active
17. The sync widget shows "last synced X minutes ago" when no active session exists
18. Sync session index page shows active accounts count and allows selecting a specific account for targeted sync
19. WebSocket (`ActionCable`) broadcasts progress updates during an active sync session
20. Queue visualization partial (`_queue_visualization.html.erb`) renders on the sync sessions index

---

## 11. Sync Conflicts

**Pages/Routes:** `GET /sync_conflicts`, `GET /sync_conflicts/:id`, `POST /sync_conflicts/:id/resolve`, `POST /sync_conflicts/:id/undo`, `POST /sync_conflicts/:id/preview_merge`, `GET /sync_conflicts/:id/row`, `POST /sync_conflicts/bulk_resolve`
**Priority:** High
**Estimated scenarios:** 16

### Scenarios:
1. User visits `/sync_conflicts` and sees all unresolved conflicts with stats (total, pending, resolved, by type)
2. Conflict list can be filtered by `status` (pending/resolved) via query parameter
3. Conflict list can be filtered by `conflict_type` via query parameter
4. Conflict list is sorted by priority and paginated (25 per page)
5. User views a conflict detail page and sees both the existing expense and the new expense side-by-side
6. Conflict detail page shows field differences between the two versions
7. User resolves a conflict (action type: keep existing, use new, or merge) and it is marked as resolved
8. Resolved conflict row is updated via Turbo Stream without a full page reload
9. Resolving a conflict shows a toast notification with success message
10. User undoes a conflict resolution; conflict returns to unresolved state
11. Undoing a resolution via Turbo Stream updates the conflict row in the list
12. User previews a merge (`POST preview_merge`) and receives JSON showing what the merged expense would look like and what fields would change
13. `POST /sync_conflicts/bulk_resolve` resolves multiple conflicts at once; returns count of resolved and failed conflicts
14. Bulk resolve via Turbo Stream updates each conflict row individually
15. `GET /sync_conflicts/:id/row` returns the conflict row partial (used for Turbo Stream replacements)
16. Conflict list scoped to a specific sync session when `sync_session_id` param is provided

---

## 12. Sync Performance Monitoring

**Pages/Routes:** `GET /sync_performance`, `GET /sync_performance/export`, `GET /sync_performance/realtime`
**Priority:** Medium
**Estimated scenarios:** 12

### Scenarios:
1. User visits `/sync_performance` and sees metrics summary: total syncs, success rate, average duration, emails processed
2. Performance dashboard shows timeline chart with success/failure counts over time
3. Dashboard shows duration trend chart
4. Dashboard shows per-account metrics table (bank name, email, syncs, success rate, emails processed, last sync)
5. Dashboard shows error analysis: total errors, error rate, error type breakdown
6. Dashboard shows peak times: hourly and daily patterns, top 5 peak hours
7. User changes the period filter to "last hour", "last 7 days", "last 30 days", or "custom" and the data updates
8. Custom date range (`period=custom&start_date=...&end_date=...`) loads data for the specified range
9. `GET /sync_performance/export` downloads a CSV file with columns for date, session ID, account, metric type, duration, emails processed, success, error type, error message
10. Export filename includes the date range in Spanish format
11. `GET /sync_performance/realtime` returns a Turbo Stream that updates the live metrics partial
12. When no metrics exist for the selected period, all values default to zero without throwing errors

---

## 13. Admin Panel — Categorization Patterns

**Pages/Routes:** All routes under `/admin/patterns` and `/admin/composite_patterns`
**Priority:** High
**Estimated scenarios:** 32

### Scenarios:
1. Unauthenticated user visits any `/admin/patterns` route and is redirected to the admin login page
2. Admin user visits `/admin/patterns` (admin root) and sees the patterns list with statistics header (total, active, average success rate, total usage)
3. Patterns list is paginated (20 per page) with navigation controls
4. User filters patterns by type (`filter_type=regex`) and list shows only regex patterns
5. User filters patterns by category (`filter_category=<id>`) and list shows only patterns for that category
6. User filters patterns by status: active, inactive, user_created, system_created, high_confidence, successful, frequently_used
7. User searches patterns by pattern value or category name; results update (ILIKE search)
8. User sorts patterns by: type, value, category, usage, success rate, confidence, created date
9. User visits the new pattern form and creates a pattern with type, value, category, and confidence weight
10. New user-created pattern has `user_created: true` set automatically
11. Creating a regex pattern value that contains dangerous ReDoS patterns (catastrophic backtracking) is rejected as invalid
12. Creating a regex pattern validates it compiles within 0.5 seconds (timeout safety)
13. User edits an existing pattern, changes its value, and the change is saved
14. User deletes a pattern and it is removed; list updates and redirects with success notice
15. Admin user with `read_only` role cannot create, edit, or delete patterns (blocked before action)
16. Rate limiter blocks more than 30 pattern test calls per minute from the same admin user
17. Rate limiter blocks more than 5 pattern import calls per hour from the same admin user
18. User visits the pattern test page (`/admin/patterns/test`) and sees the test form with fields for description, merchant name, amount, and date
19. User submits the test form; matching patterns are displayed with their category and confidence score via Turbo Stream
20. User tests a specific pattern via `GET /admin/patterns/:id/test_single` with test text; receives match/no-match result
21. Testing with an empty test text returns a "Test text is required" error
22. Pattern show page displays performance metrics: total uses, success rate, confidence, last used, average daily uses, trend (increasing/stable/decreasing)
23. Pattern show page shows recent feedback entries (last 10) with associated expense details
24. Performance metrics are cached for 1 hour (cache key includes updated_at timestamp)
25. User imports patterns via CSV upload; success message shows imported count and skipped count
26. Dry-run import (`dry_run=true`) previews the import without making changes
27. Import with invalid CSV data redirects with error message showing import failures
28. User exports patterns to CSV; file contains all columns (type, value, category, confidence, active, usage stats)
29. Export with `export_active_only=true` limits to active patterns only
30. Export filtered by `export_category_id` limits to patterns for that category
31. Admin user visits `/admin/patterns/statistics` and sees stats filtered by category, type, or active status
32. Admin user visits `/admin/patterns/performance` and sees overall accuracy, patterns by effectiveness, category accuracy rates, time series (last 30 days), top 10 and bottom 10 performers

---

## 14. Admin Panel — Composite Patterns

**Pages/Routes:** `GET /admin/composite_patterns`, actions under `/admin/composite_patterns/:id`
**Priority:** Medium
**Estimated scenarios:** 8

### Scenarios:
1. Admin user visits `/admin/composite_patterns` and sees the list of composite patterns
2. Admin user toggles a composite pattern active/inactive via `POST /admin/composite_patterns/:id/toggle_active`
3. Toggling active status via Turbo Stream updates the pattern row in the list without a full page reload
4. Admin user tests a composite pattern via `GET /admin/composite_patterns/:id/test` with test input
5. Composite pattern test returns match/no-match result and score
6. Admin user creates a new composite pattern (form fields for name, sub-patterns, logic)
7. Admin user edits an existing composite pattern
8. Admin user deletes a composite pattern with confirmation

---

## 15. Analytics — Pattern Dashboard

**Pages/Routes:** `GET /analytics/pattern_dashboard`, `GET /analytics/pattern_dashboard/trends`, `GET /analytics/pattern_dashboard/heatmap`, `GET /analytics/pattern_dashboard/export`, `POST /analytics/pattern_dashboard/refresh`
**Priority:** High
**Estimated scenarios:** 18

### Scenarios:
1. Admin user without analytics permission (`can_access_statistics? = false`) is blocked with a 403 error
2. Admin user with analytics permission visits the dashboard and sees: overall metrics, category performance, pattern type analysis, top 10 patterns, bottom 10 patterns, learning metrics, recent activity
3. Overall metrics card shows total patterns, active count, average success rate, and total uses
4. Category performance section shows accuracy and usage per category
5. Pattern type analysis shows effectiveness breakdown by type (exact match, regex, etc.)
6. Top 10 and bottom 10 performing patterns are listed with usage and success rate
7. User applies the default 30-day time range filter
8. User changes time range to "today", "week", "month", "quarter", "year" and data reloads
9. User applies a custom date range; data is loaded for that specific range
10. Custom date range with start > end is automatically corrected to the default range (with a warning)
11. Date range exceeding the maximum allowed years is capped at the max
12. `GET /analytics/pattern_dashboard/trends?interval=daily` returns JSON trend data; interval can also be "weekly" or "monthly"
13. `GET /analytics/pattern_dashboard/heatmap` returns JSON usage heatmap data
14. Analytics data is cached (5 minutes for main metrics, 10 minutes for trends, 30 minutes for heatmap)
15. User exports analytics to CSV; file is downloaded
16. User exports analytics to JSON; file is downloaded
17. Export with an invalid format type redirects with "Invalid export format" alert
18. Export rate limiter blocks more than 5 exports per hour; user sees "rate limit exceeded" error
19. `POST /analytics/pattern_dashboard/refresh?component=overall_metrics` via Turbo Stream updates only the overall metrics partial
20. `POST /analytics/pattern_dashboard/refresh?component=category_performance` updates only the category performance partial
21. `POST /analytics/pattern_dashboard/refresh` with an unknown component returns 422

---

## 16. Budget Management

**Pages/Routes:** `GET /budgets`, `GET /budgets/new`, `POST /budgets`, `GET /budgets/:id`, `GET /budgets/:id/edit`, `PATCH/PUT /budgets/:id`, `DELETE /budgets/:id`, `POST /budgets/:id/duplicate`, `POST /budgets/:id/deactivate`, `GET /budgets/quick_set`
**Priority:** High
**Estimated scenarios:** 24

### Scenarios:
1. User visits `/budgets` but no active email account exists; they are redirected to root with "configure email account first" alert
2. User visits `/budgets` with an active email account and sees budgets grouped by period (daily, weekly, monthly, yearly)
3. Budget list shows active budgets first (sorted by `active: desc, period: asc, created_at: desc`)
4. Budget list shows overall budget health: percentage used, status (good/warning/critical/exceeded), total budget vs. spend
5. User creates a new monthly budget with a name, amount (CRC), start date, and warning/critical thresholds; redirected to dashboard with success notice
6. Budget defaults are applied on creation: `start_date = today`, `currency = CRC`, `warning_threshold = 70`, `critical_threshold = 90`
7. User submits a budget with a blank name and sees the "can't be blank" validation error
8. User submits with a zero or negative amount and sees the validation error
9. User submits with `warning_threshold >= critical_threshold` and sees the validation error ("warning must be less than critical")
10. User submits with `end_date < start_date` and sees the validation error
11. User tries to create a second active budget with the same period and category as an existing active one; validation blocks it with "ya existe un presupuesto activo" error
12. User views a budget show page and sees: current spend, usage percentage, remaining amount, days remaining in period, daily average needed
13. Budget show page displays historical adherence for the last 6 periods
14. Budget with 0% usage shows `status: :good` and emerald-600 color
15. Budget reaching the warning threshold (70% by default) shows `status: :warning` and amber-600 color
16. Budget reaching the critical threshold (90% by default) shows `status: :critical` and rose-500 color
17. Budget exceeding 100% shows `status: :exceeded`, rose-600 color, and "Presupuesto excedido" message
18. User updates a budget's amount; `calculate_current_spend!` is called and cached spend is recalculated
19. User deactivates a budget; it moves to inactive state and no longer counts toward budget health
20. User deletes a budget and it is permanently removed
21. User duplicates a budget; a new budget is created for the next period with the same settings
22. Duplicated budget shows the edit form so the user can adjust amounts before saving
23. `GET /budgets/quick_set?period=monthly` shows a quick-set form with a suggested budget amount based on recent spending
24. Suggested budget amount is calculated as 110% of the average spending over the lookback period, rounded to the nearest thousand
25. Budget indicators appear correctly on the dashboard when active budgets exist (budget_progress_controller)

---

## 17. Categories

**Pages/Routes:** `GET /categories` (JSON endpoint)
**Priority:** Medium
**Estimated scenarios:** 6

### Scenarios:
1. `GET /categories` returns a JSON array of all categories sorted by name
2. Category JSON response is used by the inline categorization dropdowns throughout the app
3. Categories include color fields used for visual category badges
4. Categories with parent-child hierarchy are returned with parent information
5. `GET /api/v1/categories` (API endpoint) returns categories with proper API authentication
6. `GET /api/v1/categories` without a valid API token returns 401

---

## 18. API — Webhooks (iPhone Shortcuts Integration)

**Pages/Routes:** `POST /api/webhooks/process_emails`, `POST /api/webhooks/add_expense`, `GET /api/webhooks/recent_expenses`, `GET /api/webhooks/expense_summary`
**Priority:** High
**Estimated scenarios:** 18

### Scenarios:
1. Request to any webhook endpoint without an `Authorization: Bearer <token>` header returns 401 with "Missing API token"
2. Request with an invalid or expired bearer token returns 401 with "Invalid or expired API token"
3. Request with a valid bearer token passes authentication and proceeds
4. `POST /api/webhooks/process_emails` with `email_account_id` queues `ProcessEmailsJob` for that account and returns 202 Accepted
5. `POST /api/webhooks/process_emails` without `email_account_id` queues `ProcessEmailsJob` for all active accounts
6. `since` parameter accepts numeric strings (hours ago), "today", "yesterday", "week", "month", ISO 8601 timestamps
7. Invalid `since` parameter defaults to 1 week ago
8. `POST /api/webhooks/add_expense` with required fields (amount, description, transaction_date) creates an expense and returns 201 with expense JSON
9. Created expense has `status: "processed"` and is associated with the first active email account
10. `POST /api/webhooks/add_expense` with an optional `category_id` assigns that category to the new expense
11. `POST /api/webhooks/add_expense` with missing required field returns 422 with validation errors
12. `POST /api/webhooks/add_expense` when no active email account exists creates a default "Manual Entry" account
13. `GET /api/webhooks/recent_expenses` returns up to 10 recent expenses (default) as JSON
14. `GET /api/webhooks/recent_expenses?limit=25` returns up to 25 expenses (capped at 50)
15. `GET /api/webhooks/recent_expenses?limit=0` defaults to 10 expenses
16. Recent expenses response includes: id, amount, formatted_amount, description, merchant_name, transaction_date (ISO 8601), category, bank_name, status, created_at
17. `GET /api/webhooks/expense_summary` returns summary for the default period with status, period, and summary keys
18. `GET /api/webhooks/expense_summary?period=month` returns monthly summary data

---

## 19. API v1 — Patterns

**Pages/Routes:** `GET /api/v1/patterns`, `GET /api/v1/patterns/:id`, `POST /api/v1/patterns`, `PATCH /api/v1/patterns/:id`, `DELETE /api/v1/patterns/:id`, `GET /api/v1/patterns/statistics`
**Priority:** Medium
**Estimated scenarios:** 16

### Scenarios:
1. `GET /api/v1/patterns` without authentication returns 401
2. `GET /api/v1/patterns` with valid auth returns paginated list of patterns with `meta` block (page, total, total_pages)
3. Filter by `pattern_type` returns only patterns of that type
4. Filter by `category_id` returns only patterns for that category
5. Filter by `active=true` returns only active patterns
6. Filter by `user_created=true` returns only user-created patterns
7. Filter by `min_success_rate=0.8` returns only patterns with success rate >= 0.8
8. Filter by `min_usage_count=10` returns only patterns used at least 10 times
9. Sort by `success_rate` descending (default direction)
10. Sort by `usage_count`, `created_at`, `pattern_type` with `sort_direction=asc`
11. `GET /api/v1/patterns/:id` returns detailed pattern JSON including category info
12. `GET /api/v1/patterns/:id` returns ETag header; subsequent identical request with `If-None-Match` returns 304 Not Modified
13. `POST /api/v1/patterns` with valid attributes creates a new pattern with `user_created: true`
14. `PATCH /api/v1/patterns/:id` updates `pattern_value`, `confidence_weight`, `active`, or `metadata`
15. `DELETE /api/v1/patterns/:id` soft-deactivates the pattern (`active: false`); does not hard delete
16. `GET /api/v1/patterns/statistics` returns aggregated statistics about pattern performance

---

## 20. API v1 — Categorization

**Pages/Routes:** `POST /api/v1/categorization/suggest`, `POST /api/v1/categorization/feedback`, `POST /api/v1/categorization/batch_suggest`, `GET /api/v1/categorization/statistics`
**Priority:** High
**Estimated scenarios:** 10

### Scenarios:
1. `POST /api/v1/categorization/suggest` with merchant name and description returns the top suggested category with confidence score
2. `POST /api/v1/categorization/suggest` with an unrecognized merchant returns a low-confidence suggestion or no suggestion
3. `POST /api/v1/categorization/feedback` records whether a categorization suggestion was correct or incorrect
4. Feedback with `was_correct: false` triggers pattern learning to improve future suggestions
5. `POST /api/v1/categorization/batch_suggest` accepts an array of expense inputs and returns suggestions for each
6. Batch suggest returns results in the same order as the input array
7. `GET /api/v1/categorization/statistics` returns overall categorization accuracy, pattern usage stats, and ML metrics
8. All categorization endpoints require valid API authentication
9. `POST /api/v1/categorization/suggest` without required parameters returns a 422 error
10. Categorization statistics endpoint supports optional time range filtering

---

## 21. API — Health Checks

**Pages/Routes:** `GET /api/health`, `GET /api/health/ready`, `GET /api/health/live`, `GET /api/health/metrics`, `GET /up`
**Priority:** Medium
**Estimated scenarios:** 10

### Scenarios:
1. `GET /api/health` returns 200 with `healthy: true` when all subsystems are operational
2. `GET /api/health` returns 503 with `healthy: false` when a critical subsystem is failing
3. Health response includes per-subsystem checks with `status`, `response_time_ms`, and any errors
4. `GET /api/health/ready` returns 200 `{ status: "ready" }` when the app can serve traffic
5. `GET /api/health/ready` returns 503 with a list of unhealthy checks when not ready
6. `GET /api/health/live` returns 200 `{ status: "live" }` when the process is alive
7. `GET /api/health/live` returns 503 `{ status: "dead" }` when the liveness check fails
8. `GET /api/health/metrics` returns categorization stats, pattern counts, cache stats, DB pool metrics, and memory usage
9. Health endpoints do not require authentication (skip `authenticate_user!`)
10. `GET /up` (Rails built-in health check) returns 200 when the app boots without exceptions

---

## 22. API — Queue & Monitoring

**Pages/Routes:** `GET /api/queue/status`, `GET /api/queue/metrics`, `GET /api/queue/health`, `POST /api/queue/pause`, `POST /api/queue/resume`, `POST /api/queue/retry_all_failed`, `POST /api/queue/jobs/:id/retry`, `POST /api/queue/jobs/:id/clear`, `GET /api/monitoring/metrics`, `GET /api/monitoring/health`, `GET /api/monitoring/strategy`
**Priority:** Medium
**Estimated scenarios:** 10

### Scenarios:
1. `GET /api/queue/status` returns current queue depth, active jobs count, and failed jobs count
2. `GET /api/queue/metrics` returns processing rate, throughput, and per-queue statistics
3. `GET /api/queue/health` returns whether the queue system is healthy
4. `POST /api/queue/pause` pauses the queue; subsequent jobs are not processed until resumed
5. `POST /api/queue/resume` resumes a paused queue
6. `POST /api/queue/retry_all_failed` re-enqueues all failed jobs
7. `POST /api/queue/jobs/:id/retry` re-enqueues a specific failed job by ID
8. `POST /api/queue/jobs/:id/clear` permanently removes a specific failed job
9. `GET /api/monitoring/metrics` returns application-level performance metrics
10. `GET /api/monitoring/strategy` returns the current monitoring configuration and strategy details

---

## 23. Navigation, Layout & Responsive Behavior

**Pages/Routes:** All pages (layout-level scenarios)
**Priority:** High
**Estimated scenarios:** 18

### Scenarios:
1. Desktop viewport (768px+): horizontal navigation bar is rendered with all main nav links visible
2. Mobile viewport (<768px): hamburger button is visible; nav links are hidden by default
3. User taps the hamburger button on mobile; the nav menu slides open (opacity transition)
4. User taps a nav link inside the open mobile menu; menu closes and user navigates to the target page
5. User taps outside the mobile menu; menu closes (click-outside handler)
6. User presses `Escape` while mobile menu is open; menu closes and focus returns to the hamburger button
7. Resizing from mobile to desktop (>=768px) automatically closes the mobile menu (`matchMedia` listener)
8. Mobile menu button has `aria-expanded` attribute toggling between "true" and "false"
9. Opening the mobile menu focuses the first navigation link (keyboard accessibility)
10. Flash messages are dismissible via the `flash_controller` (click or auto-dismiss after timeout)
11. Toast notifications appear and auto-dismiss via `toast_controller` and `toast_container_controller`
12. Dropdown menus work via `dropdown_controller` with click-outside dismissal
13. Main navigation links are highlighted when the current page matches the route
14. Page titles in the browser tab correctly reflect the current section
15. The application renders correctly on a modern mobile browser (iOS Safari, Android Chrome)
16. Skip-to-main-content link is present and functional for keyboard users
17. Color contrast ratios for text and backgrounds meet WCAG 2.1 AA standards throughout the app
18. No `blue-` color classes appear anywhere in the rendered UI (Financial Confidence palette enforced)

---

## 24. Undo History

**Pages/Routes:** `POST /undo_histories/:id/undo`
**Priority:** High
**Estimated scenarios:** 8

### Scenarios:
1. After a single expense deletion, the undo history record is created with the correct `affected_count` (1)
2. User POSTs to `/undo_histories/:id/undo` within the time window; expense is restored and response confirms `affected_count`
3. Undo via Turbo Stream replaces the `dashboard-expenses-widget` with a refreshed expense list
4. Undo via JSON format returns `{ success: true, message: "...", affected_count: N }`
5. Undo request after the time window has expired returns 422 with "Esta acción ya no se puede deshacer" message
6. `POST /undo_histories/:id/undo` with a non-existent ID returns 404 with "Undo record not found"
7. After bulk delete, the undo record covers all deleted expenses; undoing restores all of them
8. The undo notification flash correctly counts down the remaining time before the undo window closes

---

## 25. Search & Filtering (Cross-Feature)

**Pages/Routes:** `GET /expenses`, `GET /expenses/dashboard`
**Priority:** High
**Estimated scenarios:** 10

### Scenarios:
1. Text search on expense list matches against `merchant_name` and `description` fields (case-insensitive, using pg_trgm trigram index)
2. Text search with a Spanish accented character (e.g., "café") matches records with or without accents (unaccent extension)
3. Text search with an empty string returns the full unfiltered list (no empty-string filter applied)
4. Text search with SQL injection attempt (e.g., `' OR '1'='1`) is safely sanitized and returns no results
5. Period-based filter `period=day` correctly scopes to today's date range
6. Period-based filter `period=week` correctly scopes to the current week (beginning to end)
7. Period-based filter `period=year` correctly scopes to the current calendar year
8. Date range filter with `date_from` and `date_to` params works correctly for explicit ranges (dashboard card navigation context)
9. Category filter by name (single `category` param) correctly resolves the category ID and applies the filter
10. Combining `period` with `category_ids` and `banks` filters all apply simultaneously

---

## 26. Accessibility Enhancements

**Pages/Routes:** All pages (cross-cutting)
**Priority:** High
**Estimated scenarios:** 12

### Scenarios:
1. All interactive elements on the expense list (filter chips, inline actions, sort buttons) are reachable by Tab key
2. Expense table supports arrow key navigation between rows (`accessibility_enhanced_controller`)
3. Pressing `Enter` on a focused expense row opens the expense show page
4. Dashboard filter chips can be activated and removed using keyboard only
5. All form inputs have associated `<label>` elements
6. All images and icons have descriptive `alt` text or are marked `aria-hidden`
7. Modal dialogs (bulk operations modal, conflict modal) trap focus while open; `Escape` closes them
8. Screen reader announcements are made when batch selection count changes
9. Screen reader announcement is made when a Turbo Stream update occurs (live region)
10. Color is not the sole means of conveying information (e.g., status badges include text labels, not just color)
11. Interactive elements have sufficient touch target size (minimum 44x44px) on mobile
12. The `accessibility_enhanced_controller` adds correct ARIA roles and live regions to dynamic content

---

## 27. Keyboard Shortcuts

**Pages/Routes:** `GET /expenses`, `GET /expenses/dashboard`
**Priority:** Medium
**Estimated scenarios:** 8

### Scenarios:
1. Keyboard shortcut suppression: when focused inside an input, textarea, or select, global shortcuts do not fire (`shouldSuppressShortcut` utility)
2. Dashboard keyboard shortcut navigates to the expense list
3. Expense list keyboard shortcut opens the "New Expense" form
4. Keyboard shortcut for toggling view mode (compact/expanded) works on the expense list
5. Arrow keys navigate between expense rows when not in an input
6. The `range_display_controller` updates displayed range value when a range input is adjusted via keyboard
7. Filter form can be submitted by pressing `Enter` from any filter field
8. Keyboard shortcut to open bulk actions does not fire when a dialog is open

---

## 28. Error Handling & Edge Cases

**Pages/Routes:** All routes
**Priority:** High
**Estimated scenarios:** 14

### Scenarios:
1. Accessing a non-existent route returns a 404 response (not a 500 error)
2. Accessing `/expenses/:id` with an ID that does not exist redirects to the expense list with "not found" flash
3. Server errors in the dashboard data loading (e.g., database connection failure) result in empty default metrics being shown, not a 500 page
4. Server error in the virtual scroll endpoint returns `{ error: "Error loading expenses" }` JSON with 500 status
5. Bulk operation with a completely empty `expense_ids` array returns a clear error message
6. API endpoint that throws an unexpected error returns a structured JSON error response
7. Flash messages for all success/error states are in Spanish (i18n keys resolved)
8. Budget controller redirects gracefully when no active email account exists (does not raise an exception)
9. Sync session creation when rate limit is exceeded returns the correct error type and user-facing message
10. Filter service error (e.g., invalid SQL) results in the expense list falling back to an empty result with an alert flash
11. Visiting `/admin/patterns/:id` with a non-existent ID redirects to the patterns list with "Pattern not found" alert
12. Visiting a protected route while admin session has expired redirects to login; return-to URL is stored and used post-login
13. Browser compatibility: `allow_browser versions: :modern` (configured in ApplicationController) blocks outdated browsers in non-test environments
14. API client error reporting: `POST /api/client_errors` accepts a client-side error payload and logs it server-side

---

## 29. Sidekiq / Background Jobs (Non-UI)

**Pages/Routes:** `GET /sidekiq` (development only), production Sidekiq Web UI with Basic Auth
**Priority:** Medium
**Estimated scenarios:** 6

### Scenarios:
1. In development, `/sidekiq` is accessible without authentication
2. In production, `/sidekiq` requires HTTP Basic Auth with `SIDEKIQ_WEB_USERNAME` and `SIDEKIQ_WEB_PASSWORD` env vars
3. Production request to `/sidekiq` without credentials returns 401
4. Production Sidekiq web with missing env vars logs a security error and denies access (not a 500 error)
5. Background job (`ProcessEmailsJob`) is enqueued when webhook `process_emails` is called; visible in Sidekiq queue
6. `MetricsRefreshJob.enqueue_debounced` is called after an expense is saved with a relevant field change; job appears in the queue

---

## 30. Data Integrity & Business Rules

**Pages/Routes:** Cross-cutting (model-level enforcement)
**Priority:** High
**Estimated scenarios:** 12

### Scenarios:
1. Soft-deleted expenses do not appear in any query that uses the default scope (SoftDelete concern)
2. `current_user_expenses` scoping ensures users only see expenses from their email accounts or manual (null) expenses
3. Expense amount is always stored as a positive decimal; negative or zero amount is rejected by validation
4. All three currencies (CRC, USD, EUR) are supported and correctly formatted with their symbols (₡, $, €)
5. Budget `unique_active_budget_per_scope` validation prevents duplicate active budgets for the same period and category
6. Budget `thresholds_order` validation ensures warning threshold is always less than critical threshold
7. `processed_email` model prevents duplicate email processing (deduplication by email message ID)
8. Dashboard cache is cleared after any expense change to a cache-relevant attribute (amount, currency, category, date, status, email_account, deleted_at)
9. Creating an expense from a specific email account automatically populates `bank_name` from the account
10. `merchant_normalized` is always computed from `merchant_name` and stored in lowercase with special characters removed
11. `AdminUser` with `has_secure_password` never stores plaintext passwords
12. Pattern feedback `was_correct: false` correctly decrements success metrics for the associated pattern

---

## Summary

| Feature Area | Priority | Est. Scenarios |
|---|---|---|
| Authentication & Authorization | Critical | 22 |
| Dashboard | Critical | 24 |
| Expense CRUD | Critical | 30 |
| Expense List (Index, Filters, Pagination) | Critical | 28 |
| Mobile Card Layout (PER-133) | Critical | 20 |
| Bulk Operations | High | 24 |
| ML Categorization Inline Actions | High | 18 |
| Bulk Categorization Workflow | High | 18 |
| Email Accounts | High | 14 |
| Email Sync — Sync Sessions | High | 20 |
| Sync Conflicts | High | 16 |
| Sync Performance Monitoring | Medium | 12 |
| Admin Panel — Patterns | High | 32 |
| Admin Panel — Composite Patterns | Medium | 8 |
| Analytics — Pattern Dashboard | High | 21 |
| Budget Management | High | 25 |
| Categories | Medium | 6 |
| API — Webhooks | High | 18 |
| API v1 — Patterns | Medium | 16 |
| API v1 — Categorization | High | 10 |
| API — Health Checks | Medium | 10 |
| API — Queue & Monitoring | Medium | 10 |
| Navigation, Layout & Responsive | High | 18 |
| Undo History | High | 8 |
| Search & Filtering (Cross-Feature) | High | 10 |
| Accessibility Enhancements | High | 12 |
| Keyboard Shortcuts | Medium | 8 |
| Error Handling & Edge Cases | High | 14 |
| Sidekiq / Background Jobs | Medium | 6 |
| Data Integrity & Business Rules | High | 12 |
| **Total** | | **~520** |

---

## Parallelization Recommendations

These groups can be assigned independently to separate agents without shared state conflicts:

**Agent Group A — Core Expense Flows (Critical):** Authentication + Expense CRUD + Expense List + Filters + Search
**Agent Group B — Dashboard & Mobile (Critical):** Dashboard + Mobile Card Layout (PER-133) + Navigation + Responsive
**Agent Group C — Bulk & ML Operations (High):** Bulk Operations + ML Inline Actions + Bulk Categorization Workflow + Undo History
**Agent Group D — Email & Sync (High):** Email Accounts + Sync Sessions + Sync Conflicts + Sync Performance
**Agent Group E — Admin & Analytics (High):** Admin Patterns + Admin Composite Patterns + Analytics Dashboard
**Agent Group F — Budget & Categories (High):** Budget Management + Categories + Data Integrity
**Agent Group G — API & Infrastructure (Medium/High):** Webhooks + API v1 Patterns + API v1 Categorization + Health + Queue + Error Handling + Sidekiq
