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

## Budget Management

### Scenario EFG-055: Budget list page loads
**Priority:** Critical
**Feature:** Budget Management
**Preconditions:** User is logged in (main app, not admin); an active email account exists; at least one budget exists

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Page loads with title "Presupuestos"
2. Observe the budget cards grouped by period
   - **Expected:** Budgets are organized under period headings (e.g., "Mensual", "Semanal")
3. Verify each budget card shows: name, category, amount, usage percentage, status (Activo/Inactivo)
   - **Expected:** All fields are populated correctly
4. Verify the "Nuevo Presupuesto" button is visible
   - **Expected:** Teal button with "Nuevo Presupuesto" text is present

#### Pass Criteria
- [ ] Budget list page loads without errors
- [ ] Budgets are grouped by period
- [ ] Each card shows name, category, amount, usage %, and status
- [ ] Active budgets appear before inactive (sorted by active desc)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-056: Budget list with no email account redirects
**Priority:** High
**Feature:** Budget Management
**Preconditions:** No active email account exists in the database

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Redirected to root path with alert "Debes configurar una cuenta de correo primero."

#### Pass Criteria
- [ ] Redirect to root occurs
- [ ] Alert message in Spanish is displayed
- [ ] No server error

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-057: Budget list with no budgets shows empty state
**Priority:** Medium
**Feature:** Budget Management
**Preconditions:** User is logged in; active email account exists; no budgets exist

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Empty state message: "No tienes presupuestos configurados."
2. Verify the "Crear tu primer presupuesto" link is present
   - **Expected:** Link text and teal styling are visible

#### Pass Criteria
- [ ] Empty state message is displayed in Spanish
- [ ] Link to create first budget is present and functional

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-058: Create a new monthly budget
**Priority:** Critical
**Feature:** Budget CRUD
**Preconditions:** User is logged in; active email account exists; categories exist

#### Steps
1. Navigate to `http://localhost:3000/budgets/new`
   - **Expected:** Budget form loads with default values: period "monthly", currency "CRC", start_date today, warning_threshold 70, critical_threshold 90
2. Enter "Presupuesto Alimentacion" in the "Nombre" field
   - **Expected:** Name accepted
3. Select "Mensual" for the period dropdown
   - **Expected:** Period set to monthly
4. Enter "500000" in the "Monto" field
   - **Expected:** Amount accepted
5. Select "CRC" as currency
   - **Expected:** Currency set
6. Select a category (e.g., "Alimentacion")
   - **Expected:** Category selected
7. Verify the start date defaults to today
   - **Expected:** Date field shows today's date
8. Verify warning threshold is 70 and critical threshold is 90
   - **Expected:** Default values are pre-filled
9. Click "Crear Presupuesto"
   - **Expected:** Redirected to dashboard with notice "Presupuesto creado exitosamente."

#### Pass Criteria
- [ ] Budget is created with all specified values
- [ ] Default values are applied correctly
- [ ] `calculate_current_spend!` is called after creation
- [ ] Success message in Spanish is displayed
- [ ] Redirect goes to dashboard

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-059: Create budget with validation errors
**Priority:** High
**Feature:** Budget Validation
**Preconditions:** User is logged in; budget form is accessible

#### Steps
1. Navigate to `http://localhost:3000/budgets/new`
   - **Expected:** Form loads
2. Leave the "Nombre" field empty
   - **Expected:** Field is blank
3. Leave the "Monto" field empty or set to 0
   - **Expected:** Field is blank/zero
4. Click "Crear Presupuesto"
   - **Expected:** Form re-renders with validation errors in a rose-colored error box
5. Observe the error messages
   - **Expected:** Messages indicate required fields (may be in Spanish due to rails-i18n gem)

#### Pass Criteria
- [ ] Form does not submit with invalid data
- [ ] Validation errors are displayed
- [ ] HTTP status is 422
- [ ] Previously entered data is preserved in the form

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-060: Create budget with warning >= critical threshold
**Priority:** High
**Feature:** Budget Validation
**Preconditions:** User is logged in

#### Steps
1. Navigate to `http://localhost:3000/budgets/new`
   - **Expected:** Form loads
2. Fill in required fields (name, amount, period)
   - **Expected:** Fields accepted
3. Set warning_threshold to 95 and critical_threshold to 90
   - **Expected:** Values accepted in fields
4. Click "Crear Presupuesto"
   - **Expected:** Validation error: warning must be less than critical threshold

#### Pass Criteria
- [ ] Budget with warning_threshold >= critical_threshold is rejected
- [ ] Validation error clearly explains the constraint

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-061: View budget details (show page)
**Priority:** High
**Feature:** Budget Details
**Preconditions:** User is logged in; a budget exists

#### Steps
1. Navigate to `http://localhost:3000/budgets/<id>`
   - **Expected:** Budget show page loads
2. Observe the budget statistics
   - **Expected:** Current spend, usage percentage, remaining amount, days remaining in period, daily average needed are all displayed
3. Observe historical adherence
   - **Expected:** Historical data for the last 6 periods is shown

#### Pass Criteria
- [ ] Show page loads without errors
- [ ] All budget statistics are displayed
- [ ] Historical adherence section is present
- [ ] Numbers are formatted correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-062: Edit a budget
**Priority:** High
**Feature:** Budget CRUD
**Preconditions:** User is logged in; a budget exists

