# QA Testing Playbook -- Group C+D: Bulk Operations, ML Categorization, Bulk Categorization, Undo History, Email Accounts, Sync Sessions, Sync Conflicts

**Application:** Expense Tracker (Rails 8.1.2)
**URL:** `http://localhost:3000`
**Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**UI Language:** Spanish
**Date:** 2026-03-26

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

## Scenario CD-001: Enter Selection Mode via Keyboard Shortcut
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; dashboard has at least 5 expenses listed in table view

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads showing expense list in a table with rows
2. Click anywhere inside the expense table to give it focus
   - **Expected:** The table area is focused (no visible change required)
3. Press `Ctrl+Shift+A` (or `Cmd+Shift+A` on macOS)
   - **Expected:** Selection mode is toggled ON; checkbox columns appear on the left side of each expense row
4. Press `Ctrl+Shift+A` again
   - **Expected:** Selection mode is toggled OFF; checkbox columns are hidden; any selections are cleared

### Pass Criteria
- [ ] Checkboxes appear when selection mode is enabled
- [ ] Checkboxes disappear when selection mode is disabled
- [ ] No console errors during toggle

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-002: Master Checkbox Selects All Visible Expenses
**Priority:** Critical
**Feature:** Batch Selection
**Preconditions:** User is logged in; dashboard has at least 3 expenses; selection mode is active (checkboxes visible)

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads with expense list
2. Enable selection mode by pressing `Ctrl+Shift+A`
   - **Expected:** Checkbox column appears on each row and in the table header
3. Click the master checkbox in the table header row
   - **Expected:** All individual row checkboxes become checked
4. Observe the selection counter text
   - **Expected:** Counter displays "N de N gastos seleccionados" where N equals the total number of visible expenses
5. Observe the selection toolbar at the bottom of the page
   - **Expected:** A toolbar slides up from the bottom showing the selected count and bulk action buttons

### Pass Criteria
- [ ] Master checkbox checks all individual checkboxes
- [ ] Selection counter shows correct total (e.g., "5 de 5 gastos seleccionados")
- [ ] Selection toolbar becomes visible with slide-up animation
- [ ] Each selected row has a teal-50 background highlight

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-003: Master Checkbox Deselects All Expenses
**Priority:** Critical
**Feature:** Batch Selection
**Preconditions:** User is logged in; all visible expenses are currently selected (master checkbox checked)

### Steps
1. Starting from the state where all expenses are selected (master checkbox is checked)
   - **Expected:** All rows are highlighted with teal-50 background; toolbar is visible
2. Click the master checkbox in the table header to uncheck it
   - **Expected:** All individual checkboxes become unchecked
3. Observe the expense rows
   - **Expected:** All rows lose the teal-50 highlight and return to default styling
4. Observe the selection toolbar
   - **Expected:** The toolbar hides (display: none)
5. Observe the selection counter
   - **Expected:** The counter is hidden

### Pass Criteria
- [ ] All checkboxes are unchecked after clicking master checkbox
- [ ] All row highlights are removed
- [ ] Toolbar is completely hidden
- [ ] Selection counter is hidden

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-004: Individual Checkbox Toggle
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; selection mode is active; no expenses are currently selected

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard` with selection mode active
   - **Expected:** Checkboxes visible on each expense row; none are checked
2. Click the checkbox on the first expense row
   - **Expected:** The checkbox becomes checked; the row background changes to teal-50; `aria-selected` is set to `true`
3. Observe the selection counter
   - **Expected:** Counter shows "1 de N gastos seleccionados"
4. Observe the selection toolbar
   - **Expected:** Toolbar slides up and becomes visible
5. Click the checkbox on a second expense row
   - **Expected:** Second row is also selected; counter updates to "2 de N gastos seleccionados"
6. Click the checkbox on the first expense row again to deselect it
   - **Expected:** First row is deselected; its background returns to default; counter shows "1 de N gastos seleccionados"
7. Observe the master checkbox in the header
   - **Expected:** Master checkbox shows an indeterminate state (dash icon) since some but not all are selected

### Pass Criteria
- [ ] Individual checkboxes toggle correctly
- [ ] Selected rows get teal-50 background
- [ ] Deselected rows lose highlight
- [ ] Counter updates on each toggle
- [ ] Master checkbox shows indeterminate state for partial selection

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-005: Selection Counter Accuracy
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; selection mode active; at least 5 expenses visible

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard` with selection mode active
   - **Expected:** No expenses selected; counter is hidden
2. Select expenses one by one by clicking their checkboxes (select 3 expenses)
   - **Expected:** Counter shows "3 de N gastos seleccionados" after each click the count increments
3. Deselect 1 expense
   - **Expected:** Counter updates to "2 de N gastos seleccionados"
4. Click the master checkbox to select all
   - **Expected:** Counter shows "N de N gastos seleccionados" matching total visible count

### Pass Criteria
- [ ] Counter increments when selecting individual expenses
- [ ] Counter decrements when deselecting individual expenses
- [ ] Counter shows full total when master checkbox is used
- [ ] Counter text follows format "X de Y gastos seleccionados"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-006: Selection Toolbar Slides Up from Bottom
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; selection mode active; no expenses selected

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Selection toolbar is hidden (not visible)
2. Select one expense by clicking its checkbox
   - **Expected:** A toolbar appears at the bottom of the viewport with a slide-up animation (`animate-slide-up` class)
3. Inspect the toolbar contents
   - **Expected:** Toolbar shows the selected count and contains action buttons (Bulk Actions button)
4. Deselect the expense
   - **Expected:** Toolbar hides completely

### Pass Criteria
- [ ] Toolbar is hidden when no expenses are selected
- [ ] Toolbar slides up when first expense is selected
- [ ] Toolbar contains action buttons
- [ ] Toolbar hides when all expenses are deselected

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-007: Select All via Ctrl+A Keyboard Shortcut
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; dashboard has expenses; focus is inside the expense table area

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads with expense list
2. Click inside the expense table to focus it
   - **Expected:** Table area is focused
3. Press `Ctrl+A` (or `Cmd+A` on macOS)
   - **Expected:** All visible expenses are selected; all checkboxes become checked; selection mode is enabled if not already active
4. Observe the selection counter
   - **Expected:** Counter shows total count matching all visible expenses
5. Observe the master checkbox
   - **Expected:** Master checkbox is checked (not indeterminate)

### Pass Criteria
- [ ] Ctrl+A selects all visible expenses
- [ ] Selection mode is auto-enabled if not already active
- [ ] Screen reader announcement "N gastos seleccionados" is generated (check DOM for sr-only element with role="status")
- [ ] Default browser select-all is prevented (no text selection)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-008: Escape Key Clears Selection
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; some expenses are selected; toolbar is visible

### Steps
1. Starting from a state where 3 or more expenses are selected
   - **Expected:** Selection toolbar is visible; counter shows selected count
2. Press the `Escape` key
   - **Expected:** All selections are cleared; all checkboxes unchecked
3. Observe the toolbar
   - **Expected:** Toolbar is hidden
4. Observe expense rows
   - **Expected:** All rows have default styling (no teal-50 highlight)
5. Observe the selection counter
   - **Expected:** Counter is hidden
6. Check for screen reader announcement
   - **Expected:** A sr-only element with text "Seleccion limpiada" was briefly added to the DOM

### Pass Criteria
- [ ] Escape clears all selected checkboxes
- [ ] Toolbar hides after Escape
- [ ] Row highlights are removed
- [ ] Counter is hidden

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-009: Clear Selection Button
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; expenses are selected; toolbar is visible

### Steps
1. Starting from a state with selected expenses and the toolbar visible
   - **Expected:** Toolbar shows selected count and has a clear selection button
2. Click the "Clear Selection" or "Limpiar seleccion" button in the toolbar
   - **Expected:** All selections are cleared; all checkboxes become unchecked
3. Observe the toolbar
   - **Expected:** Toolbar hides
4. Observe the master checkbox
   - **Expected:** Master checkbox is unchecked and not indeterminate

### Pass Criteria
- [ ] Clear selection button deselects all expenses
- [ ] Toolbar disappears
- [ ] Master checkbox resets to unchecked

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-010: Selection Persists Across View Toggle
**Priority:** High
**Feature:** Batch Selection
**Preconditions:** User is logged in; expenses are selected; view toggle (compact/expanded) is available

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads with expense table
2. Enable selection mode and select 3 expenses; note their expense IDs
   - **Expected:** 3 expenses selected; counter shows "3 de N gastos seleccionados"
