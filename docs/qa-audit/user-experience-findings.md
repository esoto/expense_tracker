# User Experience QA Audit Findings

**Date**: 2026-02-14
**Auditor**: Claude Opus 4.6 (UX Tester role)
**Application**: Expense Tracker (Rails 8.1)
**Methodology**: Static code analysis of controllers, views, models, Stimulus controllers, services, and routes
**Known Open Issues**: 5 (in `docs/issues/`)

---

## Summary Table

| # | Severity | Epic | Finding | File(s) | Status |
|---|----------|------|---------|---------|--------|
| UX-001 | CRITICAL | Cross-Epic | Multiple controllers missing authentication | `email_accounts_controller.rb`, `budgets_controller.rb`, `sync_sessions_controller.rb` | New |
| UX-002 | CRITICAL | Cross-Epic | Expense form requires email_account_id but "include_blank" allows nil | `_form.html.erb`, `expenses_controller.rb` | New |
| UX-003 | HIGH | Epic 3 | N+1 query: Category.all.order loaded per expense row | `_expense_row.html.erb:96` | New |
| UX-004 | HIGH | Cross-Epic | Delete confirmation says "Esta accion no se puede deshacer" but soft delete IS undoable | `_expense_row.html.erb:164`, `_bulk_operations_modal.html.erb:163` | New |
| UX-005 | HIGH | Epic 3 | Dashboard inline delete lacks undo notification integration | `dashboard_inline_actions_controller.js:267` | New |
| UX-006 | HIGH | Cross-Epic | No pagination on expenses index page | `index.html.erb:195` | New |
| UX-007 | HIGH | Cross-Epic | Broken bundle - missing gems prevent test suite from running | `Gemfile.lock` | New |
| UX-008 | MEDIUM | Cross-Epic | Email account deletion cascades to destroy all associated expenses | `email_account.rb:8` | New |
| UX-009 | MEDIUM | Epic 2 | Dashboard metrics hardcoded to CRC currency symbol | `dashboard.html.erb:218` | New |
| UX-010 | MEDIUM | Cross-Epic | Flash messages have no auto-dismiss functionality | `application.html.erb:96-110` | New |
| UX-011 | MEDIUM | Epic 3 | Dashboard duplicateExpense forces full page reload | `dashboard_inline_actions_controller.js:201` | New |
| UX-012 | MEDIUM | Cross-Epic | Show page missing "failed" status badge rendering | `show.html.erb:33-47` | New |
| UX-013 | MEDIUM | Epic 3 | Keyboard shortcut conflict: "S" key used for different actions | `dashboard_inline_actions_controller.js:425`, `inline_actions_controller.js:69` | New |
| UX-014 | MEDIUM | Cross-Epic | Bank filter dropdown hardcoded to only "BAC" and "Manual Entry" | `index.html.erb:67` | New |
| UX-015 | MEDIUM | Cross-Epic | No mobile-responsive navigation menu (hamburger/collapse) | `application.html.erb:53-93` | New |
| UX-016 | LOW | Cross-Epic | Mixed language in UI - English strings in Spanish interface | Multiple files | New |
| UX-017 | LOW | Cross-Epic | No footer in application layout | `application.html.erb` | New |
| UX-018 | LOW | Epic 3 | confidence_text_color helper is private but called from view | `expenses_helper.rb:176`, `_category_with_confidence.html.erb:145` | New |
| UX-019 | INFO | Cross-Epic | No user logout mechanism visible in main navigation | `application.html.erb:64-89` | New |
| UX-020 | INFO | Cross-Epic | Expense create defaults bank_name to "Manual Entry" string | `expenses_controller.rb:73` | New |

**Totals**: 2 CRITICAL, 5 HIGH, 7 MEDIUM, 4 LOW, 2 INFO

---

## Detailed Findings

---

### UX-001: Multiple Controllers Missing Authentication (CRITICAL)

**Epic Affected**: Cross-Epic (Security)

**Files**:
- `/Users/esoto/development/expense_tracker/app/controllers/email_accounts_controller.rb` (line 1)
- `/Users/esoto/development/expense_tracker/app/controllers/budgets_controller.rb` (line 6)
- `/Users/esoto/development/expense_tracker/app/controllers/sync_performance_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/undo_histories_controller.rb` (line 3)
- `/Users/esoto/development/expense_tracker/app/controllers/sync_conflicts_controller.rb`