#### Steps
1. Navigate to `http://localhost:3000/budgets/<id>/edit`
   - **Expected:** Edit form loads with pre-filled values from the existing budget
2. Change the amount to a new value (e.g., "600000")
   - **Expected:** Amount field accepts the new value
3. Click "Actualizar Presupuesto"
   - **Expected:** Redirected to dashboard with notice "Presupuesto actualizado exitosamente."
4. Navigate to `http://localhost:3000/budgets/<id>`
   - **Expected:** Updated amount is reflected on the show page

#### Pass Criteria
- [ ] Edit form pre-fills existing values
- [ ] Update saves correctly
- [ ] `calculate_current_spend!` is called after update
- [ ] Success message in Spanish is displayed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-063: Delete a budget
**Priority:** High
**Feature:** Budget CRUD
**Preconditions:** User is logged in; a budget exists

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Budget list loads
2. Find a budget and click its delete action
   - **Expected:** Confirmation may be required
3. Confirm deletion
   - **Expected:** Redirected to `http://localhost:3000/budgets` with notice "Presupuesto eliminado exitosamente."
4. Verify the budget is gone
   - **Expected:** Budget no longer appears in the list

#### Pass Criteria
- [ ] Budget is permanently deleted
- [ ] Success message in Spanish is displayed
- [ ] Budget list updates correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-064: Deactivate a budget
**Priority:** High
**Feature:** Budget Management
**Preconditions:** User is logged in; an active budget exists

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Budget list loads
2. Find an active budget and click the "Desactivar" button
   - **Expected:** Budget status changes to inactive
3. Verify the redirect
   - **Expected:** Redirected to budgets list with notice "Presupuesto desactivado exitosamente."
4. Verify the budget now shows as "Inactivo"
   - **Expected:** Status text changes from "Activo" (emerald) to "Inactivo" (slate)

#### Pass Criteria
- [ ] Budget is deactivated (not deleted)
- [ ] Success message in Spanish is displayed
- [ ] Budget status visually changes
- [ ] Deactivated budget no longer contributes to overall budget health

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-065: Duplicate a budget
**Priority:** Medium
**Feature:** Budget Management
**Preconditions:** User is logged in; a budget exists

#### Steps
1. Trigger the duplicate action for an existing budget (POST to `http://localhost:3000/budgets/<id>/duplicate`)
   - **Expected:** A new budget is created for the next period with the same settings
2. Verify the redirect
   - **Expected:** Redirected to the edit page for the new duplicated budget with notice "Presupuesto duplicado exitosamente. Puedes ajustar los valores segun necesites."
3. Observe the pre-filled form
   - **Expected:** The duplicated budget has the same amount, category, thresholds but is set for the next period

#### Pass Criteria
- [ ] New budget record is created
- [ ] Settings are copied from the original
- [ ] User is sent to edit page to adjust values
- [ ] Success message is displayed in Spanish

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-066: Quick set budget from dashboard
**Priority:** Medium
**Feature:** Budget Management
**Preconditions:** User is logged in; active email account exists; expense history exists

#### Steps
1. Navigate to `http://localhost:3000/budgets/quick_set?period=monthly`
   - **Expected:** Quick set form partial is returned
2. Observe the suggested amount
   - **Expected:** Amount is approximately 110% of the average recent spending, rounded to the nearest thousand
3. Verify the pre-filled fields
   - **Expected:** Period is "monthly", currency is "CRC", name is "Presupuesto Mensual" (or similar)

#### Pass Criteria
- [ ] Quick set endpoint returns a form partial
- [ ] Suggested amount is data-driven (based on recent spending)
- [ ] Default values are reasonable

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-067: Budget usage percentage colors
**Priority:** High
**Feature:** Budget Display
**Preconditions:** User is logged in; budgets exist at various usage levels

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Budget list loads
2. Find a budget with < 70% usage
   - **Expected:** Usage percentage is shown in emerald/green color (:good status)
3. Find a budget with 70-89% usage
   - **Expected:** Usage percentage shown in amber color (:warning status)
4. Find a budget with 90-99% usage
   - **Expected:** Usage percentage shown in rose/red color (:critical status)
5. Find a budget with >= 100% usage
   - **Expected:** Usage percentage shown in dark rose color (:exceeded status)

#### Pass Criteria
- [ ] Budget < 70% shows green/emerald styling
- [ ] Budget 70-89% shows amber/warning styling
- [ ] Budget 90-99% shows rose/critical styling
- [ ] Budget >= 100% shows exceeded styling

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-068: Overall budget health indicator
**Priority:** High
**Feature:** Budget Health
**Preconditions:** User is logged in; multiple active budgets exist

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Page loads with overall budget health section
2. Observe the health indicator
   - **Expected:** Shows status (good/warning/critical/exceeded), usage percentage, total budget vs total spend, and a message in Spanish
3. Verify the message matches the status
   - **Expected:** "Vas bien" for good, "Atencion" for warning, "Estas muy cerca del limite" for critical, "Has excedido tu presupuesto" for exceeded

#### Pass Criteria
- [ ] Overall health is calculated correctly from all active budgets
- [ ] Status message is in Spanish
- [ ] Percentage is correct (total spend / total budget * 100)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Categories

### Scenario EFG-069: Categories JSON endpoint
**Priority:** Medium
**Feature:** Categories
**Preconditions:** User is logged in; categories exist in the database

