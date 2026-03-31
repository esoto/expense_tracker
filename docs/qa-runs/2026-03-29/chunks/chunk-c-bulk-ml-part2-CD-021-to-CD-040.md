# QA Testing Playbook -- Group C+D: Bulk Operations, ML Categorization, Bulk Categorization, Undo History, Email Accounts, Sync Sessions, Sync Conflicts

**Application:** Expense Tracker (Rails 8.1.2)
**URL:** `http://localhost:3000`
**Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**UI Language:** Spanish
**Date:** 2026-03-26
**QA Execution Date:** 2026-03-27
**QA Executor:** QA Agent (Playwright automated)

---

## Executive Results Summary

**Run Date:** 2026-03-27
**Tester:** QA Agent via Playwright browser automation
**Environment:** localhost:3000 (Rails 8.1.2 development server)
**Total Scenarios:** 118 (CD-001 to CD-118)

### Overall Results

| Section | Scenarios | Pass | Fail | Blocked |
|---------|-----------|------|------|---------|
| Batch Selection (CD-001 to CD-024) | 24 | 7 | 8 | 9 |
| ML Categorization (CD-025 to CD-042) | 18 | 4 | 0 | 14 |
| Bulk Categorization (CD-043 to CD-060) | 18 | 0 | 0 | 18 |
| Email Accounts (CD-061 to CD-074) | 14 | 0 | 0 | 14 |
| Sync Sessions (CD-075 to CD-094) | 20 | 0 | 0 | 20 |
| Sync Conflicts (CD-095 to CD-110) | 16 | 0 | 0 | 16 |
| Undo History (CD-111 to CD-118) | 8 | 0 | 0 | 8 |
| **TOTAL** | **118** | **11** | **8** | **99** |

### Critical Bugs Found

**BUG-001 [CRITICAL]: Keyboard shortcut for selection mode is wrong (CD-001)**
- Playbook states `Ctrl+Shift+A` but actual shortcut is `Ctrl+Shift+S`
- Action in controller: `toggleSelectionMode` mapped to `Ctrl+Shift+S`

**BUG-002 [HIGH]: Bulk Categorize fails with 406 Not Acceptable (CD-011, CD-012)**
- Clicking "Categorizar" bulk button triggers fetch to `/categories.json`
- Server returns 302 redirect to `/admin/login`, then admin login returns 406
- The `/categories.json` endpoint does not serve JSON for non-admin context
- Modal never opens; ARIA error "Error al cargar categorías" is announced
- **Actual network trace:** `GET /categories.json → 302 → GET /admin/login → 406 Not Acceptable`

**BUG-003 [HIGH]: Bulk action buttons not disabled when 0 items selected (CD-018)**
- Categorizar, Estado, and Eliminar buttons remain enabled when 0 expenses selected
- Clicking Categorizar with 0 selected will attempt the (already broken) fetch
- Expected: buttons should have `disabled` attribute and `opacity-50 cursor-not-allowed` styling

**BUG-004 [MEDIUM]: Selection counter text format incorrect (CD-005)**
- Counter only shows the number (e.g., "3") not the full format "3 de 15 gastos seleccionados"
- The `selectedCount` target element just contains the bare digit

**BUG-005 [MEDIUM]: Bulk modal cannot be closed (CD-015, CD-016)**
- Status update modal ("Actualizar Estado") opens correctly via the "Estado" button
- Clicking X button (`.bulk-modal-close`) does NOT close the modal
- Clicking "Cancelar" button (action: `closeBulkModal`) does NOT close the modal
- Clicking "Cancelar" triggered navigation to `/admin/login`, destroying session
- **Root cause:** `closeBulkModal` Stimulus action may be navigating instead of hiding the modal

**BUG-006 [MEDIUM]: `aria-selected` attribute never set on selected rows (CD-004, CD-024)**
- When rows are selected via checkbox, `aria-selected` on the `<tr>` element stays `"false"`
- This breaks screen reader accessibility — rows are not announced as selected
- ARIA live region announcements DO work (status element announces counts correctly)

**BUG-007 [MEDIUM]: Selection mode CSS class persists after exiting (CD-008)**
- After clicking X (disableSelectionMode), the toolbar hides (display: none)
- BUT `.selection-mode-active` CSS class remains on the container element
- Checkboxes remain visible (`display: table-cell`) instead of being hidden
- ARIA announces "Modo de selección desactivado" but DOM state is inconsistent

**BUG-008 [LOW]: Toolbar visibility when 0 items selected (CD-003, CD-006)**
- When 0 items are selected in selection mode, the toolbar remains visible (display: block)
- Expected: toolbar should hide when no items are selected
- Toolbar shows "0 seleccionados" but remains fully rendered