**User Story**: As a malicious user, I can access and manage all email accounts, budgets, sync sessions, and undo operations without logging in.

**Expected Behavior**: All controllers handling sensitive data should require authentication via `include Authentication`.

**Actual Behavior**: Only `ExpensesController`, `BulkCategorizationsController`, and `BulkCategorizationActionsController` include the `Authentication` concern. The `EmailAccountsController`, `BudgetsController`, `UndoHistoriesController`, `SyncConflictsController`, and `SyncPerformanceController` inherit from `ApplicationController` which does NOT include authentication.

**Steps to Reproduce**:
1. Open a browser without logging in
2. Navigate to `/email_accounts`
3. You can view, create, edit, and delete email accounts without authentication
4. Navigate to `/budgets` - same issue
5. POST to `/undo_histories/:id/undo` - can undo any operation

**Recommended Fix**: Add `include Authentication` to all controllers that handle user data, or add it to `ApplicationController` and exclude public-facing endpoints. Example:

```ruby
class EmailAccountsController < ApplicationController
  include Authentication
  # ...
end
```

---

### UX-002: Expense Form Allows Blank email_account_id Creating Orphan Records (CRITICAL)

**Epic Affected**: Cross-Epic (Data Integrity)

**Files**:
- `/Users/esoto/development/expense_tracker/app/views/expenses/_form.html.erb` (line 66-68)
- `/Users/esoto/development/expense_tracker/app/controllers/expenses_controller.rb` (line 72-83)
- `/Users/esoto/development/expense_tracker/app/models/expense.rb` (line 7)

**User Story**: As a user creating a manual expense, if I select "Entrada manual" (blank option) for email account, the expense fails because `email_account` is a required `belongs_to` association.

**Expected Behavior**: Either (a) the form should not allow blank email_account_id since the model requires it, or (b) the controller should auto-assign a default email account for manual entries.

**Actual Behavior**: The expense form has `include_blank: "Entrada manual"` for email_account_id select, which submits nil. The model has `belongs_to :email_account` (required by default in Rails). The controller does NOT assign a default email account. The create action will fail with a validation error: "Email account must exist."

**Steps to Reproduce**:
1. Navigate to `/expenses/new`
2. Fill in amount (e.g., 10000), currency, date
3. Leave email account as "Entrada manual" (blank)
4. Click "Crear Gasto"
5. Form re-renders with validation error

**Recommended Fix**: Either remove `include_blank` from the email account select and pre-select the first account, or create a dedicated "manual" email account and auto-assign it in the controller:

```ruby
def create
  @expense = Expense.new(expense_params)
  @expense.email_account ||= EmailAccount.find_or_create_by!(
    email: "manual@expense-tracker.local",
    bank_name: "Manual Entry",
    provider: "manual"
  )
  # ...
end
```

---

### UX-003: N+1 Query - Category.all Loaded Per Expense Row (HIGH)

**Epic Affected**: Epic 3 (Expense List Performance)

**File**: `/Users/esoto/development/expense_tracker/app/views/expenses/_expense_row.html.erb` (line 96)

**User Story**: As a user viewing the expense list, the page loads slowly because every expense row triggers a separate `Category.all.order(:name)` query for its inline category dropdown.

**Expected Behavior**: Categories should be loaded once and passed to the partial, or cached at the controller level.

**Actual Behavior**: Line 96 of `_expense_row.html.erb` contains:
```erb
<% Category.all.order(:name).each do |category| %>
```
This executes a database query for every single expense row rendered. With 50 expenses on a page, this is 50 redundant queries.

**Steps to Reproduce**:
1. Navigate to `/expenses` or the dashboard
2. Open Rails log or use the Bullet gem
3. Observe: one `SELECT "categories".* FROM "categories" ORDER BY name` query per expense row

**Recommended Fix**: Load categories once in the controller and pass them as a local variable:

```ruby
# In controller
@categories = Category.all.order(:name)

# In _expense_row partial call
<%= render "expense_row", expense: expense, categories: @categories %>
```

---

### UX-004: Delete Confirmation Contradicts Soft Delete Behavior (HIGH)

**Epic Affected**: Cross-Epic (User Trust)

**Files**:
- `/Users/esoto/development/expense_tracker/app/views/expenses/_expense_row.html.erb` (line 164)
- `/Users/esoto/development/expense_tracker/app/views/expenses/_bulk_operations_modal.html.erb` (line 163-165)