#### Steps
1. Navigate to `http://localhost:3000/categories.json`
   - **Expected:** JSON array of categories is returned
2. Verify the JSON structure
   - **Expected:** Each category has: id, name, color, parent_id
3. Verify the sort order
   - **Expected:** Categories are sorted alphabetically by name

#### Pass Criteria
- [ ] JSON endpoint returns valid data
- [ ] All categories are included
- [ ] Each category has id, name, color, parent_id fields
- [ ] Sorted by name

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-070: Categories HTML endpoint redirects to expenses
**Priority:** Low
**Feature:** Categories
**Preconditions:** User is logged in

#### Steps
1. Navigate to `http://localhost:3000/categories` (HTML format)
   - **Expected:** Redirected to `http://localhost:3000/expenses`

#### Pass Criteria
- [ ] HTML request redirects to expenses path
- [ ] No error page is shown

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-071: Category colors are present in data
**Priority:** Medium
**Feature:** Categories
**Preconditions:** Categories have color values set

#### Steps
1. Navigate to `http://localhost:3000/categories.json`
   - **Expected:** JSON response
2. Verify at least some categories have non-null `color` values
   - **Expected:** Color fields contain color codes or names used for visual badges

#### Pass Criteria
- [ ] Categories include color data
- [ ] Colors are used in the UI for category badges

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API -- Health Checks

### Scenario EFG-072: Health check endpoint returns healthy status
**Priority:** Critical
**Feature:** API Health
**Preconditions:** Application is running; database is connected

#### Steps
1. Run: `curl -s http://localhost:3000/api/health | python3 -m json.tool`
   - **Expected:** JSON response with `status` and `healthy: true`, HTTP status 200
2. Verify the response includes subsystem checks
   - **Expected:** `checks` object with per-subsystem status, response_time_ms fields

#### Pass Criteria
- [ ] Health endpoint returns 200 when all systems are operational
- [ ] Response includes `healthy: true`
- [ ] Subsystem checks are listed
- [ ] No authentication required

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-073: Readiness probe endpoint
**Priority:** High
**Feature:** API Health
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" http://localhost:3000/api/health/ready`
   - **Expected:** HTTP 200 with `{ "status": "ready", "timestamp": "..." }`

#### Pass Criteria
- [ ] Ready endpoint returns 200 when app can serve traffic
- [ ] Response includes `status: "ready"` and `timestamp`
- [ ] No authentication required

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-074: Liveness probe endpoint
**Priority:** High
**Feature:** API Health
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" http://localhost:3000/api/health/live`
   - **Expected:** HTTP 200 with `{ "status": "live", "timestamp": "..." }`

#### Pass Criteria
- [ ] Live endpoint returns 200 when process is alive
- [ ] Response includes `status: "live"` and `timestamp`

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-075: Metrics endpoint
**Priority:** Medium
**Feature:** API Health
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s http://localhost:3000/api/health/metrics | python3 -m json.tool`
   - **Expected:** JSON response with categorization stats, pattern counts, cache stats, DB pool metrics, and memory usage
2. Verify the response structure
   - **Expected:** Top-level keys: timestamp, categorization, patterns, performance, system

#### Pass Criteria
- [ ] Metrics endpoint returns 200
- [ ] Response includes categorization, patterns, performance, and system sections
- [ ] No authentication required

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-076: Rails built-in health check
**Priority:** Medium
**Feature:** Application Health
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" http://localhost:3000/up`
   - **Expected:** HTTP 200 indicating the app booted without exceptions

#### Pass Criteria
- [ ] /up returns 200 when the application is healthy

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API -- Webhooks

### Scenario EFG-077: Webhook without authentication returns 401
**Priority:** Critical
**Feature:** API Webhook Authentication
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" -X POST http://localhost:3000/api/webhooks/add_expense`
   - **Expected:** HTTP 401 with JSON `{ "error": "Missing API token" }`

#### Pass Criteria
- [ ] Request without Authorization header returns 401
- [ ] Error message is "Missing API token"

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-078: Webhook with invalid token returns 401
**Priority:** Critical
**Feature:** API Webhook Authentication
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer invalid_token_123" http://localhost:3000/api/webhooks/add_expense`
   - **Expected:** HTTP 401 with JSON `{ "error": "Invalid or expired API token" }`

#### Pass Criteria
- [ ] Invalid token returns 401
- [ ] Error message is "Invalid or expired API token"

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-079: Add expense via webhook with valid token
**Priority:** Critical
**Feature:** API Webhook
**Preconditions:** Application is running; a valid API token exists in the database

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/add_expense \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"expense": {"amount": 15000, "description": "Compra AutoMercado", "merchant_name": "AutoMercado", "transaction_date": "2026-03-26"}}'
   ```
   - **Expected:** HTTP 201 with JSON containing `status: "success"`, `message: "Expense created successfully"`, and `expense` object
2. Verify the expense object in the response
   - **Expected:** Includes id, amount (15000), description, merchant_name, transaction_date (ISO 8601), status ("processed")

#### Pass Criteria
- [ ] Expense is created with status "processed"
- [ ] Response includes the full expense JSON
- [ ] HTTP status is 201
- [ ] Expense is associated with the first active email account

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-080: Add expense with missing required fields
**Priority:** High
**Feature:** API Webhook Validation
**Preconditions:** Valid API token exists

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/add_expense \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"expense": {}}'
   ```
   - **Expected:** HTTP 422 with JSON containing `status: "error"`, `errors` array with validation messages

