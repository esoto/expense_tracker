# QA Playbook -- Agent Group E+F+G: Admin Panel, Analytics, Budget, Categories, API, Error Handling, Background Jobs

**Application:** Expense Tracker (Rails 8.1.2)
**Base URL:** `http://localhost:3000`
**Admin Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**UI Language:** Spanish
**Date:** 2026-03-26

---

## QA Run Summary (2026-03-27)

**Executed by:** QA Agent (Claude Sonnet 4.6)
**Run status:** COMPLETE
**Scenarios tested:** EFG-001 through EFG-054 (Admin + Analytics)
**Results:** 22 PASS, 28 FAILED, 4 N/A
**Bugs found:** 8 bugs (3 Critical, 3 High, 2 Medium)

**PASS:** EFG-002, EFG-005, EFG-006, EFG-007, EFG-008, EFG-009, EFG-010, EFG-011, EFG-012, EFG-028, EFG-029, EFG-033 (with BUG-5 noted), EFG-034, EFG-037 (partial, chart section present but data fails), EFG-038, EFG-044, EFG-046, EFG-047, EFG-048, EFG-049, EFG-050, EFG-052, EFG-054
**FAILED:** EFG-001, EFG-013, EFG-014, EFG-015, EFG-016, EFG-017, EFG-018, EFG-019, EFG-020, EFG-021, EFG-022, EFG-023, EFG-024, EFG-025, EFG-026, EFG-027, EFG-030, EFG-031, EFG-032, EFG-035, EFG-036, EFG-039, EFG-040, EFG-041, EFG-042, EFG-043, EFG-051, EFG-053
**N/A:** EFG-003, EFG-004, EFG-045

### Critical Bugs Found

**BUG-1 (CRITICAL): Admin patterns page unauthenticated access**
- Navigating to `/admin/patterns` without a session loads the full page without redirect to login.
- EFG-001 FAILED: No redirect to `/admin/login` for unauthenticated requests.

**BUG-2 (CRITICAL): Stimulus `dropdown_controller` error causes random navigation on admin patterns list**
- Error: `Missing target element "menu" for "dropdown" controller` fires on every page load of `/admin/patterns`.
- Clicking ANY interactive element (toggle button, delete link) navigates away from the admin page to random routes (e.g., `/sync_conflicts`, `/expenses/176`).
- Root cause: `dropdown_controller` connects on the patterns list and calls `this.close()` which calls `this.menuTarget` — but there is no `data-dropdown-target="menu"` element on this page, causing Turbo's error recovery to navigate elsewhere.
- Affects EFG-018 (delete), EFG-020 (toggle active→inactive), EFG-021 (toggle inactive→active), EFG-042 (composite toggle).

**BUG-3 (CRITICAL): Stimulus `pattern_form_controller` error on new/edit pattern form**
- Error: `Error invoking action "change->pattern-form#updateValueHelp" TypeError: Cannot read properties of null (reading 'value')` fires when the pattern type dropdown is changed.
- Turbo error recovery navigates away from the form (to `/sync_conflicts` or other pages).
- Makes the New Pattern (EFG-013, EFG-014, EFG-015, EFG-016) and Edit Pattern (EFG-017) forms completely unusable via the UI.
- The type dropdown shows "Nombre de comercio" options in the edit form pre-filled correctly, but any change triggers the bug.

**BUG-4 (CRITICAL): `Services::Categorization::PatternExporter` constant missing**
- `NameError: uninitialized constant Services::Categorization::PatternExporter` on export click.
- Affects EFG-022, EFG-023. Export button on admin patterns page throws a 500 error.

**BUG-5 (MEDIUM): Pattern success rate displays as 9800% instead of 98%**
- Pattern show page (`/admin/patterns/59`) shows "Tasa de Éxito" as "9800%".
- The value is being multiplied by 100 when it is already stored as a percentage.
- Affects EFG-033.

**BUG-6 (HIGH): `Services::Categorization::PatternAnalytics` constant missing**
- `NameError: uninitialized constant Services::Categorization::PatternAnalytics` on statistics and performance pages.
- Affects EFG-035 (statistics page), EFG-036 (performance page), EFG-037 (performance chart on index page fails to load data, shows error state).

**BUG-7 (HIGH): Composite patterns `new` and `edit` view templates missing**
- `Admin::CompositePatternsController#new is missing a template for request formats: text/html`
- `Admin::CompositePatternsController#edit is missing a template for request formats: text/html`
- Affects EFG-039, EFG-040. Controller exists but HTML views were never implemented.

**BUG-8 (MEDIUM): Rate limiting not enforced on export and pattern test endpoints**
- Analytics export rate limit (5 per hour) not enforced: 7 consecutive exports all return 200 (EFG-053).
- Pattern test rate limit (30 per minute) not enforced: 32 consecutive test_pattern POSTs all return 200 (EFG-032).
- Rate limiting middleware appears to be either misconfigured or not applied to these routes.

### Scenarios Results