**User Story**: As a user, the delete confirmation tells me "Esta accion no se puede deshacer" (this action cannot be undone), but the system actually uses soft delete with a 30-minute undo window.

**Expected Behavior**: The confirmation message should accurately reflect that the action IS undoable for 30 minutes via the undo system.

**Actual Behavior**:
- `_expense_row.html.erb` line 164: `"Esta accion no se puede deshacer"`
- `_bulk_operations_modal.html.erb` line 163: `"Advertencia: Esta accion no se puede deshacer"`
- The `SoftDelete` module (line 21-26) overrides `destroy` to perform soft delete
- `UndoHistory` (line 7) provides a 30-minute undo window

**Steps to Reproduce**:
1. Click the delete button on any expense
2. Read the confirmation message: "Esta accion no se puede deshacer"
3. Actually, the expense is soft-deleted and recoverable

**Recommended Fix**: Update the confirmation text to:
```
"Este gasto sera eliminado. Tendras 30 minutos para deshacer esta accion."
```

---

### UX-005: Dashboard Inline Delete Lacks Undo Notification (HIGH)

**Epic Affected**: Epic 3 (Inline Actions)

**File**: `/Users/esoto/development/expense_tracker/app/javascript/controllers/dashboard_inline_actions_controller.js` (lines 247-276)

**User Story**: As a user deleting an expense from the dashboard via inline actions, I see a success toast but am NOT offered an undo option, even though the system supports it.

**Expected Behavior**: After deleting an expense, the user should see an undo notification with a countdown timer (30-minute window), similar to how bulk delete works.

**Actual Behavior**: The `confirmDelete` method in `dashboard_inline_actions_controller.js` sends a DELETE request and on success only shows a toast "Gasto eliminado exitosamente" and animates the row removal. It does not:
1. Check the response for `undo_id`
2. Display the undo notification bar
3. Integrate with the `undo_manager_controller.js`

The controller's `destroy` action returns JSON with `{ success: true, message: ... }` but does not include undo information. Meanwhile, `bulk_destroy` returns `undo_id` and `undo_time_remaining`.

**Steps to Reproduce**:
1. Go to the dashboard
2. Click the delete (trash) icon on any expense row
3. Confirm deletion
4. Observe: toast shows "Gasto eliminado exitosamente" but no undo option
5. The expense is soft-deleted and theoretically recoverable, but the user has no way to undo

**Recommended Fix**:
1. Update `ExpensesController#destroy` to create an `UndoHistory` record and return `undo_id` in JSON response
2. Update `dashboard_inline_actions_controller.js` to dispatch an undo notification event after successful deletion

---

### UX-006: No Pagination on Expenses Index Page (HIGH)

**Epic Affected**: Cross-Epic (Performance/UX)

**File**: `/Users/esoto/development/expense_tracker/app/views/expenses/index.html.erb` (line 195-197)

**User Story**: As a user with thousands of expenses, the index page loads all matching expenses at once with no way to navigate between pages.

**Expected Behavior**: The expense list should have pagination controls (next/previous/page numbers) or infinite scroll.

**Actual Behavior**: The expenses index page shows a static message at the bottom:
```erb
Mostrando los <%= @expenses.count %> gastos mas recientes
```
While the `ExpenseFilterService` supports pagination (with `page` and `per_page` params), the view does not render any pagination controls. The default `per_page` is 50, but there are no "next page" or "previous page" links.

**Steps to Reproduce**:
1. Navigate to `/expenses`
2. Scroll to the bottom
3. See "Mostrando los 50 gastos mas recientes" with no pagination controls
4. No way to view expenses beyond the first 50

**Recommended Fix**: Add pagination controls using the Kaminari gem (already available via `scope.page(page).per(per_page)` in the service) or add a "load more" button.

---

### UX-007: Broken Bundle Prevents Test Execution (HIGH)

**Epic Affected**: Cross-Epic (Development Environment)

**Files**: `Gemfile.lock`

**User Story**: As a developer, I cannot run the test suite because required gems are missing from the local installation.

**Expected Behavior**: `bundle exec rspec` should execute the test suite.

**Actual Behavior**: Running any `bundle exec` command fails with:
```
Could not find rack-attack-6.8.0, selenium-webdriver-4.40.0, webmock-3.26.1,
irb-1.17.0, rubyzip-3.2.2, crack-1.0.1, rdoc-7.2.0 in locally installed gems
```