#### Pass Criteria
- [ ] Missing fields return 422
- [ ] Error messages describe the missing fields
- [ ] No expense record is created

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-081: Add expense with category_id
**Priority:** High
**Feature:** API Webhook
**Preconditions:** Valid API token; a category exists with a known ID

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/add_expense \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"expense": {"amount": 8000, "description": "Almuerzo", "transaction_date": "2026-03-26", "category_id": <known_id>}}'
   ```
   - **Expected:** HTTP 201; expense is created with the specified category

#### Pass Criteria
- [ ] Expense is created with the correct category assignment
- [ ] Response includes category name

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-082: Process emails webhook
**Priority:** High
**Feature:** API Webhook
**Preconditions:** Valid API token; an active email account exists

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/process_emails \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"email_account_id": <id>}'
   ```
   - **Expected:** HTTP 202 Accepted with `status: "success"` and message indicating job was queued
2. Run without email_account_id:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/process_emails \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 202 with message indicating processing queued for all active accounts

#### Pass Criteria
- [ ] With email_account_id: job queued for specific account
- [ ] Without email_account_id: job queued for all active accounts
- [ ] HTTP status is 202 (Accepted)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-083: Recent expenses webhook
**Priority:** High
**Feature:** API Webhook
**Preconditions:** Valid API token; expenses exist

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/webhooks/recent_expenses \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with JSON containing `status: "success"` and `expenses` array (default 10)
2. Run with custom limit:
   ```
   curl -s "http://localhost:3000/api/webhooks/recent_expenses?limit=25" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Up to 25 expenses returned
3. Verify each expense includes required fields
   - **Expected:** id, amount, formatted_amount, description, merchant_name, transaction_date (ISO 8601), category, bank_name, status, created_at

#### Pass Criteria
- [ ] Default limit is 10
- [ ] Custom limit is respected (capped at 50)
- [ ] All expense fields are present in the response
- [ ] Expenses are ordered by recency

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-084: Expense summary webhook
**Priority:** Medium
**Feature:** API Webhook
**Preconditions:** Valid API token; expenses exist

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/webhooks/expense_summary \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with JSON containing `status: "success"`, `period`, and `summary`
2. Run with period parameter:
   ```
   curl -s "http://localhost:3000/api/webhooks/expense_summary?period=month" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Monthly summary data

#### Pass Criteria
- [ ] Summary endpoint returns valid data
- [ ] Period parameter is respected
- [ ] Response structure includes status, period, summary

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API v1 -- Categories

### Scenario EFG-085: API v1 categories without authentication
**Priority:** Critical
**Feature:** API v1 Authentication
**Preconditions:** Application is running

#### Steps
1. Run: `curl -s -w "\n%{http_code}" http://localhost:3000/api/v1/categories`
   - **Expected:** HTTP 401 with JSON error response

#### Pass Criteria
- [ ] Request without token returns 401
- [ ] Error message indicates missing authentication

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-086: API v1 categories with valid authentication
**Priority:** High
**Feature:** API v1 Categories
**Preconditions:** Valid API token exists; categories exist

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/v1/categories \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with JSON array of categories
2. Verify each category has: id, name, color, description
   - **Expected:** All fields present; sorted by name

#### Pass Criteria
- [ ] Categories are returned as JSON array
- [ ] Each category has id, name, color, description
- [ ] Sorted alphabetically by name
- [ ] Response includes API version header (X-API-Version)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API v1 -- Patterns

### Scenario EFG-087: List patterns via API
**Priority:** High
**Feature:** API v1 Patterns
**Preconditions:** Valid API token; patterns exist

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/v1/patterns \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with `status: "success"`, `patterns` array, and `meta` block with pagination info
2. Verify the meta block
   - **Expected:** Contains current_page, total_pages, total_count, per_page, next_page, prev_page

#### Pass Criteria
- [ ] Patterns are returned with pagination metadata
- [ ] Response includes status: "success"
- [ ] Each pattern includes category information

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-088: Filter patterns by type via API
**Priority:** Medium
**Feature:** API v1 Pattern Filtering
**Preconditions:** Valid API token; patterns of multiple types exist

#### Steps
1. Run:
   ```
   curl -s "http://localhost:3000/api/v1/patterns?pattern_type=merchant" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Only patterns of type "merchant" are returned

#### Pass Criteria
- [ ] Type filter works correctly
- [ ] All returned patterns have the specified type

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-089: Filter patterns by active status via API
**Priority:** Medium
**Feature:** API v1 Pattern Filtering
**Preconditions:** Valid API token; both active and inactive patterns exist

#### Steps
1. Run:
   ```
   curl -s "http://localhost:3000/api/v1/patterns?active=true" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Only active patterns are returned

#### Pass Criteria
- [ ] Active filter returns only active patterns
- [ ] All returned patterns have active=true

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-090: Sort patterns via API
**Priority:** Medium
**Feature:** API v1 Pattern Sorting
**Preconditions:** Valid API token; patterns with varied usage exist

#### Steps
1. Run:
   ```
   curl -s "http://localhost:3000/api/v1/patterns?sort_by=usage_count&sort_direction=desc" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Patterns sorted by usage_count descending
2. Run:
   ```
   curl -s "http://localhost:3000/api/v1/patterns?sort_by=success_rate&sort_direction=asc" \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Patterns sorted by success_rate ascending