3. Toggle the view mode (e.g., from compact to expanded or vice versa)
   - **Expected:** View layout changes but selected expenses remain checked
4. Observe the selected rows after the toggle
   - **Expected:** Previously selected expense rows still have teal-50 highlight and checked checkboxes
5. Observe the counter
   - **Expected:** Counter still shows "3 de N gastos seleccionados"

### Pass Criteria
- [ ] Selection state is preserved across view toggle
- [ ] Row highlighting reapplied after view change
- [ ] Counter remains accurate

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-011: Open Bulk Operations Modal
**Priority:** Critical
**Feature:** Bulk Operations
**Preconditions:** User is logged in; at least 2 expenses are selected

### Steps
1. Starting from a state with 2+ expenses selected and toolbar visible
   - **Expected:** Toolbar is visible with "Operaciones en Lote" or bulk actions button enabled
2. Click the bulk actions button in the toolbar
   - **Expected:** A modal dialog opens with the title "Operaciones en Lote"
3. Observe the modal header
   - **Expected:** Modal header shows "N gastos seleccionados" matching the selection count
4. Observe the modal body
   - **Expected:** Three operation type radio buttons are visible: "Categorizar", "Actualizar Estado", "Eliminar"
5. Observe the modal footer
   - **Expected:** "Cancelar" and "Ejecutar" buttons are present; "Ejecutar" is disabled by default

### Pass Criteria
- [ ] Modal opens when bulk actions button is clicked
- [ ] Modal displays correct selected count
- [ ] Three operation types are listed
- [ ] Submit button is disabled until an operation is selected
- [ ] Modal has `role="dialog"` and `aria-labelledby` attributes

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-012: Bulk Categorize via Modal
**Priority:** Critical
**Feature:** Bulk Operations
**Preconditions:** User is logged in; 2+ expenses are selected; bulk operations modal is open

### Steps
1. In the bulk operations modal, select the "Categorizar" radio button
   - **Expected:** A category dropdown appears below the radio buttons with label "Seleccionar Categoria"
2. Select a category from the dropdown (e.g., "Alimentacion")
   - **Expected:** The "Ejecutar" button becomes enabled (no longer has `opacity-50` class)
3. Click the "Ejecutar" button
   - **Expected:** A progress bar appears inside the modal showing processing status
4. Wait for the operation to complete
   - **Expected:** A success message appears (emerald background); the modal may auto-close or show completion state
5. Observe the expense list after the modal closes
   - **Expected:** The previously selected expenses now show the assigned category; selection is cleared; toolbar is hidden

### Pass Criteria
- [ ] Category dropdown appears when "Categorizar" is selected
- [ ] "Ejecutar" button enables after selecting a category
- [ ] Progress indicator shows during processing
- [ ] Expenses are updated with the new category after completion
- [ ] Selection is cleared after successful operation

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-013: Bulk Status Update via Modal
**Priority:** High
**Feature:** Bulk Operations
**Preconditions:** User is logged in; 2+ expenses are selected; bulk operations modal is open

### Steps
1. In the bulk operations modal, select the "Actualizar Estado" radio button
   - **Expected:** A status dropdown appears with options: Pendiente, Procesado, Fallido, Duplicado
2. Select "Procesado" from the dropdown
   - **Expected:** The "Ejecutar" button becomes enabled
3. Click the "Ejecutar" button
   - **Expected:** Processing begins; progress indicator shows
4. Wait for the operation to complete
   - **Expected:** Success message appears
5. Observe the expense list
   - **Expected:** Selected expenses now show "Procesado" status; selection is cleared

### Pass Criteria
- [ ] Status dropdown appears with four status options
- [ ] All selected expenses are updated to "Procesado"
- [ ] Selection clears after successful operation

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-014: Bulk Delete with Confirmation
**Priority:** Critical
**Feature:** Bulk Operations
**Preconditions:** User is logged in; 2+ expenses selected; bulk operations modal open

### Steps
1. In the bulk operations modal, select the "Eliminar" radio button
   - **Expected:** A warning panel appears with rose/red background: "Advertencia: Los gastos eliminados se pueden deshacer dentro de un tiempo limitado."
2. Observe the confirmation checkbox
   - **Expected:** A checkbox with text "Confirmo que deseo eliminar estos gastos" is visible; "Ejecutar" button is still disabled
3. Check the confirmation checkbox
   - **Expected:** The "Ejecutar" button becomes enabled
4. Click the "Ejecutar" button
   - **Expected:** Processing begins; progress indicator shows
5. Wait for the operation to complete
   - **Expected:** Expenses are deleted from the list; an undo notification may appear
6. Observe the expense list
   - **Expected:** The deleted expenses are no longer visible in the list

### Pass Criteria
- [ ] Delete warning panel displays with correct count
- [ ] "Ejecutar" is disabled until confirmation checkbox is checked
- [ ] Expenses are removed from the list after deletion
- [ ] An undo notification appears allowing recovery

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-015: Bulk Operations Modal Close via Cancel
**Priority:** Medium
**Feature:** Bulk Operations
**Preconditions:** Bulk operations modal is open

### Steps
1. In the bulk operations modal, click the "Cancelar" button in the footer
   - **Expected:** Modal closes; no operations are performed
2. Observe the selection state
   - **Expected:** Expense selections are preserved (still selected)
3. Observe the toolbar
   - **Expected:** Selection toolbar is still visible

### Pass Criteria
- [ ] Modal closes on Cancel without performing any operation
- [ ] Selections are preserved after closing modal

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-016: Bulk Operations Modal Close via X Button
**Priority:** Medium
**Feature:** Bulk Operations
**Preconditions:** Bulk operations modal is open

### Steps
1. In the bulk operations modal, click the X button in the top-right corner of the modal header
   - **Expected:** Modal closes; no operations performed
2. Observe the selection state
   - **Expected:** Selections remain intact

### Pass Criteria
- [ ] Modal closes via X button
- [ ] No side effects on expense data

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-017: Bulk Operations Modal Close via Overlay Click
**Priority:** Medium
**Feature:** Bulk Operations
**Preconditions:** Bulk operations modal is open

### Steps
1. Click on the dark overlay area outside the modal dialog
   - **Expected:** Modal closes

### Pass Criteria
- [ ] Modal closes when clicking outside of it

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-018: Bulk Actions Button Disabled with No Selection
**Priority:** High
**Feature:** Bulk Operations
**Preconditions:** User is logged in; selection mode is active but no expenses selected

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard` with selection mode active but no selections
   - **Expected:** Bulk actions button is visible but disabled
2. Observe the button styling
   - **Expected:** Button has `opacity-50` and `cursor-not-allowed` classes
3. Click the disabled button
   - **Expected:** Nothing happens; modal does not open

### Pass Criteria
- [ ] Button is disabled when no expenses are selected
- [ ] Button has visual disabled styling
- [ ] Clicking does not open the modal

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-019: Row Click Toggles Selection in Selection Mode
**Priority:** Medium
**Feature:** Batch Selection
**Preconditions:** User is logged in; selection mode is active

### Steps
1. Navigate to dashboard with selection mode active
   - **Expected:** Checkboxes visible; no selections
2. Click on a row body area (not on a checkbox, button, or link)
   - **Expected:** The row's checkbox toggles to checked; row gets teal-50 highlight
3. Click on the same row body area again
   - **Expected:** The row's checkbox toggles to unchecked; highlight is removed

### Pass Criteria
- [ ] Row click toggles the checkbox in selection mode
- [ ] Clicking on buttons/links within the row does NOT toggle selection
- [ ] Row highlighting updates with checkbox state

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-020: Row Click Does Not Toggle Outside Selection Mode
**Priority:** Medium
**Feature:** Batch Selection
**Preconditions:** User is logged in; selection mode is NOT active

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard` without entering selection mode
   - **Expected:** No checkboxes visible
2. Click on an expense row body area
   - **Expected:** No selection behavior occurs; row does not highlight with teal-50