**Steps to Reproduce**:
1. Run `bundle exec rspec`
2. Observe: BundlerGemNotFound error

**Recommended Fix**: Run `bundle install` to restore missing gems.

---

### UX-008: Email Account Deletion Cascades to Destroy All Expenses (MEDIUM)

**Epic Affected**: Cross-Epic (Data Safety)

**File**: `/Users/esoto/development/expense_tracker/app/models/email_account.rb` (line 8)

**User Story**: As a user who accidentally deletes an email account, all associated expenses are permanently destroyed with no recovery possible.

**Expected Behavior**: Deleting an email account should either (a) soft-delete the account, (b) nullify the expense associations, or (c) require explicit confirmation that all expenses will be lost.

**Actual Behavior**: `has_many :expenses, dependent: :destroy` means all expenses are hard-deleted when an email account is removed. The `EmailAccountsController#destroy` action has no confirmation step and no soft-delete mechanism.

**Steps to Reproduce**:
1. Navigate to `/email_accounts`
2. Click "Destroy" on an email account
3. All expenses associated with that account are permanently deleted
4. No undo available

**Recommended Fix**: Change to `dependent: :nullify` or add soft-delete to EmailAccount:
```ruby
has_many :expenses, dependent: :nullify
```

---

### UX-009: Dashboard Metrics Hardcoded to CRC Currency (MEDIUM)

**Epic Affected**: Epic 2 (Metric Cards)

**File**: `/Users/esoto/development/expense_tracker/app/views/expenses/dashboard.html.erb` (lines 218, 278, 283, 309, 340, 371, 424, 435, 868)

**User Story**: As a user with USD or EUR expenses, all dashboard metric amounts are displayed with the CRC symbol regardless of actual currency.

**Expected Behavior**: Dashboard metrics should display amounts with the correct currency symbol based on the expense currency, or indicate that values are normalized to a single currency.

**Actual Behavior**: All metric displays in the dashboard use hardcoded `₡` prefix. For example:
- Line 218: `₡<%= number_with_delimiter(@total_expenses.to_i) %>`
- Line 278: `₡<%= number_with_delimiter(@total_metrics[:metrics][:transaction_count]) %>`
- The `animated-metric` controllers also have `data-animated-metric-prefix-value="₡"` hardcoded

**Steps to Reproduce**:
1. Create expenses in USD or EUR
2. View the dashboard
3. All amounts show with CRC symbol even if they are USD/EUR

**Recommended Fix**: Either convert all amounts to a single display currency, or show a "mixed currencies" indicator and display per-currency breakdowns.

---

### UX-010: Flash Messages Never Auto-Dismiss (MEDIUM)

**Epic Affected**: Cross-Epic (UX Polish)

**File**: `/Users/esoto/development/expense_tracker/app/views/layouts/application.html.erb` (lines 96-110)

**User Story**: As a user, flash messages (success/error) persist on screen until I navigate away, cluttering the interface.

**Expected Behavior**: Success flash messages should auto-dismiss after 5-8 seconds. Error messages can persist but should have a close button.

**Actual Behavior**: Flash messages are rendered as static `<div>` elements with no auto-dismiss timer and no close/dismiss button. They remain visible until the next page load.

**Steps to Reproduce**:
1. Create, edit, or delete any expense
2. Notice the green/red flash message at the top
3. The message stays on screen indefinitely

**Recommended Fix**: Add a `data-controller="toast"` to flash messages or add a dismiss button with a timer.

---

### UX-011: Dashboard Duplicate Forces Full Page Reload (MEDIUM)

**Epic Affected**: Epic 3 (Inline Actions)

**File**: `/Users/esoto/development/expense_tracker/app/javascript/controllers/dashboard_inline_actions_controller.js` (lines 197-209)

**User Story**: As a user duplicating an expense from the dashboard, the page reloads after 1 second, losing my scroll position and any applied filters.

**Expected Behavior**: After duplicating, the new expense row should be prepended to the table via Turbo Stream, maintaining scroll position and filter state.

**Actual Behavior**: The `duplicateExpense` method uses `setTimeout(() => { window.location.reload() }, 1000)` which causes a full page reload.

**Steps to Reproduce**:
1. Scroll down on the dashboard expense list
2. Apply some filters
3. Click duplicate on an expense
4. After 1 second, full page reload - scroll position lost, filters potentially lost