#### Pass Criteria
- [ ] Sorting by usage_count works
- [ ] Sorting by success_rate works
- [ ] Sort direction (asc/desc) is respected

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-091: Get single pattern via API
**Priority:** Medium
**Feature:** API v1 Patterns
**Preconditions:** Valid API token; a pattern exists with a known ID

#### Steps
1. Run:
   ```
   curl -s -i http://localhost:3000/api/v1/patterns/<id> \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with detailed pattern JSON including category info
2. Note the ETag header from the response
   - **Expected:** ETag header is present
3. Run again with If-None-Match:
   ```
   curl -s -w "\n%{http_code}" http://localhost:3000/api/v1/patterns/<id> \
     -H "Authorization: Bearer <valid_token>" \
     -H "If-None-Match: <etag_value>"
   ```
   - **Expected:** HTTP 304 Not Modified (if pattern has not changed)

#### Pass Criteria
- [ ] Single pattern returns detailed data with category
- [ ] ETag header is returned
- [ ] Conditional GET with matching ETag returns 304

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-092: Create pattern via API
**Priority:** High
**Feature:** API v1 Patterns
**Preconditions:** Valid API token; a category exists

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/v1/patterns \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"pattern": {"pattern_type": "merchant", "pattern_value": "PriceSmart", "category_id": <id>, "confidence_weight": 1.5, "active": true}}'
   ```
   - **Expected:** HTTP 201 with `status: "success"` and created pattern data
2. Verify the pattern has `user_created: true`
   - **Expected:** Pattern is flagged as user-created

#### Pass Criteria
- [ ] Pattern is created via API
- [ ] user_created is set to true
- [ ] HTTP status is 201
- [ ] Response includes the full pattern data

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-093: Update pattern via API
**Priority:** Medium
**Feature:** API v1 Patterns
**Preconditions:** Valid API token; a pattern exists

#### Steps
1. Run:
   ```
   curl -s -X PATCH http://localhost:3000/api/v1/patterns/<id> \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"pattern": {"pattern_value": "UpdatedValue", "confidence_weight": 2.5}}'
   ```
   - **Expected:** HTTP 200 with updated pattern data

#### Pass Criteria
- [ ] Pattern is updated with new values
- [ ] Response shows the updated data
- [ ] Only allowed fields are updated (pattern_value, confidence_weight, active, metadata)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-094: Delete (soft-deactivate) pattern via API
**Priority:** Medium
**Feature:** API v1 Patterns
**Preconditions:** Valid API token; an active pattern exists

#### Steps
1. Run:
   ```
   curl -s -X DELETE http://localhost:3000/api/v1/patterns/<id> \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with `message: "Pattern deactivated successfully"`
2. Verify the pattern still exists but is inactive
   - **Expected:** Pattern has `active: false`; it is NOT hard-deleted from the database

#### Pass Criteria
- [ ] DELETE soft-deactivates the pattern (sets active to false)
- [ ] Pattern still exists in the database
- [ ] Response confirms deactivation

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-095: Pattern statistics via API
**Priority:** Medium
**Feature:** API v1 Patterns
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/v1/patterns/statistics \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with aggregated pattern statistics

#### Pass Criteria
- [ ] Statistics endpoint returns valid JSON data
- [ ] Includes pattern counts, types, usage data

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-096: API returns 404 for non-existent pattern
**Priority:** Medium
**Feature:** API v1 Error Handling
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s -w "\n%{http_code}" http://localhost:3000/api/v1/patterns/999999 \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 404 with JSON error `{ "error": "Couldn't find CategorizationPattern...", "status": 404 }`

#### Pass Criteria
- [ ] Non-existent pattern returns 404
- [ ] Error message is in structured JSON
- [ ] No server crash

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API v1 -- Categorization

### Scenario EFG-097: Suggest category for an expense
**Priority:** High
**Feature:** API v1 Categorization
**Preconditions:** Valid API token; patterns and categories exist

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/v1/categorization/suggest \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"merchant_name": "AutoMercado", "description": "Compra semanal", "amount": 50000}'
   ```
   - **Expected:** HTTP 200 with `status: "success"` and `suggestions` array containing categories with confidence scores

#### Pass Criteria
- [ ] Suggestions are returned with category and confidence
- [ ] At least one suggestion is provided for a known merchant
- [ ] Response includes the input expense_data echo

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-098: Suggest without required parameters returns error
**Priority:** High
**Feature:** API v1 Categorization Validation
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/v1/categorization/suggest \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{}'
   ```
   - **Expected:** HTTP 400 with error about missing merchant_name or description

#### Pass Criteria
- [ ] Missing required params returns 400
- [ ] Error message explains what is needed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-099: Submit categorization feedback
**Priority:** High
**Feature:** API v1 Categorization Feedback
**Preconditions:** Valid API token; an expense and category exist

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/v1/categorization/feedback \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"feedback": {"expense_id": <id>, "category_id": <id>, "was_correct": true}}'
   ```
   - **Expected:** HTTP 200 with `status: "success"` and feedback confirmation

