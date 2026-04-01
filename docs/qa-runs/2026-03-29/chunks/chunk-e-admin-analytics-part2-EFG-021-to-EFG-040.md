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