**Recommended Fix**: Use Turbo Stream to prepend the new expense row instead of reloading, similar to how the `inline_actions_controller.js` version handles it.

---

### UX-012: Show Page Missing "failed" Status Badge (MEDIUM)

**Epic Affected**: Cross-Epic (UI Completeness)

**File**: `/Users/esoto/development/expense_tracker/app/views/expenses/show.html.erb` (lines 33-47)

**User Story**: As a user viewing an expense with "failed" status, no status badge is displayed.

**Expected Behavior**: All four status values (processed, pending, duplicate, failed) should have corresponding badge styling.

**Actual Behavior**: The show page only renders badges for `processed`, `pending`, and `duplicate` statuses. The `failed` status has no `<% when 'failed' %>` case, so nothing is rendered. Note that the `_status_badge.html.erb` partial correctly handles all four statuses, but the show page duplicates the status rendering logic and misses `failed`.

**Steps to Reproduce**:
1. Create or find an expense with "failed" status
2. Navigate to its show page
3. No status badge is displayed

**Recommended Fix**: Either add a `failed` case to the show page, or use the existing `_status_badge` partial:
```erb
<%= render "expenses/status_badge", expense: @expense %>
```

---

### UX-013: Keyboard Shortcut Conflict Between Controllers (MEDIUM)

**Epic Affected**: Epic 3 (Keyboard Navigation)

**Files**:
- `/Users/esoto/development/expense_tracker/app/javascript/controllers/dashboard_inline_actions_controller.js` (line 425-429)
- `/Users/esoto/development/expense_tracker/app/javascript/controllers/inline_actions_controller.js` (line 69-70)

**User Story**: As a user navigating with keyboard, pressing "S" toggles status in the dashboard controller but "R" toggles status in the expenses index controller, creating inconsistent behavior.

**Expected Behavior**: The same keyboard shortcut should perform the same action across the application.

**Actual Behavior**:
- `dashboard_inline_actions_controller.js`: "S" key toggles status, "D" duplicates
- `inline_actions_controller.js`: "R" key toggles status, "D" duplicates
- Both controllers use "C" for category and "Delete" for delete

**Steps to Reproduce**:
1. On the dashboard, focus an expense row and press "S" - status toggles
2. On the expenses index, focus an expense row and press "S" - nothing happens
3. On the expenses index, press "R" - status toggles

**Recommended Fix**: Standardize keyboard shortcuts across both controllers to use the same key bindings.

---

### UX-014: Bank Filter Dropdown Hardcoded (MEDIUM)

**Epic Affected**: Cross-Epic (Filter Accuracy)

**File**: `/Users/esoto/development/expense_tracker/app/views/expenses/index.html.erb` (line 67)

**User Story**: As a user with expenses from banks other than BAC (e.g., BCR, Scotiabank, Banco Nacional), I cannot filter by those banks.

**Expected Behavior**: The bank filter should dynamically list all banks that have associated expenses.

**Actual Behavior**: The bank filter is hardcoded:
```erb
options_for_select([["Todos los bancos", ""], ["BAC", "BAC"], ["Manual Entry", "Manual Entry"]], params[:bank])
```
Only "BAC" and "Manual Entry" are available as filter options.

**Steps to Reproduce**:
1. Navigate to `/expenses`
2. Open the bank filter dropdown
3. Only "BAC" and "Manual Entry" are listed

**Recommended Fix**: Dynamically populate the bank filter from actual data:
```ruby
# In controller
@available_banks = Expense.joins(:email_account).distinct.pluck('email_accounts.bank_name')

# In view
options_for_select(@available_banks.map { |b| [b, b] }.prepend(["Todos los bancos", ""]), params[:bank])
```

---

### UX-015: No Mobile-Responsive Navigation (MEDIUM)

**Epic Affected**: Cross-Epic (Responsiveness)

**File**: `/Users/esoto/development/expense_tracker/app/views/layouts/application.html.erb` (lines 53-93)

**User Story**: As a mobile user, the navigation bar does not collapse into a hamburger menu, causing navigation links to overflow or stack.

**Expected Behavior**: On screens below ~768px, the navigation should collapse into a hamburger menu or slide-out drawer.

**Actual Behavior**: The navigation is a simple `flex` layout with 8+ items (Dashboard, Gastos, Categorizar, Analytics, Cuentas, Sincronizacion, Patrones, Nuevo Gasto). On small screens, these items will overflow or wrap in an unusable way. There is no hamburger button, no Stimulus controller for mobile menu toggle.