### Pass Criteria
- [ ] No selection occurs when clicking rows outside selection mode

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

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

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-041: Needs Review Indicator
**Priority:** Medium
**Feature:** ML Categorization
**Preconditions:** An expense has the `needs_review?` flag set to true

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard loads
2. Locate an expense that needs review
   - **Expected:** The expense displays a visual "needs review" indicator (e.g., an icon, badge, or highlighted border)

### Pass Criteria
- [ ] Expenses requiring review have a distinct visual indicator
- [ ] Indicator is clearly distinguishable from normal expenses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-042: Correct Category Updates ml_last_corrected_at
**Priority:** Medium
**Feature:** ML Categorization
**Preconditions:** An expense exists; user has access to Rails console or can verify timestamps via API

### Steps
1. Note the current `ml_last_corrected_at` value for an expense (check via Rails console: `Expense.find(ID).ml_last_corrected_at`)
   - **Expected:** Value is either nil or a past timestamp
2. Correct the expense's category via the inline action (POST `/expenses/:id/correct_category`)
   - **Expected:** Category updates successfully
3. Check the `ml_last_corrected_at` value again
   - **Expected:** Timestamp has been updated to approximately the current time

### Pass Criteria
- [ ] `ml_last_corrected_at` is updated after correction
- [ ] Timestamp is recent (within last few seconds)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Bulk Categorization Workflow

---

## Scenario CD-043: Navigate to Bulk Categorization Page
**Priority:** Critical
**Feature:** Bulk Categorization
**Preconditions:** User is logged in; some uncategorized expenses exist in the database

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with title "Categorizacion Masiva" and subtitle "Revisa y categoriza multiples gastos similares a la vez"
2. Observe the statistics bar at the top
   - **Expected:** Four statistics cards are displayed: "Grupos Totales", "Gastos Totales", "Alta Confianza", "Monto Total"
3. Observe the main content area
   - **Expected:** Uncategorized expenses are grouped by similarity; each group is a card with a header

### Pass Criteria
- [ ] Page loads without errors
- [ ] Statistics bar shows all four metrics
- [ ] Expense groups are displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-044: Expense Groups Show Correct Details
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** User is on `/bulk_categorizations`; at least one expense group exists

### Steps
1. Observe any expense group card
   - **Expected:** Group header shows: group name (merchant or description pattern), expense count (e.g., "3 gastos"), total amount (e.g., "C/1,500")
2. Observe the confidence badge on the group
   - **Expected:** A percentage badge showing confidence (e.g., "85% confianza") with appropriate color: emerald for >80%, amber for 60-80%, rose for <60%
3. Observe the group type badge
   - **Expected:** A badge showing grouping type (e.g., "Comercio exacto", "Coincidencia aproximada", etc.)

### Pass Criteria
- [ ] Group name, count, and amount are displayed
- [ ] Confidence badge shows correct color per threshold
- [ ] Group type badge is visible and descriptive

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-045: High Confidence Group Visual Indicator
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** At least one group has confidence > 0.8

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with groups
2. Locate a group with confidence > 80%
   - **Expected:** Its confidence badge has emerald green styling (`bg-emerald-100 text-emerald-800`)
3. Locate a group with confidence < 60%
   - **Expected:** Its confidence badge has rose/red styling (`bg-rose-100 text-rose-800`)

### Pass Criteria
- [ ] High confidence groups (>80%) show emerald badge
- [ ] Medium confidence groups (60-80%) show amber badge
- [ ] Low confidence groups (<60%) show rose badge

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-046: Empty State When No Uncategorized Expenses
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** All expenses have categories assigned (no uncategorized expenses)

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with an empty state view
2. Observe the empty state message
   - **Expected:** A centered card with a checkmark icon and text "Todo al dia!" and "No hay gastos sin categorizar que revisar."

### Pass Criteria
- [ ] Empty state displays when no uncategorized expenses exist
- [ ] Message text is correct in Spanish
- [ ] Checkmark icon is visible

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-047: Suggested Category Shown for Group
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** At least one group has a `suggested_category` from the ML engine

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with groups
2. Locate a group that has a suggested category
   - **Expected:** Below the group header, a teal-50 banner shows "Sugerida: [Category Name]" with confidence percentage and an "Aplicar Sugerencia" button

### Pass Criteria
- [ ] Suggested category name is displayed
- [ ] Suggestion confidence percentage is shown
- [ ] "Aplicar Sugerencia" button is present

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-048: Apply Suggested Category to Group
**Priority:** Critical
**Feature:** Bulk Categorization
**Preconditions:** A group has a suggested category; user is on `/bulk_categorizations`

### Steps
1. Locate a group with a suggested category
   - **Expected:** "Aplicar Sugerencia" button visible
2. Click the "Aplicar Sugerencia" button
   - **Expected:** All expenses in the group are categorized with the suggested category
3. Observe the group after applying
   - **Expected:** The group may disappear from the list (since expenses are now categorized) or show as categorized; statistics update

### Pass Criteria
- [ ] Clicking "Aplicar Sugerencia" categorizes all group expenses
- [ ] Statistics update to reflect fewer uncategorized expenses
- [ ] Group is removed or updated

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-049: Select Category from Dropdown and Apply to Group
**Priority:** Critical
**Feature:** Bulk Categorization
**Preconditions:** A group exists; user is on `/bulk_categorizations`

### Steps
1. Locate any expense group
   - **Expected:** Group has a category dropdown selector ("Selecciona una categoria...") and an "Aplicar a Todo" button
2. Open the category dropdown
   - **Expected:** Categories listed with parent hierarchy (e.g., "Transporte -> Gasolina")
3. Select a category from the dropdown
   - **Expected:** The dropdown shows the selected category
4. Click the "Aplicar a Todo" button
   - **Expected:** All expenses in the group are assigned the selected category

### Pass Criteria
- [ ] Category dropdown shows hierarchical categories
- [ ] "Aplicar a Todo" assigns the category to all expenses in the group
- [ ] Group updates or is removed from the page

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-050: Expand Group to See Individual Expenses
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** A group with multiple expenses exists

### Steps
1. Locate a group card on `/bulk_categorizations`
   - **Expected:** Group shows the collapse/expand chevron button
2. Click the expand button (chevron icon)
   - **Expected:** The hidden expense details section expands showing individual expenses
3. Observe the expanded list
   - **Expected:** Each expense shows: checkbox (checked by default), description, date, bank name, amount, and an individual category override dropdown
4. Click the expand button again
   - **Expected:** The expense list collapses and hides

### Pass Criteria
- [ ] Expand button shows individual expenses
- [ ] Each expense has correct details displayed
- [ ] Individual category override dropdown is present
- [ ] Collapse button hides the list

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-051: Individual Expense Override Category
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** A group is expanded showing individual expenses

### Steps
1. Expand a group to show individual expenses
   - **Expected:** Each expense has an "Usar categoria del grupo" default in the override dropdown
2. On one individual expense, change the override dropdown to a different category
   - **Expected:** The dropdown updates to show the selected override category
3. Apply the group category (click "Aplicar a Todo")
   - **Expected:** The overridden expense gets its individually selected category, while others get the group category

### Pass Criteria
- [ ] Individual override dropdown allows selecting a different category
- [ ] Override is respected when applying group category

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-052: Deselect Individual Expense from Group
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** A group is expanded showing individual expenses with checkboxes

### Steps
1. Expand a group to show individual expenses
   - **Expected:** All expense checkboxes are checked by default
2. Uncheck one expense's checkbox
   - **Expected:** The checkbox becomes unchecked
3. Apply the group category
   - **Expected:** The unchecked expense is excluded from categorization; only checked expenses are updated

### Pass Criteria
- [ ] Unchecking an expense excludes it from the group operation
- [ ] Only checked expenses are categorized

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-053: Preview Button Shows Preview Modal
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** A group exists; a category is selected in the dropdown

### Steps
1. Select a category from the dropdown for a group
   - **Expected:** Category is selected
2. Click the "Previsualizar" button
   - **Expected:** A preview modal or section appears showing what would change (expenses and their new categories) without making changes

### Pass Criteria
- [ ] Preview does not modify any data
- [ ] Preview shows the expected categorization result

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-054: Auto-Categorize High Confidence Button
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** High-confidence groups exist on `/bulk_categorizations`

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with header area showing "Categorizar Automaticamente Alta Confianza" button
2. Click the "Categorizar Automaticamente Alta Confianza" button
   - **Expected:** A POST request is sent to `/bulk_categorizations/auto_categorize`; processing begins