#### Pass Criteria
- [ ] Feedback is recorded
- [ ] Response includes feedback details and improvement suggestion
- [ ] Pattern learning is triggered for incorrect feedback

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-100: Batch suggest categories
**Priority:** Medium
**Feature:** API v1 Categorization
**Preconditions:** Valid API token; patterns and categories exist

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/v1/categorization/batch_suggest \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"expenses": [{"merchant_name": "AutoMercado", "description": "Compra"}, {"merchant_name": "Shell", "description": "Gasolina"}]}'
   ```
   - **Expected:** HTTP 200 with `results` array containing suggestions for each expense in the same order

#### Pass Criteria
- [ ] Batch results match input order
- [ ] Each result includes category suggestion and confidence
- [ ] Maximum 100 expenses per batch

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-101: Batch suggest with more than 100 expenses
**Priority:** Medium
**Feature:** API v1 Categorization Rate Limit
**Preconditions:** Valid API token

#### Steps
1. Submit a batch request with 101 expense entries
   - **Expected:** HTTP 400 with error "Maximum 100 expenses per batch"

#### Pass Criteria
- [ ] Batch limit of 100 is enforced
- [ ] Clear error message returned

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-102: Categorization statistics
**Priority:** Medium
**Feature:** API v1 Categorization
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/v1/categorization/statistics \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with `statistics` object containing total_patterns, active_patterns, patterns_by_type, average_success_rate, top_categories, etc.

#### Pass Criteria
- [ ] Statistics endpoint returns comprehensive data
- [ ] All expected fields are present

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## API -- Queue & Monitoring

### Scenario EFG-103: Queue status endpoint
**Priority:** Medium
**Feature:** API Queue Management
**Preconditions:** Valid API token; Solid Queue is running

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/queue/status \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with queue depth, active jobs count, failed jobs count

#### Pass Criteria
- [ ] Queue status returns current state
- [ ] Response includes queue depth and job counts

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-104: Queue metrics endpoint
**Priority:** Medium
**Feature:** API Queue Management
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/queue/metrics \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with processing rate, throughput, per-queue statistics

#### Pass Criteria
- [ ] Metrics endpoint returns valid data
- [ ] Processing rate and throughput values are present

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-105: Queue health endpoint
**Priority:** Medium
**Feature:** API Queue Management
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/queue/health \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with queue health status

#### Pass Criteria
- [ ] Health endpoint returns queue system status
- [ ] Healthy/unhealthy status is clearly indicated

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-106: Monitoring metrics endpoint
**Priority:** Medium
**Feature:** API Monitoring
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/monitoring/metrics \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with application-level performance metrics

#### Pass Criteria
- [ ] Monitoring metrics return valid data
- [ ] Response includes performance metrics

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-107: Monitoring strategy endpoint
**Priority:** Low
**Feature:** API Monitoring
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s http://localhost:3000/api/monitoring/strategy \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 200 with monitoring configuration and strategy details

#### Pass Criteria
- [ ] Strategy endpoint returns configuration data

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Error Handling & Edge Cases

### Scenario EFG-108: Non-existent URL returns 404
**Priority:** Critical
**Feature:** Error Handling
**Preconditions:** Application is running

#### Steps
1. Navigate to `http://localhost:3000/this-page-does-not-exist`
   - **Expected:** 404 error page is displayed (not a 500 error)
2. Observe the page content
   - **Expected:** A user-friendly error page indicating the page was not found

#### Pass Criteria
- [ ] Non-existent routes return 404, not 500
- [ ] Error page is user-friendly
- [ ] No server stack trace is exposed

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-109: Non-existent expense ID redirects gracefully
**Priority:** High
**Feature:** Error Handling
**Preconditions:** User is logged in

#### Steps
1. Navigate to `http://localhost:3000/expenses/999999`
   - **Expected:** Redirected to expense list with a "not found" flash message

#### Pass Criteria
- [ ] Non-existent expense ID does not cause a 500 error
- [ ] User is redirected with a helpful message

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-110: API unexpected error returns structured JSON
**Priority:** High
**Feature:** API Error Handling
**Preconditions:** Valid API token

#### Steps
1. Send a request that could trigger an unexpected error (e.g., malformed JSON body):
   ```
   curl -s -X POST http://localhost:3000/api/v1/patterns \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d 'not-valid-json'
   ```
   - **Expected:** HTTP 400 or 500 with structured JSON error response including `error`, `status`, and `request_id`

#### Pass Criteria
- [ ] Error response is structured JSON, not raw HTML
- [ ] Response includes request_id for debugging
- [ ] Status code is appropriate (400 for bad request, 500 for server error)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-111: Flash messages are in Spanish
**Priority:** High
**Feature:** Internationalization
**Preconditions:** User is logged in

#### Steps
1. Create a budget successfully
   - **Expected:** Flash message "Presupuesto creado exitosamente."
2. Delete a budget
   - **Expected:** Flash message "Presupuesto eliminado exitosamente."
3. Try to access budgets without an email account
   - **Expected:** Flash message "Debes configurar una cuenta de correo primero."

#### Pass Criteria
- [ ] All budget-related flash messages are in Spanish
- [ ] No English-only messages appear in the main user interface
- [ ] Validation error messages are also in Spanish

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-112: Admin session expiration redirects to login with return URL
**Priority:** High
**Feature:** Admin Session Management
**Preconditions:** Admin was previously logged in but session has expired

#### Steps
1. Log in to admin panel
   - **Expected:** Access to admin pages
2. Wait for session to expire (or manually clear the session cookie)
   - **Expected:** Session is invalidated