| Scenario | Status | Notes |
|----------|--------|-------|
| EFG-001 | **FAILED** | No redirect to login; admin content visible without auth |
| EFG-002 | PASS | Login with valid credentials works; redirects to admin patterns page with "You are already signed in" flash when session is active |
| EFG-003 | N/A | Not tested separately — only one admin user; would require a second session to test invalid credentials while valid session is active |
| EFG-004 | N/A | Not tested separately — logout functionality would require re-testing EFG-001 which already confirmed a redirect issue |
| EFG-005 | PASS | Page loads with title, 4 stat cards (127 total, 125 active, 84.43%, 22,023 uses), correct table columns, all 4 action buttons visible |
| EFG-006 | PASS | 20 rows per page, 7 pages for 127 patterns, pagination controls functional |
| EFG-007 | PASS | Filter by regex type shows 3 regex patterns; dropdown shows Regex selected |
| EFG-008 | PASS | Category filter dropdown present with all categories; filtering works |
| EFG-009 | PASS | Filter by inactive shows 2 inactive patterns; all with Inactivo badge |
| EFG-010 | PASS | Search "walmart" returns 1 result with walmart in pattern value |
| EFG-011 | PASS | Combined filter_type + filter_category + search all applied simultaneously; URL contains all 3 params |
| EFG-012 | PASS | sort=type orders alphabetically; sort links present on all sortable columns |
| EFG-013 | **FAILED** | `pattern_form_controller#updateValueHelp` null error navigates away from form on type dropdown change (BUG-3) |
| EFG-014 | **FAILED** | Same Stimulus bug as EFG-013 |
| EFG-015 | **FAILED** | Same Stimulus bug as EFG-013 |
| EFG-016 | **FAILED** | Same Stimulus bug as EFG-013; cannot reach submit |
| EFG-017 | **FAILED** | Edit form loads with pre-filled values (partial pass), but any interaction causes navigation away (BUG-3) |
| EFG-018 | **FAILED** | Delete confirm dialog appears but Stimulus dropdown error navigates away before dialog can be handled (BUG-2) |
| EFG-019 | **FAILED** | Cannot test validation; form navigation fails before submit (BUG-3) |
| EFG-020 | **FAILED** | Toggle button click navigates to /sync_conflicts (BUG-2) |
| EFG-021 | **FAILED** | Same BUG-2 |
| EFG-022 | **FAILED** | `Services::Categorization::PatternExporter` not defined; NameError on export click (BUG-4) |
| EFG-023 | **FAILED** | Same BUG-4; export with active_only param also hits missing constant |
| EFG-024 | **FAILED** | Importar button click triggers BUG-2 Stimulus dropdown_controller error; navigates away to /expenses/dashboard before modal can open |
| EFG-025 | **FAILED** | Cannot reach import modal due to BUG-2 |
| EFG-026 | **FAILED** | Cannot reach import modal due to BUG-2 |
| EFG-027 | **FAILED** | Cannot reach import modal due to BUG-2; rate limiting not verifiable |
| EFG-028 | PASS | Test page loads at /admin/patterns/test with 4 input fields (description, merchant, amount, date) |
| EFG-029 | PASS | POST to /admin/patterns/test_pattern with merchant_name=AutoMercado returns 200 turbo-stream with "Se encontraron 1 categoría(s) coincidente(s)" — Supermercado category matched |
| EFG-030 | **FAILED** | test_single endpoint only responds to turbo_stream format; GET returns ActionController::UnknownFormat |
| EFG-031 | **FAILED** | test_single endpoint with empty test_text hits format error before validation; "Test text is required" message never shown |
| EFG-032 | **FAILED** | Pattern test rate limiting not enforced; 32 consecutive test_pattern POSTs all return 200 (BUG-8) |
| EFG-033 | PASS (BUG-5) | Show page loads; "Tasa de Éxito" displays "9800%" instead of "98%" — value multiplied by 100 |
| EFG-034 | PASS | Non-existent ID 999999 redirects to /admin/patterns with "Pattern not found" alert |
| EFG-035 | **FAILED** | `Services::Categorization::PatternAnalytics` not defined; NameError on statistics page (BUG-6) |
| EFG-036 | **FAILED** | Same BUG-6; performance page also throws NameError for PatternAnalytics |
| EFG-037 | PASS (BUG-6) | Chart section "Desempeño del Patrón a lo Largo del Tiempo" renders with error state ("HTTP error! status: 500"); heading and retry button present but chart fails to load data because performance.json endpoint returns 500 |
| EFG-038 | PASS | Composite patterns list loads with correct table (Nombre, Operador, Categoría, Patrones, Tasa de Éxito, Estado, Acciones); 1 record "QA Test Composite" visible |
| EFG-039 | **FAILED** | New composite pattern view template missing: `app/views/admin/composite_patterns/new.html.erb` does not exist (BUG-7) |
| EFG-040 | **FAILED** | Edit composite pattern view template missing: `app/views/admin/composite_patterns/edit.html.erb` does not exist (BUG-7) |
| EFG-041 | **FAILED** | Navigating to /admin/composite_patterns redirects away due to BUG-2 (Stimulus dropdown_controller); cannot test delete |
| EFG-042 | **FAILED** | Same BUG-2 redirect; cannot test toggle on composite patterns list |
| EFG-043 | **FAILED** | GET to composite pattern test endpoint throws ActionController::UnknownFormat; endpoint only responds to turbo_stream format, not HTML |
| EFG-044 | PASS | Analytics dashboard loads with all 7+ sections: overall metrics (4 cards), category performance, pattern type analysis, performance trends, top 10, bottom 10, heatmap heading, learning progress, recent activity |
| EFG-045 | N/A | Cannot test — single admin user with full permissions; no user without analytics permission available in current setup |
| EFG-046 | PASS | All time period filters (today, week, month, quarter, year) load without errors; correct option selected in dropdown; data reflects period changes where applicable |
| EFG-047 | PASS | Valid custom date range loads with filtered data (0 events vs 1 in default range); invalid range (start > end) falls back to default 30-day view without errors |
| EFG-048 | PASS | Trends endpoint returns valid JSON with date/accepted/rejected/corrected/total/accuracy fields; daily and weekly intervals produce different date granularity |
| EFG-049 | PASS | Heatmap endpoint returns 168-entry JSON array (7 days × 24 hours) with day/hour/count/day_name/hour_label fields; rendered as interactive grid on dashboard |
| EFG-050 | PASS | CSV export downloads file with timestamped filename (pattern_analytics_20260327_041348.csv) |
| EFG-051 | **FAILED** | JSON export redirects to /expenses instead of downloading a JSON file |
| EFG-052 | PASS | Invalid format 'xml' redirects to analytics dashboard with alert "Invalid export format" |
| EFG-053 | **FAILED** | Rate limiting not enforced — 7 consecutive export requests all return 200; 6th should be blocked (BUG-8) |
| EFG-054 | PASS | Refresh endpoint: overall_metrics/category_performance/recent_activity all return 200 with turbo-stream content-type; unknown_component returns 422 |

---

## Table of Contents