3. Wait for completion
   - **Expected:** High-confidence groups are auto-categorized; statistics update; groups disappear from the list

### Pass Criteria
- [ ] Auto-categorize processes high-confidence groups
- [ ] Statistics update after processing
- [ ] Low-confidence groups remain unchanged

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-055: Export Bulk Categorization Report
**Priority:** Medium
**Feature:** Bulk Categorization
**Preconditions:** Uncategorized expenses exist

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Page loads with "Exportar Reporte" button in the header
2. Click the "Exportar Reporte" link
   - **Expected:** Browser downloads a CSV file
3. Inspect the downloaded file
   - **Expected:** File is named with the pattern `bulk_categorizations_YYYYMMDD.csv` and contains expense data

### Pass Criteria
- [ ] CSV file downloads successfully
- [ ] File name contains the current date
- [ ] File contains relevant expense data

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-056: View Bulk Operation Details
**Priority:** Medium
**Feature:** Bulk Categorization
**Preconditions:** A bulk operation has been performed; its ID is known

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations/:id` (replace `:id` with a real bulk operation ID)
   - **Expected:** Page loads with title "Detalles de Operacion Masiva"
2. Observe the operation summary
   - **Expected:** Shows "Operacion Masiva #[ID]" and the count of affected expenses
3. Observe the affected expenses section
   - **Expected:** Lists all expenses that were affected by the bulk operation

### Pass Criteria
- [ ] Operation details page loads without errors
- [ ] Operation ID is displayed
- [ ] Affected expense count matches actual count

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-057: Undo Bulk Categorization
**Priority:** Critical
**Feature:** Bulk Categorization
**Preconditions:** A completed bulk categorization operation exists; its ID is known

### Steps
1. Send a POST request to `/bulk_categorizations/:id/undo`
   - **Expected:** The operation is reversed; all affected expenses return to uncategorized (null category)
2. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** The previously categorized expenses now appear as uncategorized groups again

### Pass Criteria
- [ ] Undo reverses the bulk categorization
- [ ] Affected expenses return to uncategorized state
- [ ] Success message is returned

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-058: Pagination on Bulk Categorizations
**Priority:** Medium
**Feature:** Bulk Categorization
**Preconditions:** More than 100 uncategorized expenses exist

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** First page loads with up to 100 expenses (grouped)
2. Navigate to `http://localhost:3000/bulk_categorizations?page=2`
   - **Expected:** Second page loads with the next batch of expenses

### Pass Criteria
- [ ] First page shows up to 100 expenses
- [ ] Page parameter loads the correct offset of expenses
- [ ] Groups are consistent between pages

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-059: Statistics Bar Updates Reflect Actual Data
**Priority:** High
**Feature:** Bulk Categorization
**Preconditions:** Uncategorized expenses exist

### Steps
1. Navigate to `http://localhost:3000/bulk_categorizations`
   - **Expected:** Statistics bar shows: Grupos Totales, Gastos Totales, Alta Confianza, Monto Total
2. Note the values displayed
   - **Expected:** Values are non-zero and logically consistent (e.g., Alta Confianza <= Grupos Totales)
3. Categorize one group and reload the page
   - **Expected:** Statistics values decrease to reflect fewer uncategorized expenses

### Pass Criteria
- [ ] All four statistics values are displayed
- [ ] Values are logically consistent
- [ ] Values update after categorization

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-060: Graceful Degradation on Grouping Error
**Priority:** Medium
**Feature:** Bulk Categorization
**Preconditions:** This tests error handling (may require mocking a service failure)

### Steps
1. If possible, simulate a grouping service failure (e.g., by temporarily breaking the `GroupingService`)
   - **Expected:** The page still loads
2. Observe the page
   - **Expected:** A warning flash message appears: "No se pudieron agrupar los gastos. Mostrando lista sin agrupar."
3. Observe the main content
   - **Expected:** An empty or ungrouped list is shown; no 500 error page

### Pass Criteria
- [ ] Page does not crash on grouping error
- [ ] Warning flash message is displayed
- [ ] Statistics default to zero values

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Email Accounts

---

## Scenario CD-061: List Email Accounts
**Priority:** Critical
**Feature:** Email Accounts
**Preconditions:** User is logged in; at least one email account exists in the database

### Steps
1. Navigate to `http://localhost:3000/email_accounts`
   - **Expected:** Page loads with title "Cuentas de Correo" and subtitle about managing email accounts
2. Observe the table
   - **Expected:** Table has columns: Email, Banco, Proveedor, Estado, Acciones
3. Observe the email account rows
   - **Expected:** Each row shows: email address, bank name, provider (capitalized), active status badge (green "Activa" or gray "Inactiva"), and Edit/Delete action links
4. Observe the "Nueva cuenta" button
   - **Expected:** A teal button labeled "Nueva cuenta" is visible in the header area

### Pass Criteria
- [ ] Table displays all email accounts
- [ ] Columns are correct: Email, Banco, Proveedor, Estado, Acciones
- [ ] Active accounts show green "Activa" badge
- [ ] Inactive accounts show gray "Inactiva" badge
- [ ] "Nueva cuenta" button is present

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-062: Empty State for Email Accounts
**Priority:** Medium
**Feature:** Email Accounts
**Preconditions:** No email accounts exist in the database

### Steps
1. Navigate to `http://localhost:3000/email_accounts`
   - **Expected:** Page loads with the table structure
2. Observe the table body
   - **Expected:** A single row spanning all columns with text: "No hay cuentas de correo configuradas. Crear la primera cuenta" where "Crear la primera cuenta" is a link to `/email_accounts/new`

### Pass Criteria
- [ ] Empty state message is displayed
- [ ] Link to create first account works

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-063: Navigate to New Email Account Form
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/email_accounts/new`
   - **Expected:** Page loads with title "Nueva Cuenta de Correo"
2. Observe the form fields
   - **Expected:** The following fields are present:
     - "Correo electronico" (email input)
     - "Contrasena" (password input)
     - "Banco" (select dropdown)
     - "Proveedor de correo" (select dropdown with help text about Gmail/Outlook auto-config)
     - "Servidor IMAP (opcional)" (text input)
     - "Puerto (opcional)" (number input, placeholder 993)
     - "Cuenta activa" (checkbox)
3. Observe the form buttons
   - **Expected:** "Cancelar" link and "Crear cuenta" submit button

### Pass Criteria
- [ ] All form fields are present and labeled correctly
- [ ] Help texts are visible under password, provider, server, and port fields
- [ ] Submit button text is "Crear cuenta"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-064: Create Email Account with All Fields
**Priority:** Critical
**Feature:** Email Accounts
**Preconditions:** User is on the new email account form

### Steps
1. Navigate to `http://localhost:3000/email_accounts/new`
   - **Expected:** Form loads
2. Fill in "Correo electronico" with `test@testbank.com`
   - **Expected:** Email field populated
3. Fill in "Contrasena" with `SecurePass123!`
   - **Expected:** Password field populated (masked)
4. Select a bank from the "Banco" dropdown
   - **Expected:** Bank is selected
5. Select a provider from the "Proveedor de correo" dropdown (e.g., "Gmail")
   - **Expected:** Provider is selected
6. Fill in "Servidor IMAP" with `imap.testbank.com`
   - **Expected:** Server field populated
7. Fill in "Puerto" with `993`
   - **Expected:** Port field populated
8. Check the "Cuenta activa" checkbox
   - **Expected:** Checkbox is checked
9. Click "Crear cuenta"
   - **Expected:** Redirect to the show page `/email_accounts/:id` with a success flash message

### Pass Criteria
- [ ] Account is created successfully
- [ ] Redirect to show page occurs
- [ ] Success flash message appears
- [ ] Password is stored encrypted (not plaintext)
- [ ] Custom IMAP settings are stored in the `settings` JSON field

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-065: Create Email Account -- Validation Error
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** User is on the new email account form

### Steps
1. Navigate to `http://localhost:3000/email_accounts/new`
   - **Expected:** Form loads
2. Leave all fields blank
   - **Expected:** Fields are empty