3. Try to access `http://localhost:3000/admin/patterns/statistics`
   - **Expected:** Redirected to `http://localhost:3000/admin/login`
4. Log in again
   - **Expected:** After login, redirected back to the originally requested URL (`/admin/patterns/statistics`)

#### Pass Criteria
- [ ] Expired session redirects to login
- [ ] Return-to URL is stored in the session
- [ ] After re-login, user is redirected to the original target page

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-113: CSRF token handling on admin forms
**Priority:** High
**Feature:** Security
**Preconditions:** Admin is logged in

#### Steps
1. Navigate to `http://localhost:3000/admin/patterns/new`
   - **Expected:** Form loads with a hidden CSRF token field
2. Inspect the form HTML (browser dev tools)
   - **Expected:** A hidden field named `authenticity_token` is present
3. Submit the form normally
   - **Expected:** Form submits successfully (CSRF token is valid)

#### Pass Criteria
- [ ] CSRF token is included in all admin forms
- [ ] Form submission with valid token succeeds
- [ ] Form without valid CSRF token would be rejected

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-114: Client error reporting endpoint
**Priority:** Medium
**Feature:** Error Reporting
**Preconditions:** Application is running

#### Steps
1. Run:
   ```
   curl -s -X POST http://localhost:3000/api/client_errors \
     -H "Content-Type: application/json" \
     -d '{"error": {"message": "Test client error", "stack": "at test.js:1", "url": "/dashboard"}}'
   ```
   - **Expected:** HTTP 200 or 201 confirming the error was logged

#### Pass Criteria
- [ ] Client error is accepted and logged server-side
- [ ] No authentication required for error reporting (or appropriate auth)

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-115: Bulk operation with empty expense_ids
**Priority:** Medium
**Feature:** Error Handling
**Preconditions:** User is logged in

#### Steps
1. Send a POST to `http://localhost:3000/expenses/bulk_destroy` with empty `expense_ids` parameter
   - **Expected:** Clear error message indicating no expenses were selected
2. Verify no expenses are deleted
   - **Expected:** Database unchanged

#### Pass Criteria
- [ ] Empty expense_ids does not cause a server error
- [ ] Error message clearly explains the issue

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Data Integrity & Business Rules

### Scenario EFG-116: Expense amounts must be positive
**Priority:** Critical
**Feature:** Data Integrity
**Preconditions:** User is logged in or valid API token

#### Steps
1. Try to create an expense with amount 0 via API:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/add_expense \
     -H "Authorization: Bearer <valid_token>" \
     -H "Content-Type: application/json" \
     -d '{"expense": {"amount": 0, "description": "Test", "transaction_date": "2026-03-26"}}'
   ```
   - **Expected:** HTTP 422 with validation error about amount
2. Try with a negative amount (-5000):
   - **Expected:** HTTP 422 with validation error

#### Pass Criteria
- [ ] Zero amount is rejected
- [ ] Negative amount is rejected
- [ ] Validation error message is clear

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-117: Budget unique active constraint
**Priority:** High
**Feature:** Data Integrity
**Preconditions:** User is logged in; an active monthly budget for a specific category already exists

#### Steps
1. Navigate to `http://localhost:3000/budgets/new`
   - **Expected:** Form loads
2. Fill in the form with the same period and category_id as the existing active budget
   - **Expected:** Fields accepted
3. Click "Crear Presupuesto"
   - **Expected:** Validation error: "ya existe un presupuesto activo" (or similar uniqueness violation)

#### Pass Criteria
- [ ] Duplicate active budget for same period + category is rejected
- [ ] Validation error is displayed in Spanish
- [ ] Existing budget is unaffected

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-118: Budget threshold order validation
**Priority:** High
**Feature:** Data Integrity
**Preconditions:** User is logged in

#### Steps
1. Navigate to `http://localhost:3000/budgets/new`
   - **Expected:** Form loads
2. Set warning_threshold to 95 and critical_threshold to 90
   - **Expected:** Fields accept the values
3. Click submit
   - **Expected:** Validation error indicating warning must be less than critical

#### Pass Criteria
- [ ] Warning >= critical is rejected
- [ ] Error message explains the constraint

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-119: Currency formatting for CRC, USD, EUR
**Priority:** Medium
**Feature:** Data Integrity
**Preconditions:** Expenses or budgets exist with different currencies

#### Steps
1. Navigate to `http://localhost:3000/budgets`
   - **Expected:** Budget amounts show correct currency symbols
2. Verify CRC amounts show the colon symbol
   - **Expected:** Amounts formatted with the appropriate currency symbol
3. If USD or EUR budgets exist, verify their formatting
   - **Expected:** USD shows $, EUR shows euro sign

#### Pass Criteria
- [ ] CRC amounts are formatted correctly
- [ ] USD amounts use $ symbol
- [ ] EUR amounts use euro symbol

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-120: Category assignments persist after page reload
**Priority:** High
**Feature:** Data Integrity
**Preconditions:** User is logged in; expenses with category assignments exist

#### Steps
1. Navigate to the dashboard or expense list
   - **Expected:** Expenses show their assigned categories
2. Note the category assignments for several expenses
   - **Expected:** Categories are displayed
3. Refresh the page (F5 / Cmd+R)
   - **Expected:** Same category assignments are displayed
4. Navigate away and come back
   - **Expected:** Category assignments are unchanged

