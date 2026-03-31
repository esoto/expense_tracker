# QA Playbook -- Agent Group E+F+G: Admin Panel, Analytics, Budget, Categories, API, Error Handling, Background Jobs

**Application:** Expense Tracker (Rails 8.1.2)
**Base URL:** `http://localhost:3000`
**Admin Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**UI Language:** Spanish
**Date:** 2026-03-26

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