### Blocked Section Note

Sections CD-043 through CD-118 were BLOCKED due to repeated rate limiting (HTTP 429) on the admin login endpoint during session recovery. Rack::Attack's in-memory throttle cannot be cleared from an external Rails runner process (MemoryStore is process-local to Puma). Login attempts accumulated across multiple Playwright evaluate calls that caused page navigations to `/admin/login`.

**Recommendation:** The `/bulk_categorizations`, email accounts, sync sessions, sync conflicts, and undo history sections should be executed in a fresh browser session without prior login failures. Alternatively, temporarily disable Rack::Attack throttle in development or use a test environment cookie.

### Screenshots
- `/Users/esoto/development/expense_tracker/docs/qa-runs/2026-03-27/screenshots/cd-010-bulk-toolbar-state.png` — Toolbar with 3 items selected showing all 3 bulk buttons enabled
- `/Users/esoto/development/expense_tracker/docs/qa-runs/2026-03-27/screenshots/cd-018-zero-selected-buttons-not-disabled.png` — **BUG-003:** Buttons not disabled at 0 selections
- `/Users/esoto/development/expense_tracker/docs/qa-runs/2026-03-27/screenshots/cd-013-bulk-status-modal.png` — Status update modal visible
- `/Users/esoto/development/expense_tracker/docs/qa-runs/2026-03-27/screenshots/cd-013-bulk-status-modal-content.png` — Full page view showing modal content

---

## Table of Contents