3. Click "Crear cuenta"
   - **Expected:** Page re-renders with the form (status 422); a rose/red error panel appears listing validation errors (e.g., "Email no puede estar en blanco")

### Pass Criteria
- [ ] Form is not submitted with missing required fields
- [ ] Validation errors are displayed in rose-50 background panel
- [ ] Error messages are in Spanish

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-066: View Email Account Details
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** An email account exists

### Steps
1. Navigate to `http://localhost:3000/email_accounts/:id` (use an existing account ID)
   - **Expected:** Page loads with title "Cuenta de Correo"
2. Observe the detail card
   - **Expected:** Shows fields: Email, Banco, Proveedor, Servidor IMAP, Puerto, Estado (with active/inactive badge)
3. Observe the action buttons
   - **Expected:** "Editar" button (links to edit page) and "Volver" button (links to index)

### Pass Criteria
- [ ] All account details are displayed correctly
- [ ] Status badge shows correct active/inactive state
- [ ] Edit and Back buttons work

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-067: Edit Email Account
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** An email account exists

### Steps
1. Navigate to `http://localhost:3000/email_accounts/:id/edit`
   - **Expected:** Edit form loads with title "Editar Cuenta de Correo"; fields are pre-populated with current values
2. Verify pre-populated values
   - **Expected:** Email, bank, provider, server (from settings), port (from settings), and active status are pre-filled
3. Change the bank to a different value
   - **Expected:** Dropdown updates
4. Click "Actualizar cuenta"
   - **Expected:** Redirect to show page with success flash message; bank is updated

### Pass Criteria
- [ ] Edit form pre-populates current values
- [ ] Update redirects to show page with success message
- [ ] Changed field is persisted

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-068: Edit Email Account -- Update Password
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** An email account exists

### Steps
1. Navigate to `http://localhost:3000/email_accounts/:id/edit`
   - **Expected:** Form loads; password field has placeholder "Dejar en blanco para mantener la actual"
2. Enter a new password in the password field
   - **Expected:** Password field shows masked characters
3. Click "Actualizar cuenta"
   - **Expected:** Redirect to show page; encrypted password is updated

### Pass Criteria
- [ ] Password field placeholder text is correct
- [ ] New password is saved as encrypted
- [ ] Redirect with success message

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-069: Edit Email Account -- Preserve Password When Blank
**Priority:** High
**Feature:** Email Accounts
**Preconditions:** An email account exists with a stored password

### Steps
1. Navigate to `http://localhost:3000/email_accounts/:id/edit`
   - **Expected:** Form loads; password field is empty
2. Leave the password field blank
   - **Expected:** Field remains empty
3. Change another field (e.g., toggle active checkbox)
   - **Expected:** Checkbox changes
4. Click "Actualizar cuenta"
   - **Expected:** Account updates successfully; the existing encrypted password is preserved (not wiped)

### Pass Criteria
- [ ] Leaving password blank does not clear the stored password
- [ ] Other field changes are saved

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-070: Edit Email Account -- Update IMAP Settings Merge
**Priority:** Medium
**Feature:** Email Accounts
**Preconditions:** An email account exists with custom IMAP settings

### Steps
1. Navigate to `http://localhost:3000/email_accounts/:id/edit`
   - **Expected:** Form loads with server and port pre-populated from `settings["imap"]`
2. Change only the port to `995`
   - **Expected:** Port field shows 995; server field retains original value
3. Click "Actualizar cuenta"
   - **Expected:** Settings are merged -- new port is saved while existing server is preserved

### Pass Criteria
- [ ] IMAP settings are merged, not replaced
- [ ] Unchanged server value is preserved
- [ ] New port value is saved

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-071: Delete Email Account
**Priority:** Critical
**Feature:** Email Accounts
**Preconditions:** An email account exists; preferably one without critical associated expenses

### Steps
1. Navigate to `http://localhost:3000/email_accounts`
   - **Expected:** List of email accounts visible
2. Click the "Eliminar" (Delete) button next to an email account
   - **Expected:** A Turbo confirmation dialog appears asking "Esta seguro?" or similar
3. Confirm the deletion
   - **Expected:** The email account is deleted; redirect to `/email_accounts` with success flash message
4. Observe the list
   - **Expected:** The deleted account is no longer in the list

### Pass Criteria
- [ ] Confirmation dialog appears before deletion
- [ ] Account is removed from the database
- [ ] Redirect to index with success message
- [ ] Account no longer appears in the list

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-072: Delete Email Account -- Cancel
**Priority:** Medium
**Feature:** Email Accounts
**Preconditions:** An email account exists

### Steps
1. Navigate to `http://localhost:3000/email_accounts`
   - **Expected:** List visible
2. Click "Eliminar" next to an account
   - **Expected:** Confirmation dialog appears
3. Cancel the confirmation dialog
   - **Expected:** Account is NOT deleted; list is unchanged

### Pass Criteria
- [ ] Cancelling prevents deletion
- [ ] Account remains in the list

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-073: Create Email Account Without Custom Server/Port
**Priority:** Medium
**Feature:** Email Accounts
**Preconditions:** User is on new email account form

### Steps
1. Navigate to `http://localhost:3000/email_accounts/new`
   - **Expected:** Form loads
2. Fill in email, password, bank, and provider; leave server and port fields blank
   - **Expected:** Fields populated except server/port
3. Click "Crear cuenta"
   - **Expected:** Account is created; IMAP settings are not added to the `settings` JSON field (no "imap" key in settings)

### Pass Criteria
- [ ] Account created successfully without custom IMAP settings
- [ ] Settings JSON does not contain IMAP entries when server/port are blank

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-074: Email Account Cancel Button Returns to List
**Priority:** Medium
**Feature:** Email Accounts
**Preconditions:** User is on new or edit email account form

### Steps
1. Navigate to `http://localhost:3000/email_accounts/new`
   - **Expected:** Form loads
2. Click the "Cancelar" link
   - **Expected:** User is redirected back to `http://localhost:3000/email_accounts`

### Pass Criteria
- [ ] Cancel link navigates to email accounts list
- [ ] No data is submitted

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Sync Sessions

---

## Scenario CD-075: View Sync Sessions Index
**Priority:** Critical
**Feature:** Sync Sessions
**Preconditions:** User is logged in; at least one sync session exists

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Page loads with header "Centro de Sincronizacion" on a teal gradient banner
2. Observe the summary stats in the header
   - **Expected:** Three stat cards: "Cuentas Activas" (count), "Sincronizaciones Hoy" (count), "Gastos Detectados (Mes)" (count)
3. Observe the quick action cards
   - **Expected:** Three cards: "Sincronizar Todo" (with button), "Ultima Sincronizacion" (with timestamp), "Estado del Sistema" (health status)
4. Observe the sync history table
   - **Expected:** Table with columns: Iniciada, Duracion, Estado, Cuentas, Emails, Gastos, Acciones

### Pass Criteria
- [ ] Page loads without errors
- [ ] Header stats display numeric values
- [ ] Quick action cards are present and functional
- [ ] Sync history table shows recent sessions

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-076: Sync Session Status Badges
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** Sync sessions exist with various statuses (completed, failed, cancelled, running)

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Sync history table visible
2. Observe a completed session row
   - **Expected:** Status badge shows green (`bg-emerald-100 text-emerald-800`) with "Completed" or equivalent
3. Observe a failed session row (if exists)
   - **Expected:** Status badge shows rose/red (`bg-rose-100 text-rose-800`)
4. Observe a cancelled session (if exists)
   - **Expected:** Status badge shows amber (`bg-amber-100 text-amber-800`)
5. Observe a running session (if exists)
   - **Expected:** Status badge shows teal with `animate-pulse` and text "Sincronizando"

### Pass Criteria
- [ ] Completed sessions show emerald badge
- [ ] Failed sessions show rose badge
- [ ] Cancelled sessions show amber badge
- [ ] Running sessions show teal pulsing badge

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-077: Start Manual Sync -- All Accounts
**Priority:** Critical
**Feature:** Sync Sessions
**Preconditions:** User is logged in; no active sync session; active email accounts exist

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Page loads; "Iniciar Sincronizacion" button is enabled in the "Sincronizar Todo" card
2. Click the "Iniciar Sincronizacion" button
   - **Expected:** A POST request is sent to `/sync_sessions`; a new sync session is created