**Steps to Reproduce**:
1. Open the application on a mobile device or resize browser to <768px width
2. Observe: navigation items overflow or wrap

**Recommended Fix**: Add a responsive hamburger menu with a Stimulus controller for toggle behavior, hiding nav items behind a dropdown on mobile.

---

### UX-016: Mixed Languages in UI (LOW)

**Epic Affected**: Cross-Epic (Localization)

**Files**: Multiple

**User Story**: As a Spanish-speaking user, some UI elements appear in English while the rest is in Spanish, creating a jarring experience.

**Expected Behavior**: The entire UI should be consistently in Spanish (the primary language) or use Rails I18n consistently.

**Actual Behavior**: Examples of English strings in a Spanish interface:
- `undo_manager_controller.js` line 116: `"Expired"` (should be "Expirado")
- `undo_manager_controller.js` line 144: `"Action undone successfully"` (should be "Accion deshecha exitosamente")
- `undo_manager_controller.js` line 148: `"Failed to undo action"` (should be "Error al deshacer la accion")
- `undo_manager_controller.js` line 169: `"Undoing..."` (should be "Deshaciendo...")
- `show.html.erb` line 133: `"ago"` suffix in `time_ago_in_words(@expense.created_at) %> ago)`
- `_category_with_confidence.html.erb` line 19: `"Sin categoria"` vs `"Uncategorized"` used interchangeably in code
- Expense model line 51: `"Uncategorized"` returned by `category_name` method

**Recommended Fix**: Use Rails I18n for all user-facing strings and ensure consistent Spanish translations.

---

### UX-017: No Footer in Application Layout (LOW)

**Epic Affected**: Cross-Epic (UI Completeness)

**File**: `/Users/esoto/development/expense_tracker/app/views/layouts/application.html.erb`

**User Story**: As a user, there is no footer providing information about the application version, copyright, help links, or navigation.

**Expected Behavior**: A minimal footer with relevant links (help, about, version) should be present.

**Actual Behavior**: The layout ends after `<main>` with no footer element.

**Recommended Fix**: Add a simple footer with relevant information.

---

### UX-018: Private Helper Method Called From View (LOW)

**Epic Affected**: Epic 3 (Categorization Display)

**Files**:
- `/Users/esoto/development/expense_tracker/app/helpers/expenses_helper.rb` (line 176-191)
- `/Users/esoto/development/expense_tracker/app/views/expenses/_category_with_confidence.html.erb` (line 145)

**User Story**: The `confidence_text_color` method is declared as `private` in `ExpensesHelper` but is called from the `_category_with_confidence.html.erb` view partial.

**Expected Behavior**: Helper methods called from views should be public.

**Actual Behavior**: `confidence_text_color` is under the `private` keyword in `expenses_helper.rb` (line 176). It is called from `_category_with_confidence.html.erb` line 145. In Ruby, `private` in a module included as a helper does not actually prevent the method from being called in views (Rails makes all helper methods available), so this works in practice but is misleading and could break if the helper architecture changes.

**Recommended Fix**: Move `confidence_text_color` above the `private` keyword to make it explicitly public.

---

### UX-019: No Logout Mechanism in Main Navigation (INFO)

**Epic Affected**: Cross-Epic (Authentication)

**File**: `/Users/esoto/development/expense_tracker/app/views/layouts/application.html.erb` (lines 64-89)

**User Story**: As a logged-in user, there is no visible logout button in the main navigation bar.

**Expected Behavior**: A logout button or link should be visible when the user is authenticated.

**Actual Behavior**: The navigation has links for all features and a "Nuevo Gasto" button, but no logout link, user avatar/name display, or account management option. The logout route exists at `/admin/logout` but is not linked from the main navigation.

**Recommended Fix**: Add a user indicator and logout link to the navigation bar.

---

### UX-020: Manual Expense Creates bank_name as String Attribute (INFO)

**Epic Affected**: Cross-Epic (Data Model)

**File**: `/Users/esoto/development/expense_tracker/app/controllers/expenses_controller.rb` (line 73)

**User Story**: When creating a manual expense, `bank_name` is set to "Manual Entry" as a direct attribute. However, the `Expense#bank_name` method (line 47) delegates to `email_account.bank_name`, so this direct assignment on the Expense model would be overridden.

**Expected Behavior**: The bank_name should come from the associated email account consistently.