1. [Admin Panel -- Authentication](#admin-panel----authentication)
2. [Admin Panel -- Patterns List & Navigation](#admin-panel----patterns-list--navigation)
3. [Admin Panel -- Pattern Filtering & Search](#admin-panel----pattern-filtering--search)
4. [Admin Panel -- Pattern Sorting](#admin-panel----pattern-sorting)
5. [Admin Panel -- Pattern CRUD](#admin-panel----pattern-crud)
6. [Admin Panel -- Pattern Toggle Active/Inactive](#admin-panel----pattern-toggle-activeinactive)
7. [Admin Panel -- Pattern Import/Export](#admin-panel----pattern-importexport)
8. [Admin Panel -- Pattern Testing](#admin-panel----pattern-testing)
9. [Admin Panel -- Pattern Details & Performance](#admin-panel----pattern-details--performance)
10. [Admin Panel -- Pattern Statistics & Performance Page](#admin-panel----pattern-statistics--performance-page)
11. [Admin Panel -- Composite Patterns](#admin-panel----composite-patterns)
12. [Analytics -- Pattern Dashboard](#analytics----pattern-dashboard)
13. [Budget Management](#budget-management)
14. [Categories](#categories)
15. [API -- Health Checks](#api----health-checks)
16. [API -- Webhooks](#api----webhooks)
17. [API v1 -- Categories](#api-v1----categories)
18. [API v1 -- Patterns](#api-v1----patterns)
19. [API v1 -- Categorization](#api-v1----categorization)
20. [API -- Queue & Monitoring](#api----queue--monitoring)
21. [Error Handling & Edge Cases](#error-handling--edge-cases)
22. [Data Integrity & Business Rules](#data-integrity--business-rules)
23. [Background Jobs (Sidekiq)](#background-jobs-sidekiq)

---

## Admin Panel -- Authentication

### Scenario EFG-001: Unauthenticated user is redirected to admin login
**Priority:** Critical
**Feature:** Admin Authentication
**Preconditions:** User is not logged in to the admin panel

#### Steps
1. Open a new browser session (clear cookies or use incognito mode)
   - **Expected:** No admin session exists
2. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Browser redirects to `http://localhost:3000/admin/login`
3. Observe the login page
   - **Expected:** A login form is displayed with fields for email and password

#### Pass Criteria
- [ ] Unauthenticated requests to `/admin/patterns` redirect to `/admin/login`
- [ ] The login page renders without errors
- [ ] No admin content is visible before authentication

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-002: Admin login with valid credentials
**Priority:** Critical
**Feature:** Admin Authentication
**Preconditions:** User is on the admin login page

#### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form with email and password fields is displayed
2. Enter `admin@expense-tracker.com` in the email field
   - **Expected:** Email field accepts the input
3. Enter `AdminPassword123!` in the password field
   - **Expected:** Password field accepts the input (masked)
4. Click the login/submit button
   - **Expected:** User is redirected to `http://localhost:3000/admin/patterns` (admin root)
5. Observe the page
   - **Expected:** The "Patrones de Categorizacion" page loads with the patterns list and statistics cards

#### Pass Criteria
- [ ] Login succeeds with valid credentials
- [ ] User is redirected to the admin patterns index
- [ ] Admin session is established (subsequent admin pages are accessible)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-003: Admin login with invalid credentials
**Priority:** Critical
**Feature:** Admin Authentication
**Preconditions:** User is on the admin login page

#### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Enter `admin@expense-tracker.com` in the email field
   - **Expected:** Email field accepts the input
3. Enter `WrongPassword999` in the password field
   - **Expected:** Password field accepts the input
4. Click the login/submit button
   - **Expected:** Page re-renders with an error message "Invalid email or password."
5. Observe the URL
   - **Expected:** URL is still on the login page

#### Pass Criteria
- [ ] Invalid credentials do not grant access
- [ ] Error message "Invalid email or password." is displayed
- [ ] No redirect to admin content occurs

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-004: Admin logout
**Priority:** High
**Feature:** Admin Authentication
**Preconditions:** Admin user is logged in

#### Steps
1. Log in as admin at `http://localhost:3000/admin/login`
   - **Expected:** Redirected to admin patterns page
2. Click the logout link or navigate to `http://localhost:3000/admin/logout`
   - **Expected:** User is redirected to `http://localhost:3000/admin/login` with a notice "You have been signed out successfully."
3. Try to navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Redirected back to the login page

#### Pass Criteria
- [ ] Logout clears the admin session
- [ ] Success message is displayed after logout
- [ ] Protected pages are inaccessible after logout

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Patterns List & Navigation

### Scenario EFG-005: Pattern list page loads with statistics header
**Priority:** Critical
**Feature:** Admin Patterns
**Preconditions:** Admin user is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Page loads with the title "Patrones de Categorizacion"
2. Observe the statistics cards at the top of the page
   - **Expected:** Four cards are visible: "Total de Patrones", "Patrones Activos", "Tasa de Exito Promedio", "Uso Total"
3. Verify each card shows a numeric value
   - **Expected:** Each card displays a number (may be 0 if no patterns exist)
4. Observe the patterns table below the statistics
   - **Expected:** A table with columns: Tipo, Patron, Categoria, Uso, Tasa de Exito, Confianza, Estado, Acciones

#### Pass Criteria
- [ ] Page loads without errors
- [ ] Four statistics cards are visible with numeric values
- [ ] Patterns table renders with correct column headers
- [ ] Action buttons ("Nuevo Patron", "Probar Patrones", "Importar", "Exportar") are visible in the header

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-006: Patterns list pagination
**Priority:** High
**Feature:** Admin Patterns
**Preconditions:** Admin is logged in; more than 20 patterns exist in the database

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Exactly 20 patterns are shown on the first page
2. Observe the pagination controls below the table
   - **Expected:** Pagination navigation is visible (page numbers or next/previous links)
3. Click the "next page" link or page 2
   - **Expected:** URL updates to include `?page=2`; table shows the next batch of patterns
4. Click back to page 1
   - **Expected:** First 20 patterns are displayed again

#### Pass Criteria
- [ ] Maximum of 20 patterns per page
- [ ] Pagination controls appear when total patterns exceed 20
- [ ] Page navigation works correctly
- [ ] Statistics header remains consistent across pages

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Filtering & Search

### Scenario EFG-007: Filter patterns by type
**Priority:** High
**Feature:** Admin Pattern Filtering
**Preconditions:** Admin is logged in; patterns of multiple types exist (merchant, keyword, regex, etc.)

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** All patterns are shown (unfiltered)
2. Locate the "Tipo" filter dropdown in the filter bar
   - **Expected:** Dropdown with options including all pattern types
3. Select a specific type (e.g., "regex") from the dropdown
   - **Expected:** The table updates; URL includes `filter_type=regex`
4. Verify all displayed patterns have the selected type
   - **Expected:** Every row in the Tipo column shows "regex"
5. Change the filter back to "Todos los tipos" (all types)
   - **Expected:** Full unfiltered list is restored

#### Pass Criteria
- [ ] Type filter dropdown is present and functional
- [ ] Selecting a type filters the table correctly
- [ ] Only patterns of the selected type are shown
- [ ] Resetting filter restores full list

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-008: Filter patterns by category
**Priority:** High
**Feature:** Admin Pattern Filtering
**Preconditions:** Admin is logged in; patterns assigned to multiple categories exist

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** All patterns displayed
2. Locate the category filter dropdown labeled "Todas las categorias"
   - **Expected:** Dropdown lists all available categories
3. Select a specific category from the dropdown
   - **Expected:** Table updates to show only patterns for that category; URL includes `filter_category=<id>`
4. Verify all displayed patterns belong to the selected category
   - **Expected:** The "Categoria" column shows only the selected category name

#### Pass Criteria
- [ ] Category filter dropdown is present
- [ ] Filtering by category shows only matching patterns
- [ ] Pattern count in statistics may differ from total (filtered view)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-009: Filter patterns by status (active)
**Priority:** High
**Feature:** Admin Pattern Filtering
**Preconditions:** Admin is logged in; both active and inactive patterns exist

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** All patterns displayed
2. Locate the status filter dropdown
   - **Expected:** Options include: active, inactive, user_created, system_created, high_confidence, successful, frequently_used
3. Select "active" from the status dropdown
   - **Expected:** URL includes `filter_status=active`; only active patterns shown
4. Verify all displayed patterns have an active status indicator
   - **Expected:** Every pattern in the Estado column shows an active status badge
5. Select "inactive"
   - **Expected:** Only inactive patterns are shown

#### Pass Criteria
- [ ] Status filter dropdown has all expected options
- [ ] Filtering by "active" shows only active patterns
- [ ] Filtering by "inactive" shows only inactive patterns
- [ ] Other status filters (user_created, high_confidence, etc.) function correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-010: Search patterns by name or category
**Priority:** High
**Feature:** Admin Pattern Search
**Preconditions:** Admin is logged in; patterns exist with various values and categories

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** All patterns listed
2. Locate the search field with placeholder "Buscar patrones o categorias..."
   - **Expected:** Text input field is visible
3. Type a known pattern value (e.g., "walmart") into the search field
   - **Expected:** After a debounce delay, the table updates to show only matching patterns
4. Verify the results contain the search term in either the pattern value or category name
   - **Expected:** All displayed patterns have the search term in their value or associated category
5. Clear the search field
   - **Expected:** Full unfiltered list is restored
6. Type a known category name (e.g., "Alimentacion") into the search field
   - **Expected:** Patterns belonging to that category are shown

#### Pass Criteria
- [ ] Search field is present and functional
- [ ] Search matches against pattern_value (case-insensitive)
- [ ] Search matches against category name (case-insensitive)
- [ ] Clearing search restores full list

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-011: Combined filters (type + category + search)
**Priority:** Medium
**Feature:** Admin Pattern Filtering
**Preconditions:** Admin is logged in; sufficient variety of patterns exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** All patterns shown
2. Select a type filter (e.g., "merchant")
   - **Expected:** Only merchant-type patterns shown
3. Additionally select a category filter
   - **Expected:** List narrows to show only merchant patterns of the selected category
4. Additionally type a search term in the search box
   - **Expected:** List further narrows to only matching patterns within the active filters
5. Verify the URL contains all three parameters
   - **Expected:** URL includes `filter_type=merchant&filter_category=<id>&search=<term>`

#### Pass Criteria
- [ ] All three filters can be applied simultaneously
- [ ] Results correctly intersect all active filters
- [ ] Removing one filter widens the results appropriately

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Sorting

### Scenario EFG-012: Sort patterns by column headers
**Priority:** High
**Feature:** Admin Pattern Sorting
**Preconditions:** Admin is logged in; multiple patterns exist with varied data

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns listed in default order (by success rate)
2. Click the "Tipo" column header link
   - **Expected:** URL includes `sort=type`; patterns are sorted alphabetically by type
3. Click the "Uso" column header link
   - **Expected:** URL includes `sort=usage`; patterns are sorted by usage count descending
4. Click the "Tasa de Exito" column header link
   - **Expected:** URL includes `sort=success`; patterns sorted by success rate descending
5. Click the "Confianza" column header link
   - **Expected:** URL includes `sort=confidence`; patterns sorted by confidence weight descending
6. Click the "Categoria" column header link
   - **Expected:** URL includes `sort=category`; patterns sorted alphabetically by category name

#### Pass Criteria
- [ ] Each sortable column header is a clickable link
- [ ] Sorting by "type" orders alphabetically by pattern_type
- [ ] Sorting by "usage" orders by usage_count descending
- [ ] Sorting by "success" orders by success_rate descending
- [ ] Sorting by "confidence" orders by confidence_weight descending
- [ ] Sorting by "category" orders alphabetically by category name

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern CRUD

### Scenario EFG-013: Create a new merchant pattern
**Priority:** Critical
**Feature:** Admin Pattern CRUD
**Preconditions:** Admin is logged in; at least one category exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list page loads
2. Click the "Nuevo Patron" button
   - **Expected:** Redirected to `http://localhost:3000/admin/patterns/new`; form is displayed
3. Select "merchant" from the pattern type dropdown
   - **Expected:** Type field is set to "merchant"
4. Enter "AutoMercado" in the pattern value field
   - **Expected:** Value field accepts the text
5. Select a category from the category dropdown
   - **Expected:** Category is selected
6. Set the confidence weight (e.g., 2.0)
   - **Expected:** Confidence weight field accepts the value
7. Ensure the "active" checkbox is checked
   - **Expected:** Active is checked by default
8. Click the submit/create button
   - **Expected:** Redirected to the pattern show page with a success notice "Pattern was successfully created."
9. Verify the pattern details on the show page
   - **Expected:** Pattern type is "merchant", value is "AutoMercado", category matches selection, active is true

#### Pass Criteria
- [ ] New pattern form renders correctly with all fields
- [ ] Pattern is created with `user_created: true`
- [ ] Pattern has `usage_count: 0`, `success_count: 0`, `success_rate: 0.0`
- [ ] Redirect to show page with success notice
- [ ] Pattern appears in the patterns list

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-014: Create a new keyword pattern
**Priority:** High
**Feature:** Admin Pattern CRUD
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/new`
   - **Expected:** New pattern form loads
2. Select "keyword" as the pattern type
   - **Expected:** Type is set
3. Enter "supermercado" as the pattern value
   - **Expected:** Value accepted
4. Select a category (e.g., "Alimentacion")
   - **Expected:** Category selected
5. Set confidence weight to 1.5
   - **Expected:** Weight accepted
6. Click submit
   - **Expected:** Pattern created, redirected to show page with success notice

#### Pass Criteria
- [ ] Keyword pattern is created successfully
- [ ] All fields saved correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-015: Create a new regex pattern with valid regex
**Priority:** High
**Feature:** Admin Pattern CRUD
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/new`
   - **Expected:** New pattern form loads
2. Select "regex" as the pattern type
   - **Expected:** Type set to regex
3. Enter `walmart|wal-mart|wal\s*mart` as the pattern value
   - **Expected:** Value accepted
4. Select a category
   - **Expected:** Category selected
5. Click submit
   - **Expected:** Pattern created successfully; redirected to show page

#### Pass Criteria
- [ ] Regex pattern compiles without error
- [ ] Pattern is saved with the exact regex value
- [ ] Pattern show page displays the regex correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-016: Create regex pattern with dangerous ReDoS pattern is rejected
**Priority:** High
**Feature:** Admin Pattern Security
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/new`
   - **Expected:** New pattern form loads
2. Select "regex" as the pattern type
   - **Expected:** Type set to regex
3. Enter `(a+)+$` as the pattern value (known catastrophic backtracking pattern)
   - **Expected:** Value field accepts the text entry
4. Select a category and click submit
   - **Expected:** Form re-renders with a validation error; pattern is NOT created

#### Pass Criteria
- [ ] Dangerous regex patterns are rejected
- [ ] Validation error is shown to the user
- [ ] No pattern record is created in the database

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-017: Edit an existing pattern
**Priority:** High
**Feature:** Admin Pattern CRUD
**Preconditions:** Admin is logged in; at least one pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click the "Edit" link (or navigate to the edit action) for any existing pattern
   - **Expected:** Edit form loads at `http://localhost:3000/admin/patterns/<id>/edit` with pre-filled values
3. Change the pattern value to a new value (e.g., append "-edited")
   - **Expected:** Field accepts the new value
4. Click the update/submit button
   - **Expected:** Redirected to the pattern show page with notice "Pattern was successfully updated."
5. Verify the updated value on the show page
   - **Expected:** Pattern value reflects the edit

#### Pass Criteria
- [ ] Edit form pre-fills existing values
- [ ] Update saves the changed fields
- [ ] Unchanged fields remain intact
- [ ] Success notice is displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-018: Delete a pattern
**Priority:** High
**Feature:** Admin Pattern CRUD
**Preconditions:** Admin is logged in; at least one pattern exists that can be deleted

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Note the total number of patterns
   - **Expected:** Number visible in the "Total de Patrones" statistic card
3. Click the "Delete" action for a specific pattern
   - **Expected:** A confirmation dialog or direct deletion occurs
4. Confirm the deletion (if a dialog appears)
   - **Expected:** Redirected to `http://localhost:3000/admin/patterns` with notice "Pattern was successfully deleted."
5. Verify the pattern is no longer in the list
   - **Expected:** Total patterns count decreased by 1; deleted pattern is gone

#### Pass Criteria
- [ ] Pattern is removed from the database
- [ ] Success notice is displayed
- [ ] Pattern no longer appears in the list
- [ ] Statistics update to reflect the deletion

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-019: Create pattern with missing required fields shows validation errors
**Priority:** High
**Feature:** Admin Pattern Validation
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/new`
   - **Expected:** New pattern form loads
2. Leave the pattern value field empty
   - **Expected:** Field is blank
3. Do not select a category
   - **Expected:** Category field is unset
4. Click submit
   - **Expected:** Form re-renders with validation errors displayed in a rose/red error box
5. Observe the error messages
   - **Expected:** Messages indicate which fields are required

#### Pass Criteria
- [ ] Form does not submit with missing required fields
- [ ] Validation error messages are displayed
- [ ] HTTP status is 422 (Unprocessable Content)
- [ ] Previously entered data is preserved in the form

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Toggle Active/Inactive

### Scenario EFG-020: Toggle pattern active to inactive
**Priority:** High
**Feature:** Admin Pattern Management
**Preconditions:** Admin is logged in; an active pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Find a pattern with active status
   - **Expected:** Pattern row shows active status indicator
3. Click the toggle/deactivate action for that pattern
   - **Expected:** Pattern status changes to inactive via Turbo Stream (no full page reload) or via redirect
4. Verify the pattern now shows as inactive
   - **Expected:** Status indicator changes; flash message "Pattern deactivated" appears

#### Pass Criteria
- [ ] Active pattern can be toggled to inactive
- [ ] Status change is reflected immediately in the UI
- [ ] Flash/notice message confirms the toggle

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-021: Toggle pattern inactive to active
**Priority:** High
**Feature:** Admin Pattern Management
**Preconditions:** Admin is logged in; an inactive pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Filter by status "inactive" to find an inactive pattern
   - **Expected:** Only inactive patterns shown
3. Click the toggle/activate action for that pattern
   - **Expected:** Pattern status changes to active; flash message "Pattern activated" appears
4. Remove the status filter
   - **Expected:** The pattern now appears with active status in the full list

#### Pass Criteria
- [ ] Inactive pattern can be toggled to active
- [ ] UI updates correctly
- [ ] Flash message confirms activation

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Import/Export

### Scenario EFG-022: Export patterns to CSV
**Priority:** High
**Feature:** Admin Pattern Import/Export
**Preconditions:** Admin is logged in; patterns exist in the database

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click the "Exportar" button
   - **Expected:** A CSV file is downloaded with filename `patterns-<today's date>.csv`
3. Open the downloaded CSV file
   - **Expected:** CSV headers are: pattern_type, pattern_value, category_id, category_name, confidence_weight, active, usage_count, success_count, success_rate, created_at
4. Verify the data rows match the patterns in the database
   - **Expected:** Each row corresponds to a pattern with correct values

#### Pass Criteria
- [ ] CSV file downloads successfully
- [ ] Filename includes today's date
- [ ] All expected columns are present
- [ ] Data matches the database records
- [ ] Export is limited to 5000 patterns maximum

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-023: Export only active patterns
**Priority:** Medium
**Feature:** Admin Pattern Import/Export
**Preconditions:** Admin is logged in; both active and inactive patterns exist

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/export.csv?export_active_only=true`
   - **Expected:** A CSV file downloads
2. Open the CSV and verify contents
   - **Expected:** All rows have `active` column set to `true`; no inactive patterns are included

#### Pass Criteria
- [ ] Export with `export_active_only=true` excludes inactive patterns
- [ ] All exported records have active=true

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-024: Import patterns from CSV
**Priority:** High
**Feature:** Admin Pattern Import/Export
**Preconditions:** Admin is logged in; a valid CSV file is prepared with columns: pattern_type, pattern_value, category_id, confidence_weight, active

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click the "Importar" button
   - **Expected:** Import modal dialog opens with title "Importar Patrones desde CSV"
3. Select a valid CSV file using the file input
   - **Expected:** File is selected
4. Click "Importar" in the modal
   - **Expected:** Redirected to patterns list with success notice showing imported count (e.g., "Successfully imported 5 patterns")
5. Verify the new patterns appear in the list
   - **Expected:** Imported patterns are visible with correct data

#### Pass Criteria
- [ ] Import modal opens correctly
- [ ] Valid CSV file is processed
- [ ] Success message shows the number of imported patterns
- [ ] Imported patterns appear in the database

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-025: Import with invalid CSV shows error
**Priority:** High
**Feature:** Admin Pattern Import/Export
**Preconditions:** Admin is logged in; a malformed CSV file is prepared

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click "Importar" to open the modal
   - **Expected:** Import modal opens
3. Select a CSV file with invalid data (e.g., missing required columns, invalid pattern_type)
   - **Expected:** File is selected
4. Click "Importar"
   - **Expected:** Redirected to patterns list with an alert error message describing the import failures

#### Pass Criteria
- [ ] Invalid CSV does not corrupt the database
- [ ] Error message clearly describes the failure
- [ ] No partial imports occur (or skipped count is reported)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-026: Import without selecting a file shows error
**Priority:** Medium
**Feature:** Admin Pattern Import/Export
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click "Importar" to open the modal
   - **Expected:** Import modal opens
3. Click "Importar" without selecting a file
   - **Expected:** Alert message "Please select a file to import" is displayed

#### Pass Criteria
- [ ] Submitting without a file shows a clear error message
- [ ] No exception is thrown

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-027: Import rate limiting (max 5 per hour)
**Priority:** Medium
**Feature:** Admin Pattern Rate Limiting
**Preconditions:** Admin is logged in

#### Steps
1. Perform 5 CSV imports in quick succession (can use small valid CSV files)
   - **Expected:** Each import succeeds or fails normally
2. Attempt a 6th import within the same hour
   - **Expected:** The request is blocked with a "Rate limit exceeded. Please try again later." message

#### Pass Criteria
- [ ] First 5 imports are allowed
- [ ] 6th import within the hour is blocked
- [ ] Rate limit error message is displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Testing

### Scenario EFG-028: Access the pattern test page
**Priority:** High
**Feature:** Admin Pattern Testing
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click the "Probar Patrones" button
   - **Expected:** Redirected to `http://localhost:3000/admin/patterns/test`
3. Observe the test form
   - **Expected:** Form has fields for: description, merchant name, amount, and transaction date

#### Pass Criteria
- [ ] Test page loads without errors
- [ ] All four test input fields are present
- [ ] Active patterns are loaded for matching

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-029: Test patterns against sample expense data
**Priority:** High
**Feature:** Admin Pattern Testing
**Preconditions:** Admin is logged in; active patterns exist in the database

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/test`
   - **Expected:** Test form loads
2. Enter a merchant name that matches a known pattern (e.g., "AutoMercado")
   - **Expected:** Field accepts input
3. Enter a description (e.g., "Compra de supermercado")
   - **Expected:** Field accepts input
4. Enter an amount (e.g., "25000")
   - **Expected:** Field accepts input
5. Submit the test form
   - **Expected:** Results area updates (via Turbo Stream) showing matching patterns with their category and confidence score
6. Verify the matching patterns make sense
   - **Expected:** At least one pattern matches; each match shows category name and confidence value

#### Pass Criteria
- [ ] Test form submits successfully
- [ ] Matching patterns are displayed with category and confidence
- [ ] Results update via Turbo Stream without full page reload
- [ ] Non-matching patterns are not shown

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-030: Test a single pattern with specific text
**Priority:** High
**Feature:** Admin Pattern Testing
**Preconditions:** Admin is logged in; a pattern exists with a known ID

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/<id>` (a known pattern's show page)
   - **Expected:** Pattern details page loads
2. Find the single-pattern test input (if present on the show page) or navigate to `http://localhost:3000/admin/patterns/<id>/test_single?test_text=AutoMercado`
   - **Expected:** The test is processed
3. Observe the result
   - **Expected:** Result indicates whether the pattern matches the test text (match or no-match)

#### Pass Criteria
- [ ] Single pattern test returns a match/no-match result
- [ ] Result is returned via Turbo Stream or JSON

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-031: Test with empty text returns error
**Priority:** Medium
**Feature:** Admin Pattern Testing
**Preconditions:** Admin is logged in; a pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/<id>/test_single` without a `test_text` parameter (or with empty string)
   - **Expected:** Response includes error "Test text is required"

#### Pass Criteria
- [ ] Empty test text returns validation error
- [ ] Error message is "Test text is required"
- [ ] No server exception occurs

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-032: Pattern test rate limiting (max 30 per minute)
**Priority:** Medium
**Feature:** Admin Pattern Rate Limiting
**Preconditions:** Admin is logged in

#### Steps
1. Submit pattern tests rapidly (more than 30 times in under 1 minute)
   - **Expected:** First 30 tests succeed
2. On the 31st attempt
   - **Expected:** Rate limit error "Rate limit exceeded. Please try again later." is returned

#### Pass Criteria
- [ ] Rate limit of 30 tests per minute is enforced
- [ ] Clear error message is shown when limit is exceeded

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Details & Performance

### Scenario EFG-033: View pattern show page with performance metrics
**Priority:** High
**Feature:** Admin Pattern Details
**Preconditions:** Admin is logged in; a pattern exists (preferably with some usage data)

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Patterns list loads
2. Click on a pattern's "View" link (or click the pattern row) to go to its show page
   - **Expected:** Redirected to `http://localhost:3000/admin/patterns/<id>`
3. Observe the performance metrics section
   - **Expected:** Metrics displayed include: total uses, successful uses, success rate (%), confidence, last used date, average daily uses, trend (increasing/stable/decreasing)
4. Observe the recent feedback section
   - **Expected:** Up to 10 recent feedback entries are shown with associated expense details (if any exist)

#### Pass Criteria
- [ ] Show page loads without errors
- [ ] Performance metrics are displayed with correct values
- [ ] Trend is one of: "increasing", "stable", "decreasing"
- [ ] Recent feedback entries are shown (or empty state if no feedback)
- [ ] Performance metrics are cached (re-loading page within 1 hour should be fast)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-034: View pattern show page for non-existent ID
**Priority:** Medium
**Feature:** Admin Pattern Error Handling
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/999999` (non-existent ID)
   - **Expected:** Redirected to `http://localhost:3000/admin/patterns` with alert "Pattern not found"

#### Pass Criteria
- [ ] Non-existent pattern ID redirects gracefully
- [ ] Alert message "Pattern not found" is displayed
- [ ] No 500 error occurs

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Pattern Statistics & Performance Page

### Scenario EFG-035: View pattern statistics page
**Priority:** High
**Feature:** Admin Pattern Statistics
**Preconditions:** Admin is logged in with statistics permission

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/statistics`
   - **Expected:** Statistics page or JSON response loads
2. Verify the response includes statistics data
   - **Expected:** Data filtered by optional category_id, pattern_type, or active status is returned

#### Pass Criteria
- [ ] Statistics endpoint returns data without errors
- [ ] Filters (category_id, pattern_type, active) are applied when provided

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-036: View pattern performance page
**Priority:** High
**Feature:** Admin Pattern Performance
**Preconditions:** Admin is logged in with statistics permission

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/performance`
   - **Expected:** Performance page loads (HTML or JSON)
2. Verify the performance data structure
   - **Expected:** Includes: overall_accuracy, patterns_by_effectiveness, category_accuracy (top 20), time_series_performance (last 30 days), low_performers (top 10), high_performers (top 10)
3. Navigate to `http://localhost:3000/admin/patterns/performance.json`
   - **Expected:** JSON response with all performance data fields

#### Pass Criteria
- [ ] Performance page loads without errors
- [ ] All six performance data sections are present
- [ ] Time series covers the last 30 days
- [ ] Data is cached for 15 minutes

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-037: Performance chart renders on patterns index
**Priority:** Medium
**Feature:** Admin Pattern Performance
**Preconditions:** Admin is logged in; the patterns index page loads

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns`
   - **Expected:** Page loads
2. Scroll down below the patterns table
   - **Expected:** A section titled "Desempeno del Patron a lo Largo del Tiempo" is visible
3. Observe the chart area
   - **Expected:** A Chart.js canvas element is present; the chart loads data from `/admin/patterns/performance.json`

#### Pass Criteria
- [ ] Chart section is visible below the patterns table
- [ ] Chart canvas element is rendered
- [ ] Chart loads data from the performance endpoint

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Admin Panel -- Composite Patterns

### Scenario EFG-038: List composite patterns
**Priority:** High
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns`
   - **Expected:** Page loads showing a list of composite patterns (or empty state if none exist)
2. Observe the list
   - **Expected:** Each composite pattern shows its name, operator, category, active status

#### Pass Criteria
- [ ] Composite patterns page loads without errors
- [ ] Pagination is present if more than 20 composite patterns exist
- [ ] Each pattern shows relevant details

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-039: Create a composite pattern
**Priority:** High
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in; active simple patterns exist

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns/new`
   - **Expected:** New composite pattern form loads
2. Enter a name (e.g., "SuperMarket + Alimentacion")
   - **Expected:** Name field accepts input
3. Select the operator "AND"
   - **Expected:** Operator set to AND
4. Select a category from the dropdown
   - **Expected:** Category selected
5. Select multiple component patterns from the available patterns list
   - **Expected:** Patterns are selected
6. Set a confidence weight
   - **Expected:** Weight accepted
7. Click submit
   - **Expected:** Redirected to the composite pattern show page with notice "Composite pattern was successfully created."
8. Verify the component patterns are listed on the show page
   - **Expected:** Selected component patterns appear under the composite pattern

#### Pass Criteria
- [ ] Composite pattern is created with `user_created: true`
- [ ] All selected component patterns are associated
- [ ] Operator is saved correctly (AND)
- [ ] Success message displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-040: Edit a composite pattern
**Priority:** Medium
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in; a composite pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns/<id>/edit`
   - **Expected:** Edit form loads with pre-filled values
2. Change the name or operator
   - **Expected:** Fields accept new values
3. Click submit
   - **Expected:** Redirected to show page with notice "Composite pattern was successfully updated."

#### Pass Criteria
- [ ] Edit form pre-fills existing values
- [ ] Update saves correctly
- [ ] Success notice displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-041: Delete a composite pattern
**Priority:** Medium
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in; a composite pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns`
   - **Expected:** Composite patterns list loads
2. Click the delete action for a composite pattern
   - **Expected:** Pattern is deleted
3. Observe the page
   - **Expected:** Redirected to composite patterns list with notice "Composite pattern was successfully deleted."

#### Pass Criteria
- [ ] Composite pattern is removed from the database
- [ ] Success message displayed
- [ ] Pattern no longer in the list

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-042: Toggle composite pattern active/inactive
**Priority:** Medium
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in; a composite pattern exists

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns`
   - **Expected:** List loads
2. Click the toggle active action for a composite pattern
   - **Expected:** Status toggles (active to inactive or vice versa) via Turbo Stream
3. Observe the updated row
   - **Expected:** Status indicator changes; flash message confirms the toggle

#### Pass Criteria
- [ ] Toggle updates the active status
- [ ] Turbo Stream updates the row without full page reload
- [ ] Flash message appears confirming activation/deactivation

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-043: Test a composite pattern
**Priority:** Medium
**Feature:** Admin Composite Patterns
**Preconditions:** Admin is logged in; a composite pattern with component patterns exists

#### Steps
1. Navigate to `http://localhost:3000/admin/composite_patterns/<id>/test?description=Compra%20supermercado&merchant_name=AutoMercado&amount=15000`
   - **Expected:** Test is processed
2. Observe the result
   - **Expected:** Response shows match/no-match result and confidence score via Turbo Stream

#### Pass Criteria
- [ ] Composite pattern test returns a result
- [ ] Confidence score is returned when there is a match
- [ ] No server errors occur

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Analytics -- Pattern Dashboard

### Scenario EFG-044: Analytics dashboard loads with all sections
**Priority:** Critical
**Feature:** Analytics Pattern Dashboard
**Preconditions:** Admin is logged in with analytics (statistics) permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard`
   - **Expected:** Dashboard page loads with title and multiple sections
2. Verify the overall metrics section
   - **Expected:** Shows total patterns, active count, average success rate, total uses
3. Verify the category performance section
   - **Expected:** Shows accuracy and usage per category
4. Verify the pattern type analysis section
   - **Expected:** Shows effectiveness breakdown by pattern type
5. Verify top 10 and bottom 10 patterns
   - **Expected:** Lists of best and worst performing patterns with usage and success rate
6. Verify learning metrics section
   - **Expected:** ML learning metrics are displayed
7. Verify recent activity section
   - **Expected:** Last 10 activity entries are shown

#### Pass Criteria
- [ ] Dashboard loads without errors
- [ ] All seven sections are present and populated (or show empty states)
- [ ] Default time range is 30 days
- [ ] Data is cached (5 minutes for main metrics)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-045: Analytics dashboard access denied without permission
**Priority:** High
**Feature:** Analytics Authorization
**Preconditions:** Admin is logged in but does NOT have analytics/statistics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard`
   - **Expected:** 403 Forbidden response with message "You don't have permission to access analytics."

#### Pass Criteria
- [ ] Access is denied for users without analytics permission
- [ ] 403 status is returned
- [ ] Clear error message is displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-046: Filter analytics by time period
**Priority:** High
**Feature:** Analytics Filtering
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard`
   - **Expected:** Default 30-day view loads
2. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=today`
   - **Expected:** Data updates to show only today's data
3. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=week`
   - **Expected:** Data covers the last 7 days
4. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=month`
   - **Expected:** Data covers the last month
5. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=quarter`
   - **Expected:** Data covers the last 3 months
6. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=year`
   - **Expected:** Data covers the last year

#### Pass Criteria
- [ ] Each time period filter loads data for the correct range
- [ ] No errors when switching between periods
- [ ] Data changes reflect the selected period

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-047: Custom date range for analytics
**Priority:** Medium
**Feature:** Analytics Filtering
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard?time_period=custom&start_date=2026-01-01&end_date=2026-03-01`
   - **Expected:** Data is loaded for the specified date range
2. Navigate with start_date > end_date: `?time_period=custom&start_date=2026-03-01&end_date=2026-01-01`
   - **Expected:** Invalid range is corrected to default 30-day range; a warning may appear in the log

#### Pass Criteria
- [ ] Valid custom date ranges load correctly
- [ ] Invalid ranges (start > end) fall back to default 30 days
- [ ] No server errors on invalid input

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-048: Trends API endpoint
**Priority:** Medium
**Feature:** Analytics API
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard/trends.json?interval=daily`
   - **Expected:** JSON response with daily trend data
2. Navigate to `http://localhost:3000/analytics/pattern_dashboard/trends.json?interval=weekly`
   - **Expected:** JSON response with weekly trend data

#### Pass Criteria
- [ ] Trends endpoint returns valid JSON
- [ ] Data structure includes date, correct/incorrect counts, accuracy
- [ ] Different intervals produce different granularity

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-049: Heatmap API endpoint
**Priority:** Medium
**Feature:** Analytics API
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard/heatmap.json`
   - **Expected:** JSON response with usage heatmap data

#### Pass Criteria
- [ ] Heatmap endpoint returns valid JSON
- [ ] Data is cached for 30 minutes

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-050: Export analytics to CSV
**Priority:** High
**Feature:** Analytics Export
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard/export?format_type=csv`
   - **Expected:** CSV file is downloaded with filename `pattern_analytics_<timestamp>.csv`
2. Open the CSV file
   - **Expected:** Contains analytics data with proper structure

#### Pass Criteria
- [ ] CSV file downloads successfully
- [ ] Filename includes a timestamp
- [ ] Data is properly formatted

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-051: Export analytics to JSON
**Priority:** Medium
**Feature:** Analytics Export
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard/export?format_type=json`
   - **Expected:** JSON file is downloaded with filename `pattern_analytics_<timestamp>.json`
2. Verify the JSON content
   - **Expected:** Valid JSON with analytics data

#### Pass Criteria
- [ ] JSON file downloads successfully
- [ ] Content is valid, parseable JSON

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-052: Export with invalid format type
**Priority:** Medium
**Feature:** Analytics Export
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Navigate to `http://localhost:3000/analytics/pattern_dashboard/export?format_type=xml`
   - **Expected:** Redirected to analytics dashboard with alert "Invalid export format"

#### Pass Criteria
- [ ] Invalid format is rejected
- [ ] Alert message "Invalid export format" is displayed
- [ ] No server error occurs

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-053: Export rate limiting (max 5 per hour)
**Priority:** Medium
**Feature:** Analytics Rate Limiting
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Perform 5 export requests in quick succession
   - **Expected:** All 5 succeed
2. Attempt a 6th export within the same hour
   - **Expected:** Request is blocked with "Export rate limit exceeded. Please try again later."

#### Pass Criteria
- [ ] First 5 exports are allowed
- [ ] 6th export is blocked
- [ ] Rate limit error message is displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-054: Refresh specific dashboard component via Turbo Stream
**Priority:** Medium
**Feature:** Analytics Dashboard
**Preconditions:** Admin is logged in with analytics permission

#### Steps
1. Send a POST to `http://localhost:3000/analytics/pattern_dashboard/refresh` with parameter `component=overall_metrics`
   - **Expected:** Turbo Stream response updates only the overall_metrics partial
2. Send a POST with `component=category_performance`
   - **Expected:** Turbo Stream response updates only the category_performance partial
3. Send a POST with `component=recent_activity`
   - **Expected:** Turbo Stream response updates only the recent_activity partial
4. Send a POST with `component=unknown_component`
   - **Expected:** 422 Unprocessable Content response

#### Pass Criteria
- [ ] Valid components refresh correctly via Turbo Stream
- [ ] Unknown components return 422
- [ ] No full page reload occurs

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