3. Observe the page response
   - **Expected:** Redirect to sync sessions page with success flash "Sincronizacion iniciada" or the sync widget updates via Turbo Stream showing the active session

### Pass Criteria
- [ ] New sync session is created
- [ ] Success message or widget update appears
- [ ] Active session indicator shows on the page

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-078: Start Sync -- Button Disabled When Active Session Exists
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** An active sync session is already running

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Page shows the active session with spinner and progress bar
2. Observe the "Iniciar Sincronizacion" button
   - **Expected:** Button is disabled (has `disabled` attribute)
3. Attempt to click the disabled button
   - **Expected:** Nothing happens; no new session is created

### Pass Criteria
- [ ] Button is disabled when a sync is active
- [ ] Cannot create a duplicate session

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-079: Active Sync Session Progress Display
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** An active sync session is running

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** An amber-bordered section appears at the top: "Sincronizacion en Progreso"
2. Observe the progress bar
   - **Expected:** Shows current progress percentage and "X / Y emails" count
3. Observe the per-account cards
   - **Expected:** Grid of cards showing each email account's bank name, email, status badge, processed/total count, and detected expenses
4. Observe the cancel button
   - **Expected:** A red "Cancelar" button is visible

### Pass Criteria
- [ ] Active session section shows with spinning indicator
- [ ] Progress bar reflects current percentage
- [ ] Per-account cards show individual progress
- [ ] Cancel button is visible

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-080: Cancel Active Sync Session
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** An active sync session is running

### Steps
1. Navigate to `http://localhost:3000/sync_sessions` with an active session visible
   - **Expected:** Active session section with "Cancelar" button
2. Click the "Cancelar" button
   - **Expected:** A POST request is sent to `/sync_sessions/:id/cancel`
3. Observe the response
   - **Expected:** Session status changes to "cancelled"; redirect to sync sessions page with notice

### Pass Criteria
- [ ] Session is cancelled successfully
- [ ] Status changes to "cancelled"
- [ ] Flash message confirms cancellation

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-081: Cancel Non-Active Session Returns Error
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** A completed or cancelled sync session exists

### Steps
1. Attempt to POST to `/sync_sessions/:id/cancel` for a non-active session
   - **Expected:** Redirect with alert message "not active" or equivalent

### Pass Criteria
- [ ] Error message returned for non-active session
- [ ] Session state is unchanged

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-082: View Sync Session Detail Page
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** A sync session exists (completed or active)

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Sync history table visible
2. Click "Ver Detalles" on any session row
   - **Expected:** Navigate to `/sync_sessions/:id`
3. Observe the breadcrumb navigation
   - **Expected:** Shows "Centro de Sincronizacion > Sesion #[ID]"
4. Observe the page header
   - **Expected:** Title "Detalles de Sincronizacion" with description text
5. Observe the left column -- Session Info card
   - **Expected:** Shows Estado (status badge), Iniciada (start time), Completada (end time or "-"), Duracion
6. Observe the left column -- Summary card
   - **Expected:** Shows Cuentas procesadas, Total de emails, Emails procesados, Gastos detectados
7. Observe the right column -- Account Details
   - **Expected:** Each account card shows: bank name, email, status badge, emails processed (with progress bar), detected expenses, start time, last update time

### Pass Criteria
- [ ] Breadcrumb navigation is correct
- [ ] Session info card shows all fields
- [ ] Summary card shows all metrics
- [ ] Per-account detail cards are displayed correctly

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-083: Sync Session Detail -- Running Session Shows Real-Time Progress
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** An active/running sync session exists

### Steps
1. Navigate to `/sync_sessions/:id` for a running session
   - **Expected:** A gradient progress section appears: "Progreso en Tiempo Real" with spinning indicator and "Sincronizando..."
2. Observe the progress bar
   - **Expected:** Shows current percentage with gradient fill (teal to emerald)
3. Observe the stats below the progress bar
   - **Expected:** Three columns: Emails procesados, Gastos detectados, Tiempo transcurrido
4. Observe the header actions
   - **Expected:** "Cancelar Sincronizacion" button (red) is visible

### Pass Criteria
- [ ] Real-time progress section is visible for running sessions
- [ ] Progress bar shows correct percentage
- [ ] Stats update in real time (via ActionCable)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-084: Sync Session Detail -- Failed/Cancelled Session Shows Retry
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** A failed or cancelled sync session exists

### Steps
1. Navigate to `/sync_sessions/:id` for a failed or cancelled session
   - **Expected:** Page loads; header area shows a "Reintentar" (Retry) button in teal
2. Click the "Reintentar" button
   - **Expected:** A POST request to `/sync_sessions/:id/retry` creates a new session
3. Observe the redirect
   - **Expected:** Redirect to sync sessions list with notice "Sincronizacion reiniciada" or equivalent

### Pass Criteria
- [ ] Retry button is visible for failed/cancelled sessions
- [ ] Clicking retry creates a new session
- [ ] Success message on redirect

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-085: Sync Session Detail -- Completed Session Shows Performance Metrics
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** A completed sync session exists with processed_emails > 0

### Steps
1. Navigate to `/sync_sessions/:id` for a completed session
   - **Expected:** Page loads; Summary card shows a "Metricas de Rendimiento" section below the main stats
2. Observe the performance metrics
   - **Expected:** Shows "Velocidad" (emails/min) and "Tasa de deteccion" (percentage)

### Pass Criteria
- [ ] Performance metrics section appears for completed sessions
- [ ] Speed and detection rate values are displayed and non-zero

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-086: Sync Session Detail -- Error Details for Failed Session
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** A failed sync session exists with error_details

### Steps
1. Navigate to `/sync_sessions/:id` for a failed session with error details
   - **Expected:** A rose/red error panel appears with title "Detalles del Error"
2. Observe the error content
   - **Expected:** Error message text is displayed in the panel

### Pass Criteria
- [ ] Error details panel shows for failed sessions
- [ ] Error message text is readable

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-087: Sync Session Detail -- Account Error Expandable
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** A sync session exists where one account has `last_error` set

### Steps
1. Navigate to `/sync_sessions/:id` where an account encountered an error
   - **Expected:** The account card shows a "Ver error" expandable details link in rose color
2. Click "Ver error"
   - **Expected:** The error details expand below showing the error message in a rose background panel

### Pass Criteria
- [ ] "Ver error" link is visible for accounts with errors
- [ ] Clicking expands to show error details

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-088: Sync Status API Endpoint
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** A sync session exists; its ID is known

### Steps
1. Send a GET request to `http://localhost:3000/api/sync_sessions/:id/status`
   - **Expected:** JSON response with fields: `status`, `progress_percentage`, `processed_emails`, `total_emails`, `detected_expenses`, `time_remaining`, `metrics`, `accounts` array
2. Observe the accounts array
   - **Expected:** Each account object has: `id`, `email`, `bank`, `status`, `progress`, `processed`, `total`, `detected`

### Pass Criteria
- [ ] API returns valid JSON
- [ ] All expected fields are present
- [ ] Accounts array contains per-account data

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-089: Sync Status API -- Session Not Found
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** No session with ID 999999 exists

### Steps
1. Send a GET request to `http://localhost:3000/api/sync_sessions/999999/status`
   - **Expected:** JSON response with `{ "error": "Session not found" }` and HTTP status 404

### Pass Criteria
- [ ] 404 status returned
- [ ] Error message indicates session not found

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-090: Sync Sessions -- Last Sync Info Card
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** At least one completed sync session exists

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** "Ultima Sincronizacion" card is visible
2. Observe the card content
   - **Expected:** Shows time ago text (e.g., "hace 2 horas") and the number of detected expenses

### Pass Criteria
- [ ] Time ago is displayed correctly
- [ ] Detected expense count is shown

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-091: Sync Sessions -- No Previous Syncs
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** No completed sync sessions exist

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** "Ultima Sincronizacion" card shows "No hay sincronizaciones previas"

### Pass Criteria
- [ ] Empty state text is displayed when no previous syncs exist

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-092: Sync History Table -- Duration Display
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** Completed sync sessions exist with start and end times

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Sync history table visible
2. Observe the "Duracion" column for a completed session
   - **Expected:** Shows human-readable duration (e.g., "menos de un minuto", "2 minutos")