**Actual Behavior**: The controller sets `@expense.bank_name = "Manual Entry"` but the model's `bank_name` method always returns `email_account.bank_name`. This means:
1. If the expense's email_account has a different bank_name, the model method returns the email_account's value
2. The directly set value on the expense is only stored if `bank_name` is a database column on expenses (it is, per schema)
3. But the model method overrides the column reader

This creates confusion about which value is actually displayed. The model method always delegates to `email_account.bank_name`, ignoring any value stored in the expense's own `bank_name` column.

**Recommended Fix**: Either remove the bank_name column from expenses (since it's derived from email_account), or update the model method to prefer the expense's own value:
```ruby
def bank_name
  self[:bank_name] || email_account&.bank_name
end
```

---

## Additional Observations (Not Findings)

### Positive Patterns Observed

1. **Comprehensive soft delete implementation**: The `SoftDelete` module properly filters deleted records via default scope and provides `restore!`, `with_deleted`, and `recently_deleted` functionality.

2. **Good error handling in services**: The `ExpenseFilterService` wraps all operations in a rescue block and returns structured error responses rather than raising.

3. **Accessibility foundations**: The layout includes skip navigation links, `aria-live` regions, semantic landmarks (`role="navigation"`, `role="main"`), and `aria-label` attributes on interactive elements.

4. **Security in expenses controller**: The `set_expense` method properly scopes to `current_user_expenses` with `RecordNotFound` rescue, preventing unauthorized access.

5. **Dashboard metric cards** have proper keyboard navigation (`tabindex="0"`, `keydown.enter` and `keydown.space` actions).

6. **Comprehensive inline actions** with both mouse and keyboard support, including category dropdowns with proper viewport-aware positioning.

### Areas Requiring Further Investigation (Cannot Verify Without Running Server)

1. **ActionCable real-time updates**: Cannot verify if `turbo_stream_from "dashboard_sync_updates"` properly receives and renders updates during sync operations.

2. **Budget progress partial**: The dashboard renders `shared/budget_progress` which could not be verified for existence or correct behavior.

3. **Filter persistence across page reloads**: The `dashboard-filter-persistence` controller stores state in localStorage, but correctness of restore behavior cannot be verified statically.

4. **Virtual scroll performance**: The virtual scroll threshold of 500 items cannot be load-tested without a running server.

5. **Cross-tab filter synchronization**: The `dashboard-filter-persistence` controller claims to sync across tabs, but this behavior requires runtime testing.

---

## Relationship to Known Open Issues

The 5 existing open issues in `docs/issues/` cover:
1. **Accessibility compliance violations** - Aligns with UX-003/UX-015 findings
2. **Authentication security gap** - Aligns with and is broader than UX-001
3. **JavaScript error boundary missing** - Not surfaced in this audit (infrastructure concern)
4. **Rate limiting configuration mismatch** - Not surfaced (backend concern)
5. **WebSocket connection recovery missing** - Not surfaced (infrastructure concern)

UX-001 (missing authentication on multiple controllers) is a broader issue than the existing authentication security gap issue, which only covers the queue API controller.

---

## Prioritized Remediation Plan

### Immediate (P0 - Before any deployment)
1. **UX-001**: Add authentication to all data-handling controllers
2. **UX-002**: Fix expense form email_account_id handling
3. **UX-007**: Run `bundle install` to restore gems and verify test suite

### Short-term (P1 - Next sprint)
4. **UX-003**: Fix N+1 query in expense row partial
5. **UX-004**: Correct delete confirmation messaging
6. **UX-005**: Integrate undo notification with single-expense delete
7. **UX-006**: Add pagination to expenses index page
8. **UX-008**: Change email account cascade behavior

### Medium-term (P2 - Within 2 sprints)
9. **UX-009**: Handle multi-currency display in dashboard
10. **UX-010**: Auto-dismiss flash messages
11. **UX-011**: Replace page reload with Turbo Stream for duplicate
12. **UX-012**: Fix show page status badge completeness
13. **UX-013**: Standardize keyboard shortcuts
14. **UX-014**: Dynamically populate bank filter
15. **UX-015**: Add mobile-responsive navigation

### Low priority (P3 - Backlog)
16. **UX-016**: I18n consistency
17. **UX-017**: Add footer
18. **UX-018**: Fix private helper visibility
19. **UX-019**: Add logout to navigation
20. **UX-020**: Resolve bank_name delegation inconsistency