#### Pass Criteria
- [ ] Category assignments persist across page reloads
- [ ] No data loss on navigation

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-121: AdminUser passwords are never stored in plaintext
**Priority:** Critical
**Feature:** Security / Data Integrity
**Preconditions:** Admin user exists in the database

#### Steps
1. Open Rails console: `bin/rails console`
   - **Expected:** Console starts
2. Run: `AdminUser.first.attributes`
   - **Expected:** The `password_digest` field contains a bcrypt hash (starts with `$2a$`)
3. Verify no `password` attribute is stored
   - **Expected:** Only `password_digest` exists; no plaintext password field

#### Pass Criteria
- [ ] Passwords stored as bcrypt hashes
- [ ] No plaintext password field in the database
- [ ] `has_secure_password` is in use

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-122: Pattern feedback correctly updates metrics
**Priority:** High
**Feature:** Data Integrity
**Preconditions:** A pattern exists with known usage and success counts

#### Steps
1. Record the current usage_count and success_count for a pattern
   - **Expected:** Values noted
2. Submit positive feedback (was_correct: true) via API for an expense using that pattern
   - **Expected:** Feedback is recorded
3. Check the pattern's metrics again
   - **Expected:** success_count and potentially success_rate have been updated
4. Submit negative feedback (was_correct: false) for another use
   - **Expected:** Feedback is recorded; metrics adjust accordingly

#### Pass Criteria
- [ ] Positive feedback increments success metrics
- [ ] Negative feedback does not increment success count
- [ ] Success rate recalculates correctly

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Background Jobs (Sidekiq)

### Scenario EFG-123: Sidekiq Web UI accessible in development
**Priority:** Medium
**Feature:** Background Jobs
**Preconditions:** Application running in development mode

#### Steps
1. Navigate to `http://localhost:3000/sidekiq`
   - **Expected:** Sidekiq Web UI loads without authentication (development mode)
2. Observe the dashboard
   - **Expected:** Shows queue information, processed/failed job counts, active processes

#### Pass Criteria
- [ ] Sidekiq Web UI is accessible without authentication in development
- [ ] Dashboard shows queue status

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-124: Process emails job is enqueued via webhook
**Priority:** High
**Feature:** Background Jobs
**Preconditions:** Valid API token; Sidekiq or Solid Queue is running

#### Steps
1. Open the Sidekiq Web UI at `http://localhost:3000/sidekiq`
   - **Expected:** Note the current queue state
2. Send a webhook request:
   ```
   curl -s -X POST http://localhost:3000/api/webhooks/process_emails \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** HTTP 202
3. Check the Sidekiq Web UI or queue status
   - **Expected:** `ProcessEmailsJob` appears in the queue or has been processed

#### Pass Criteria
- [ ] Webhook triggers job enqueuing
- [ ] Job appears in the Sidekiq/Solid Queue
- [ ] Job processes without fatal errors

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

### Scenario EFG-125: API response headers include version and request ID
**Priority:** Medium
**Feature:** API Infrastructure
**Preconditions:** Valid API token

#### Steps
1. Run:
   ```
   curl -s -i http://localhost:3000/api/v1/categories \
     -H "Authorization: Bearer <valid_token>"
   ```
   - **Expected:** Response headers include `X-API-Version` and `X-Request-ID`
2. Note the X-API-Version value
   - **Expected:** Contains the current API version string
3. Note the X-Request-ID value
   - **Expected:** Contains a unique request identifier

#### Pass Criteria
- [ ] X-API-Version header is present
- [ ] X-Request-ID header is present with a unique value
- [ ] Both headers appear on all API v1 responses

#### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Appendix: Test Data Requirements

Before running this playbook, ensure the following test data exists:

1. **Admin User:** `admin@expense-tracker.com` with password `AdminPassword123!` and full permissions (including analytics/statistics access)
2. **API Token:** At least one valid API token in the `api_tokens` table
3. **Categories:** Multiple categories with names, colors, and parent-child relationships
4. **Categorization Patterns:** At least 25+ patterns across multiple types (merchant, keyword, regex) with varied usage/success data
5. **Composite Patterns:** At least 2-3 composite patterns with component patterns
6. **Email Account:** At least one active email account
7. **Expenses:** Multiple expenses with various amounts, categories, dates, and statuses
8. **Budgets:** Budgets at various usage levels (< 70%, 70-89%, 90-99%, > 100%)
9. **Pattern Feedback:** Some feedback records for testing metrics and analytics

---

## Scenario Count Summary

| Section | Scenarios |
|---|---|
| Admin Authentication | 4 |
| Patterns List & Navigation | 2 |
| Pattern Filtering & Search | 5 |
| Pattern Sorting | 1 |
| Pattern CRUD | 7 |
| Pattern Toggle | 2 |
| Pattern Import/Export | 6 |
| Pattern Testing | 5 |
| Pattern Details & Performance | 2 |
| Pattern Statistics & Performance | 3 |
| Composite Patterns | 6 |
| Analytics Dashboard | 11 |
| Budget Management | 14 |
| Categories | 3 |
| API Health Checks | 5 |
| API Webhooks | 8 |
| API v1 Categories | 2 |
| API v1 Patterns | 10 |
| API v1 Categorization | 6 |
| API Queue & Monitoring | 5 |
| Error Handling | 8 |
| Data Integrity | 7 |
| Background Jobs | 3 |
| **Total** | **125** |