3. Observe the "Duracion" column for a session without start time
   - **Expected:** Shows "-"

### Pass Criteria
- [ ] Duration shows time in Spanish words for completed sessions
- [ ] Dash shown for sessions without timing data

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-093: Sync History Table -- Progress Bar for Active Sessions
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** An active sync session with total_emails > 0 exists

### Steps
1. Navigate to `http://localhost:3000/sync_sessions`
   - **Expected:** Active session row visible in the table
2. Observe the "Emails" column for the active session
   - **Expected:** Shows "X / Y" count with a small inline progress bar

### Pass Criteria
- [ ] Inline progress bar visible for active sessions
- [ ] Progress bar width matches the progress percentage

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-094: Sync Session Rate Limit Error
**Priority:** High
**Feature:** Sync Sessions
**Preconditions:** Sync rate limits are configured; user attempts to create too many sessions

### Steps
1. Create sync sessions rapidly until the rate limit is exceeded
   - **Expected:** At some point, the creation fails
2. Observe the error response
   - **Expected:** Error message about rate limit exceeded or sync limit exceeded

### Pass Criteria
- [ ] Rate limit error is returned when exceeded
- [ ] Error message is user-friendly

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Sync Conflicts

---

## Scenario CD-095: View Sync Conflicts Index
**Priority:** Critical
**Feature:** Sync Conflicts
**Preconditions:** User is logged in; sync conflicts exist in the database

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Page loads with title "Conflictos de Sincronizacion"
2. Observe the header stats
   - **Expected:** Two stat counters: "Pendientes" (teal number) and "Resueltos" (emerald number)
3. Observe the filter bar
   - **Expected:** Filter buttons for "Estado" and "Tipo"; bulk action buttons ("Seleccionar todo", "Resolver seleccionados")
4. Observe the conflicts table
   - **Expected:** Table columns: Checkbox, Tipo, Gastos en Conflicto, Similitud, Estado, Fecha, Acciones

### Pass Criteria
- [ ] Page loads without errors
- [ ] Stats show pending and resolved counts
- [ ] Filters are present
- [ ] Conflict rows are displayed in the table

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-096: Conflict Type Badges
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** Conflicts of various types exist (duplicate, similar, updated, needs_review)

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflicts listed
2. Observe "Tipo" column badges
   - **Expected:**
     - "Duplicado" = rose badge (`bg-rose-100 text-rose-800`)
     - "Similar" = amber badge (`bg-amber-100 text-amber-800`)
     - "Actualizado" = teal badge (`bg-teal-100 text-teal-800`)
     - "Revisar" = slate badge (`bg-slate-100 text-slate-800`)

### Pass Criteria
- [ ] Each conflict type has the correct color badge
- [ ] Badge text matches the conflict type in Spanish

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-097: Conflict Status Badges
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** Conflicts in various statuses exist

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflicts listed
2. Observe "Estado" column badges
   - **Expected:**
     - "Pendiente" = amber badge
     - "Resuelto" = emerald badge
     - "Auto-resuelto" = teal badge
     - "Ignorado" = slate badge

### Pass Criteria
- [ ] Status badges match the expected colors and text

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-098: Conflict Row Shows Both Expenses
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** A conflict with both existing and new expenses exists

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflict rows visible
2. Observe the "Gastos en Conflicto" column for any conflict
   - **Expected:** Shows the existing expense description, amount, and date; followed by "vs." and the new expense description, amount, and date

### Pass Criteria
- [ ] Both existing and new expense details are shown in the row
- [ ] "vs." separator is visible between the two expenses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-099: Similarity Score Display
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** A conflict with a similarity score exists

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflicts listed
2. Observe the "Similitud" column
   - **Expected:** A progress bar with percentage text; colors vary:
     - >= 90%: rose bar
     - >= 70%: amber bar
     - < 70%: teal bar

### Pass Criteria
- [ ] Similarity score progress bar is displayed
- [ ] Percentage text is visible
- [ ] Bar color matches the score threshold

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-100: Resolve Conflict -- Keep Existing
**Priority:** Critical
**Feature:** Sync Conflicts
**Preconditions:** A pending conflict exists

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts/:id` (or click "Resolver" on a pending conflict row)
   - **Expected:** Conflict detail/resolution page or modal opens showing side-by-side comparison
2. Observe the comparison layout
   - **Expected:** Left side (emerald): "Gasto Existente" with details; Right side (amber): "Nuevo Gasto Detectado" with details
3. Observe the differences section
   - **Expected:** If differences exist, a rose panel shows "Diferencias Detectadas" listing each changed field
4. Click the "Mantener Existente" button
   - **Expected:** Conflict is resolved; the existing expense is kept; the new expense is discarded
5. Observe the response
   - **Expected:** Toast notification "Conflicto resuelto exitosamente"; conflict row updates via Turbo Stream

### Pass Criteria
- [ ] Side-by-side comparison shows both expenses
- [ ] Differences are highlighted in rose
- [ ] "Mantener Existente" resolves the conflict
- [ ] Success toast appears
- [ ] Conflict status changes to "resolved"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-101: Resolve Conflict -- Keep New
**Priority:** Critical
**Feature:** Sync Conflicts
**Preconditions:** A pending conflict exists

### Steps
1. Open the conflict resolution view for a pending conflict
   - **Expected:** Side-by-side comparison visible
2. Click the "Mantener Nuevo" button
   - **Expected:** Conflict is resolved; the new expense replaces the existing one
3. Observe the response
   - **Expected:** Success toast "Conflicto resuelto exitosamente"; conflict row updates

### Pass Criteria
- [ ] "Mantener Nuevo" resolves the conflict
- [ ] Existing expense is replaced by the new expense
- [ ] Success notification appears

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-102: Resolve Conflict -- Keep Both
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** A pending conflict exists

### Steps
1. Open the conflict resolution view for a pending conflict
   - **Expected:** Resolution options visible
2. Click the "Mantener Ambos" button
   - **Expected:** Both expenses are kept in the system; conflict is marked as resolved
3. Observe the response
   - **Expected:** Success toast appears

### Pass Criteria
- [ ] Both expenses are preserved
- [ ] Conflict is resolved

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-103: Resolve Conflict -- Merge Fields
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** A pending conflict exists with differences in at least 2 fields

### Steps
1. Open the conflict resolution view
   - **Expected:** Resolution options visible
2. Click "Fusionar Campos" button
   - **Expected:** A merge options section expands below showing radio buttons for each differing field
3. For each differing field, choose either "Existente" or "Nuevo" via radio buttons
   - **Expected:** Radio buttons toggle between existing and new values
4. Click "Aplicar Fusion"
   - **Expected:** Conflict is resolved with merged values; the existing expense is updated with selected field values

### Pass Criteria
- [ ] Merge options section shows for each differing field
- [ ] Radio buttons allow choosing existing or new value per field
- [ ] Submit merges the fields correctly

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-104: Undo Conflict Resolution
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** A resolved conflict exists with undoable resolutions

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflicts listed
2. Locate a resolved conflict that shows "Deshacer" button in the actions column
   - **Expected:** "Deshacer" button is visible (amber colored)
3. Click "Deshacer"
   - **Expected:** A POST request to `/sync_conflicts/:id/undo` is sent
4. Observe the response
   - **Expected:** Conflict returns to pending/unresolved state; Turbo Stream updates the row; toast "Resolucion deshecha" appears

### Pass Criteria
- [ ] Undo button is visible for resolvable conflicts
- [ ] Undo reverts the conflict to unresolved state
- [ ] Row updates via Turbo Stream
- [ ] Toast notification appears

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-105: Conflict Resolution History
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** A conflict has been resolved (and optionally undone) creating resolution history

### Steps
1. Navigate to `/sync_conflicts/:id` for a conflict with resolution history
   - **Expected:** Conflict detail page loads
2. Observe the "Historial de Resoluciones" section
   - **Expected:** A list of past resolutions showing: date/time, action taken, and "(Deshecho)" tag if the resolution was undone

### Pass Criteria
- [ ] Resolution history section is visible
- [ ] Each resolution entry shows timestamp and action
- [ ] Undone resolutions are marked with "(Deshecho)"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-106: Bulk Resolve Conflicts
**Priority:** High
**Feature:** Sync Conflicts
**Preconditions:** Multiple pending conflicts exist

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Conflicts listed with checkboxes
2. Check the checkboxes on 3 pending conflicts
   - **Expected:** Checkboxes become checked
3. Observe the bulk action area
   - **Expected:** "Resolver seleccionados" button becomes visible and enabled
4. Click "Resolver seleccionados"
   - **Expected:** A POST to `/sync_conflicts/bulk_resolve` is sent with selected conflict IDs
5. Observe the response
   - **Expected:** All selected conflicts are resolved; rows update via Turbo Stream; toast shows "N conflictos resueltos"

### Pass Criteria
- [ ] Multiple conflicts can be selected
- [ ] Bulk resolve processes all selected conflicts
- [ ] Toast notification shows count of resolved conflicts
- [ ] Rows update individually via Turbo Stream

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-107: Select All Conflicts Checkbox
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** Multiple conflicts exist

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts`
   - **Expected:** Table header has a "select all" checkbox