1. [Batch Selection & Bulk Operations (CD-001 to CD-024)](#batch-selection--bulk-operations)
2. [ML Categorization Inline Actions (CD-025 to CD-042)](#ml-categorization-inline-actions)
3. [Bulk Categorization Workflow (CD-043 to CD-060)](#bulk-categorization-workflow)
4. [Email Accounts (CD-061 to CD-074)](#email-accounts)
5. [Sync Sessions (CD-075 to CD-094)](#sync-sessions)
6. [Sync Conflicts (CD-095 to CD-110)](#sync-conflicts)
7. [Undo History (CD-111 to CD-118)](#undo-history)

---

## Batch Selection & Bulk Operations

---

## Scenario CD-021: Keyboard Shortcuts Do Not Fire in Form Fields
**Priority:** Medium
**Feature:** Batch Selection
**Preconditions:** User is logged in; dashboard visible

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Click into a search input field (if present) or any text input
   - **Expected:** Input field is focused
3. Press `Ctrl+A` while focused in the input
   - **Expected:** The text inside the input is selected (browser default); batch selection does NOT activate
4. Press `Escape` while focused in the input
   - **Expected:** Nothing related to batch selection happens

### Pass Criteria
- [ ] Keyboard shortcuts are suppressed when typing in form fields
- [ ] Browser default text selection behavior is preserved in inputs

### Results
**BLOCKED** — No text input fields are visible in the compact dashboard view. The filter chips (category/status/period) are buttons, not text inputs. A search/filter text input was not found in the current dashboard layout. This scenario requires a text search field to test — not applicable to the current UI state.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-022: Selection Cleared After Successful Bulk Operation
**Priority:** High
**Feature:** Bulk Operations
**Preconditions:** User is logged in; bulk operation (categorize, status update, or delete) just completed successfully

### Steps
1. After a successful bulk operation completes (e.g., bulk categorize)
   - **Expected:** A `bulk-operations:completed` event fires with `{ success: true }`
2. Observe the checkboxes
   - **Expected:** All checkboxes are unchecked
3. Observe the toolbar
   - **Expected:** Toolbar is hidden
4. Observe the selection mode
   - **Expected:** Selection mode is exited (checkbox columns hidden)

### Pass Criteria
- [ ] All selections cleared after success
- [ ] Toolbar hides
- [ ] Selection mode is deactivated

### Results
**BLOCKED** — No bulk operation was successfully executed due to BUG-002 (categorize) and BUG-005 (modal close failure). Cannot verify post-operation state cleanup.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-023: Bulk Categorize Shows Error for No Category Selected
**Priority:** High
**Feature:** Bulk Operations
**Preconditions:** Expenses selected; modal open; "Categorizar" radio selected but no category chosen

### Steps
1. In the bulk operations modal, select "Categorizar" radio button
   - **Expected:** Category dropdown appears
2. Leave the category dropdown on the default "-- Selecciona una categoria --" option (value="")
   - **Expected:** "Ejecutar" button remains disabled
3. Click "Ejecutar" (it should still be disabled)
   - **Expected:** Nothing happens; form is not submitted

### Pass Criteria
- [ ] Submit button stays disabled when no category is selected
- [ ] No request is sent to the server

### Results
**BLOCKED** — The bulk categorize modal never opens (BUG-002), so cannot verify submit button disabled state within the modal.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-024: Accessibility -- Screen Reader Announcements
**Priority:** Medium
**Feature:** Batch Selection
**Preconditions:** User is logged in; dashboard visible

### Steps
1. Select all expenses via Ctrl+A
   - **Expected:** A `div` with `role="status"` and `aria-live="polite"` is temporarily added to the DOM body with text "N gastos seleccionados"
2. Clear selection via Escape
   - **Expected:** A `div` with `role="status"` and `aria-live="polite"` is temporarily added with text "Seleccion limpiada"
3. Wait approximately 1 second
   - **Expected:** The announcement elements are removed from the DOM

### Pass Criteria
- [ ] Screen reader announcements are generated for select all
- [ ] Screen reader announcements are generated for clear selection
- [ ] Announcement elements are cleaned up after ~1 second
- [ ] Selected rows have `aria-selected="true"` attribute

### Results
**PARTIAL PASS / PARTIAL FAIL** — ARIA live region announcements (via console logs showing `ARIA announcement:`) DO fire correctly for: selection mode on/off, individual selections ("1 elemento seleccionado", "2 elementos seleccionados"), select all. A `<status>` element at the bottom of the expense list region was confirmed in the accessibility snapshot ("3 elementos seleccionados"). However `aria-selected` on `<tr>` rows remains "false" when selected — see **BUG-006**. Cleanup of announcement elements was not separately verified.
- [x] ARIA announcements generated for select all
- [x] ARIA announcements generated for deselection
- [ ] Announcement elements cleaned up — **NOT VERIFIED**
- [ ] Selected rows have `aria-selected="true"` — **FAIL**: All rows stay `aria-selected="false"` regardless of selection state. See BUG-006.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## ML Categorization Inline Actions

---

## Scenario CD-025: Category Badge Displayed on Each Expense
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** User is logged in; expenses exist with assigned categories

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads with expense list
2. Observe any expense that has a category assigned
   - **Expected:** A category badge/label is visible showing the category name

### Pass Criteria
- [ ] Categorized expenses display a category badge
- [ ] Badge text matches the assigned category name

### Results
**PASS** — All 15 visible expenses on the dashboard show category badges. Categorized examples: "Supermercado" (badge with colored circle "S"), "Entretenimiento" (badge "E"), "Alimentación" (badge "A"), "Servicios" (badge "S"). Uncategorized expenses show a grey "?" circle badge with text "Sin categoría". The badge shows the category's first letter in a colored circle plus the category name text.
- [x] Categorized expenses display a category badge
- [x] Badge text matches the assigned category name

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-026: ML Confidence Indicator -- High Confidence
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** At least one expense has `ml_confidence >= 0.85`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense with high ML confidence (>= 0.85)
   - **Expected:** The expense shows a confidence indicator with "high confidence" styling (emerald/green color scheme)

### Pass Criteria
- [ ] High confidence expenses show emerald/green confidence indicator
- [ ] Indicator reflects the ML confidence score

### Results
**PASS** — Two expenses show high-confidence ML badges on the dashboard:
1. "AUTO MERCADO CARTAGO F" row: `button "Confianza: 94%"` with img icon and "94%" text (confidence = 0.94 ≥ 0.85)
2. "CARNICERIA LA GUADALUP" row: `button "Confianza: 91%"` with img icon and "91%" text (confidence = 0.91 ≥ 0.85)
Both show with a green checkmark icon in the badge. The button is interactive (clickable), suggesting it provides additional ML action options.
- [x] High confidence expenses show emerald/green confidence indicator
- [x] Indicator reflects the ML confidence score

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-027: ML Confidence Indicator -- Medium Confidence
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** At least one expense has `ml_confidence >= 0.70` and `< 0.85`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense with medium ML confidence
   - **Expected:** The expense shows a confidence indicator with "medium" styling (amber/yellow color scheme)

### Pass Criteria
- [ ] Medium confidence expenses show amber/yellow confidence indicator

### Results
**BLOCKED** — The 15 visible expenses on the dashboard only show two ML confidence badges (94% and 91%, both high confidence). No medium-confidence expenses (70-85%) were visible in the default dashboard view. Testing requires navigating to a filtered view or finding expenses with medium ML confidence in the database.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-028: ML Confidence Indicator -- Low Confidence
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** At least one expense has `ml_confidence >= 0.50` and `< 0.70`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense with low ML confidence
   - **Expected:** The expense shows a confidence indicator with "low" styling (rose/red or muted color scheme)

### Pass Criteria
- [ ] Low confidence expenses show appropriate low-confidence styling

### Results
**BLOCKED** — No low-confidence (50-70%) ML expenses visible in the default dashboard view. Same constraint as CD-027.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-029: ML Confidence Indicator -- Very Low Confidence
**Priority:** Medium
**Feature:** ML Categorization
**Preconditions:** At least one expense has `ml_confidence < 0.50`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense with very low ML confidence (< 0.50)
   - **Expected:** The expense shows a "very low" confidence indicator with distinct styling

### Pass Criteria
- [ ] Very low confidence expenses show distinct visual indicator

### Results
**BLOCKED** — No very low confidence (<50%) ML expenses visible in the default dashboard view.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-030: Accept ML Suggested Category
**Priority:** Critical
**Feature:** ML Categorization
**Preconditions:** At least one expense has an `ml_suggested_category_id` set (ML has a suggestion)

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense that has an ML-suggested category (should show "Accept" and "Reject" action buttons)
   - **Expected:** Expense row shows "Accept" / "Reject" buttons or equivalent inline action icons
3. Click the "Accept" button on that expense
   - **Expected:** The expense's category updates to the ML-suggested category via Turbo Stream (no full page reload)
4. Observe the category badge
   - **Expected:** The category badge now shows the accepted category name; confidence shows as high (1.0)

### Pass Criteria
- [ ] Accepting updates the category inline via Turbo Stream
- [ ] Category badge shows the ML-suggested category name
- [ ] No full page reload occurs
- [ ] Expense's `ml_correction_count` is incremented

### Results
**BLOCKED** — The two expenses with confidence badges (AUTO MERCADO CARTAGO F at 94%, CARNICERIA LA GUADALUP at 91%) do not show explicit "Accept"/"Reject" buttons in the accessibility snapshot. The confidence badge is a `button` element — clicking it may open accept/reject options. Testing the accept action requires: a live session (blocked by rate limiting), and identifying an expense with `ml_suggested_category_id` set. This requires further investigation in a fresh session.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-031: Accept Suggestion When No Suggestion Exists
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** An expense has NO `ml_suggested_category_id` (null)

### Steps
1. Attempt to send `POST /expenses/:id/accept_suggestion` for an expense without an ML suggestion (may require browser console or direct URL)
   - **Expected:** The response contains an error message "no suggestion available" or Spanish equivalent
2. Observe the expense
   - **Expected:** No changes to the expense's category

### Pass Criteria
- [ ] Error message returned when accepting a non-existent suggestion
- [ ] Expense data unchanged

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute API calls.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-032: Reject ML Suggested Category
**Priority:** Critical
**Feature:** ML Categorization
**Preconditions:** At least one expense has an `ml_suggested_category_id`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense with an ML suggestion showing "Reject" action
   - **Expected:** "Reject" button is visible
3. Click the "Reject" button
   - **Expected:** The `ml_suggested_category_id` is cleared; the category badge partial is replaced via Turbo Stream
4. Observe the expense
   - **Expected:** The expense retains its existing category (or shows as uncategorized if it had none); the ML suggestion is no longer shown

### Pass Criteria
- [ ] Rejecting clears the ML suggested category
- [ ] Turbo Stream replaces the category partial inline
- [ ] No full page reload

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-033: Correct Category with Valid Category
**Priority:** Critical
**Feature:** ML Categorization
**Preconditions:** An expense exists (preferably with an ML suggestion to correct)

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense and open its inline category correction action (dropdown or button that allows selecting a different category)
   - **Expected:** A category selection interface appears (dropdown or modal)
3. Select a new category from the dropdown
   - **Expected:** A POST request is sent to `/expenses/:id/correct_category` with the chosen `category_id`
4. Observe the response
   - **Expected:** The expense's category updates inline via Turbo Stream; a success message appears
5. Observe the category badge
   - **Expected:** Badge shows the newly corrected category

### Pass Criteria
- [ ] Category correction updates the expense via Turbo Stream
- [ ] New category badge is displayed
- [ ] `ml_last_corrected_at` timestamp is updated
- [ ] A `PatternLearningEvent` is created for the correction

### Results
**BLOCKED** — The inline "Cambiar categoría" button exists (confirmed in accessibility snapshot for selected rows). Testing the category dropdown open/select flow and subsequent Turbo Stream update requires a stable session. Session was blocked by rate limiting.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-034: Correct Category with Invalid Category ID
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** An expense exists

### Steps
1. Send a POST request to `/expenses/:id/correct_category` with `category_id=999999` (non-existent)
   - **Expected:** Response returns an error: "Invalid category ID" or equivalent
2. Observe the expense
   - **Expected:** No changes to the expense's category

### Pass Criteria
- [ ] Error returned for non-existent category ID
- [ ] Expense data remains unchanged

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute API calls.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-035: Correct Category with Blank Category ID
**Priority:** High
**Feature:** ML Categorization
**Preconditions:** An expense exists

### Steps
1. Send a POST request to `/expenses/:id/correct_category` without a `category_id` parameter (or blank)
   - **Expected:** The controller validates and returns an error response

### Pass Criteria
- [ ] Error returned for blank/missing category ID
- [ ] Expense data remains unchanged

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute API calls.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-036: Status Toggle -- Pending to Processed
**Priority:** High
**Feature:** Inline Actions
**Preconditions:** An expense exists with `status: pending`

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads with expenses
2. Locate a pending expense; find the status toggle or status update action
   - **Expected:** A button or dropdown to change the status is visible
3. Change the status to "processed"
   - **Expected:** A PATCH request is sent to `/expenses/:id/update_status` with `status=processed`
4. Observe the expense
   - **Expected:** Status badge updates to show "Procesado" styling via Turbo Stream

### Pass Criteria
- [ ] Status changes from pending to processed
- [ ] Turbo Stream updates the status badge inline
- [ ] No full page reload

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute. Note: The inline "Marcar como revisado" button IS visible in the accessibility snapshot for each expense row. The action should work once a session is re-established.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-037: Status Toggle -- Invalid Status
**Priority:** Medium
**Feature:** Inline Actions
**Preconditions:** An expense exists

### Steps
1. Send a PATCH request to `/expenses/:id/update_status` with `status=invalid_value`
   - **Expected:** Response returns error "Invalid status" or equivalent
2. Observe the expense
   - **Expected:** Status is unchanged

### Pass Criteria
- [ ] Invalid status values are rejected
- [ ] Error message returned

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot execute API calls.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-038: Duplicate Expense
**Priority:** High
**Feature:** Inline Actions
**Preconditions:** An expense exists

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense and click the "Duplicate" action button
   - **Expected:** A POST request is sent to `/expenses/:id/duplicate`
3. Observe the response
   - **Expected:** A new expense is created with the same description, amount, category, but with today's date, status=pending, and cleared ML fields
4. Observe the expense list
   - **Expected:** The duplicated expense appears in the list

### Pass Criteria
- [ ] New expense is created with same core data
- [ ] Duplicate has `transaction_date` set to today
- [ ] Duplicate has `status: pending`
- [ ] Duplicate has `ml_confidence: nil` and `ml_suggested_category_id: nil`
- [ ] Duplicate has `ml_correction_count: 0`

### Results
**BLOCKED** — Session lost due to rate limiting. The "Duplicar gasto" button IS visible in the accessibility snapshot for each expense row (action: `duplicateExpense`). Cannot execute without a live session.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-039: Delete Expense with Confirmation
**Priority:** High
**Feature:** Inline Actions
**Preconditions:** An expense exists

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense and click the "Delete" action
   - **Expected:** A confirmation dialog appears (Turbo confirm or browser native)
3. Confirm the deletion
   - **Expected:** The expense is removed from the list; an undo notification appears
4. Observe the undo notification
   - **Expected:** Notification shows with "Deshacer" button and a countdown timer

### Pass Criteria
- [ ] Confirmation dialog appears before deletion
- [ ] Expense is removed from the list
- [ ] Undo notification appears with timer

### Results
**BLOCKED** — Session lost due to rate limiting. The inline delete button triggers a `showDeleteConfirmation` action, and a `delete-confirmation-modal` exists (class confirmed in DOM inspection, `display: none` by default). The confirm modal has "Eliminar" and "Cancelar" buttons. Cannot safely test deletion without a live session and controlled data.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-040: Delete Expense -- Cancel Confirmation
**Priority:** Medium
**Feature:** Inline Actions
**Preconditions:** An expense exists

### Steps
1. Click the "Delete" action on an expense
   - **Expected:** Confirmation dialog appears
2. Cancel/dismiss the confirmation dialog
   - **Expected:** Expense is NOT deleted; list remains unchanged

### Pass Criteria
- [ ] Cancelling confirmation prevents deletion
- [ ] Expense remains in the list

### Results
**BLOCKED** — Session lost due to rate limiting. Cannot test.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---