2. Click the "Seleccionar todo" button or the header checkbox
   - **Expected:** All conflict checkboxes become checked

### Pass Criteria
- [ ] Select all checks all conflict checkboxes
- [ ] Bulk resolve button becomes enabled

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-108: Preview Merge via API
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** A pending conflict exists

### Steps
1. Send a POST request to `/sync_conflicts/:id/preview_merge` with `merge_fields` parameter
   - **Expected:** JSON response with `success: true`, `preview` (merged expense data), and `changes` (field-level change details)

### Pass Criteria
- [ ] Preview returns merged data without modifying the database
- [ ] Changes object lists from/to values for each changed field

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-109: Filter Conflicts by Status
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** Conflicts in both pending and resolved status exist

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts?status=pending`
   - **Expected:** Only pending conflicts are shown
2. Navigate to `http://localhost:3000/sync_conflicts?status=resolved`
   - **Expected:** Only resolved conflicts are shown
3. Navigate to `http://localhost:3000/sync_conflicts` (no filter)
   - **Expected:** All conflicts are shown

### Pass Criteria
- [ ] Status filter correctly limits displayed conflicts
- [ ] Stats reflect the filtered set

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-110: Filter Conflicts by Type
**Priority:** Medium
**Feature:** Sync Conflicts
**Preconditions:** Conflicts of different types exist

### Steps
1. Navigate to `http://localhost:3000/sync_conflicts?type=duplicate`
   - **Expected:** Only duplicate-type conflicts are shown
2. Navigate to `http://localhost:3000/sync_conflicts?type=similar`
   - **Expected:** Only similar-type conflicts are shown

### Pass Criteria
- [ ] Type filter correctly limits displayed conflicts
- [ ] Only conflicts matching the type are shown

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Undo History

---

## Scenario CD-111: Undo Notification Appears After Delete
**Priority:** Critical
**Feature:** Undo History
**Preconditions:** User is logged in; an expense exists

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Dashboard with expenses
2. Delete an expense (click delete, confirm)
   - **Expected:** Expense is removed from the list
3. Observe the bottom of the viewport
   - **Expected:** An undo notification slides in from the bottom with: trash icon, message about the deleted expense, "Deshacer" button, dismiss X button, and a countdown progress bar

### Pass Criteria
- [ ] Undo notification appears after deletion
- [ ] Notification has "Deshacer" button
- [ ] Countdown progress bar is visible
- [ ] Timer text shows remaining time with "para deshacer" label

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-112: Click Undo Restores Deleted Expense
**Priority:** Critical
**Feature:** Undo History
**Preconditions:** An expense was just deleted; undo notification is visible

### Steps
1. After deleting an expense, observe the undo notification
   - **Expected:** "Deshacer" button is visible and clickable
2. Click the "Deshacer" button
   - **Expected:** A POST request is sent to `/undo_histories/:id/undo`
3. Observe the expense list
   - **Expected:** The deleted expense is restored and reappears in the list; the undo notification disappears
4. Observe the response
   - **Expected:** Success response with message "Accion deshecha exitosamente"

### Pass Criteria
- [ ] Clicking undo restores the deleted expense
- [ ] Expense reappears in the list
- [ ] Undo notification disappears after clicking
- [ ] No errors in the console

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-113: Undo Notification Countdown Timer
**Priority:** High
**Feature:** Undo History
**Preconditions:** An expense was just deleted; undo notification is visible

### Steps
1. After deleting an expense, observe the undo notification
   - **Expected:** A countdown timer is visible showing remaining seconds
2. Observe the progress bar
   - **Expected:** Progress bar decreases over time from full to empty
3. Wait for the countdown to reach zero
   - **Expected:** The undo notification automatically dismisses/disappears

### Pass Criteria
- [ ] Countdown timer displays and decrements
- [ ] Progress bar animates downward
- [ ] Notification auto-dismisses when timer expires

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-114: Dismiss Undo Notification via X Button
**Priority:** Medium
**Feature:** Undo History
**Preconditions:** Undo notification is visible

### Steps
1. After deleting an expense, observe the undo notification
   - **Expected:** X dismiss button is visible in the notification
2. Click the X button
   - **Expected:** Notification dismisses immediately; the deletion is finalized

### Pass Criteria
- [ ] X button dismisses the notification
- [ ] Deletion is not undone

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-115: Undo After Timer Expires -- Not Undoable
**Priority:** High
**Feature:** Undo History
**Preconditions:** An expense was deleted and the undo timer has expired

### Steps
1. Delete an expense and let the undo notification timer expire completely
   - **Expected:** Notification disappears
2. Attempt to undo via API: POST `/undo_histories/:id/undo`
   - **Expected:** Response returns `{ success: false, message: "Esta accion ya no se puede deshacer" }` with status 422

### Pass Criteria
- [ ] Expired undo operations return error
- [ ] Message indicates the action can no longer be undone

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-116: Undo Notification Accessibility
**Priority:** Medium
**Feature:** Undo History
**Preconditions:** Undo notification is visible

### Steps
1. Delete an expense to trigger the undo notification
   - **Expected:** Notification appears
2. Inspect the notification HTML
   - **Expected:** The notification container has `role="alert"` and `aria-live="polite"` attributes
3. Inspect the undo button
   - **Expected:** Has `aria-label="Deshacer eliminacion"`
4. Inspect the dismiss button
   - **Expected:** Has `aria-label="Cerrar notificacion"`

### Pass Criteria
- [ ] `role="alert"` is present on the notification container
- [ ] `aria-live="polite"` is present
- [ ] Both buttons have descriptive `aria-label` attributes

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-117: Undo for Non-Existent Record
**Priority:** Medium
**Feature:** Undo History
**Preconditions:** No undo history record with ID 999999 exists

### Steps
1. Send a POST request to `/undo_histories/999999/undo`
   - **Expected:** JSON response with `{ success: false, message: "Undo record not found" }` and HTTP status 404

### Pass Criteria
- [ ] 404 status returned
- [ ] Error message indicates record not found

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario CD-118: Undo After Bulk Delete
**Priority:** High
**Feature:** Undo History
**Preconditions:** User just performed a bulk delete of multiple expenses

### Steps
1. Select 3 expenses and perform a bulk delete via the bulk operations modal
   - **Expected:** All 3 expenses are deleted; an undo notification may appear
2. If an undo notification appears, click "Deshacer"
   - **Expected:** All 3 deleted expenses are restored
3. Observe the expense list
   - **Expected:** All 3 expenses reappear in the list
4. Observe the response
   - **Expected:** `affected_count` matches the number of restored expenses (3)

### Pass Criteria
- [ ] Bulk delete creates an undoable operation
- [ ] Undo restores all deleted expenses
- [ ] Affected count matches the number of deleted expenses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Summary

| Section | Scenario Range | Count |
|---------|---------------|-------|
| Batch Selection & Bulk Operations | CD-001 to CD-024 | 24 |
| ML Categorization Inline Actions | CD-025 to CD-042 | 18 |
| Bulk Categorization Workflow | CD-043 to CD-060 | 18 |
| Email Accounts | CD-061 to CD-074 | 14 |
| Sync Sessions | CD-075 to CD-094 | 20 |
| Sync Conflicts | CD-095 to CD-110 | 16 |
| Undo History | CD-111 to CD-118 | 8 |
| **Total** | | **118** |
