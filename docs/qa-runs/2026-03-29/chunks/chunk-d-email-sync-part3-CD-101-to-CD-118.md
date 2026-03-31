# QA Playbook — Group D: Email Accounts, Sync Sessions, Sync Conflicts, Undo History

---

## Results Summary

**Run Date:** 2026-03-27
**Tester:** QA Agent (Playwright automation)
**Environment:** http://localhost:3000 | Rails 8.1.2 development server

| Section | Total | Pass | Fail | Blocked |
|---------|-------|------|------|---------|
| Email Accounts (CD-061 to CD-074) | 14 | 10 | 2 | 2 |
| Sync Sessions (CD-075 to CD-094) | 20 | 5 | 2 | 13 |
| Sync Conflicts (CD-095 to CD-110) | 16 | 0 | 0 | 16 |
| Undo History (CD-111 to CD-118) | 8 | 0 | 0 | 8 |
| **Total** | **58** | **15** | **4** | **39** |

---

## Run 2 — Targeted Fix Validation

**Run Date:** 2026-03-29
**Tester:** QA Agent (Playwright automation)
**Environment:** http://localhost:3000 | Rails 8.1.2 development server
**Purpose:** Validate three specific fixes: PER-191 (i18n translations), PER-213 (session expiry), PER-231 (select all checkboxes)

### Run 2 Results Summary

| Fix | Ticket | Result | Notes |
|-----|--------|--------|-------|
| i18n — Sync status badges in Spanish | PER-191 | **PASS** | "Fallido", "Cancelado", "Completado", "En ejecución" all display in Spanish |
| i18n — Provider name "Personalizado" | PER-191 | **PASS** | Show page displays "Personalizado" instead of "Custom" |
| i18n — Provider name in form dropdown | PER-191 | **PASS** | Dropdown shows "Personalizado" option (not "Custom") |
| i18n — Account status "Activa"/"Inactiva" | PER-191 | **PASS** (no change) | Already passing in Run 1; confirmed still passing |
| Session expiry on navigation | PER-213 | **FAIL** | Session still expires mid-interaction. "Tu sesión ha expirado" flash messages observed on dashboard. Session lost after ERR_ABORTED navigations and mid-test interactions. Account lockout cascade (failed_login_attempts hitting threshold) also still occurring, requiring manual DB reset to continue testing. |
| Select all checkboxes | PER-231 | **PARTIAL / INCONCLUSIVE** | "Selección Múltiple" button present on `/expenses` page. Individual row checkboxes visible in screenshot. Could not complete the full select-all interaction due to Turbo Drive pollution (Bug #1) intercepting clicks and redirecting to unintended pages. The select-all header checkbox was NOT found via `input[type="checkbox"]` query, suggesting it may be a custom element — further investigation needed outside this Turbo-polluted context. |

### Run 2 — Key Observations

#### PER-191 (i18n) — VALIDATED PASS
Sync session status badges that previously showed "Failed" in English now show Spanish equivalents in the history table:
- "Fallido" (failed) — rose/red badge — confirmed via CD-076 observations on `/sync_sessions`
- "Cancelado" (cancelled) — amber badge — new data available (session 4 exists)
- "Completado" (completed) — emerald badge — new data available (session 3 exists)
- "En ejecución" (running) — teal badge — visible in active session section and history table

Provider names also fixed:
- Form dropdown: "Personalizado" (not "Custom")
- Show page: "Personalizado" (not "Custom") — verified by creating test account (ID 7) with `provider: 'custom'`

#### PER-213 (Session Expiry) — STILL FAILING
Session expiry is NOT fixed. Observed in two distinct ways:
1. Direct evidence: "Tu sesión ha expirado. Por favor, recarga la página." flash appeared on the dashboard during active testing
2. Indirect evidence: Account lockout (AdminUser `locked_at` set) occurred at least twice during this run due to repeated failed login attempts triggered by session expiry redirects — required manual `update_columns(failed_login_attempts: 0, locked_at: nil)` to continue. The Rails server also crashed once mid-session (net::ERR_CONNECTION_REFUSED), likely due to memory pressure from session handling.
3. The Rack::Attack `logins/ip` throttle (5 per 20 seconds) is conflicting with automated re-login attempts after session expiry, creating a lockout cascade that blocks further testing.

#### PER-231 (Select All Checkboxes) — PARTIALLY TESTED
Testing was severely impacted by Bug #1 (Turbo Drive pollution from admin/patterns). Findings:
- "Selección Múltiple" button IS present on `/expenses` page
- Individual row checkboxes ARE visible in viewport screenshots
- The button click via `browser_click` triggered unintended navigation (to `/expenses/dashboard`)
- When click was executed via `window.location.assign` + JS evaluate, the page loaded but the "select all" header checkbox was not found as `input[type="checkbox"]` — it may be a Stimulus-controlled element or custom div
- "Operaciones en Lote | Limpiar selección | Cancelar | Ejecutar" buttons were found in DOM after clicking "Selección Múltiple" via JS, suggesting the mode DID activate — but the select-all checkbox specifically could not be verified
- **Recommendation**: Test PER-231 in isolation from a fresh browser session that never visits `/admin/patterns` first

### Run 2 — Remaining Open Bugs (unchanged from Run 1)

1. **[BUG — CRITICAL] Turbo Drive navigation pollution from admin/patterns** — STILL PRESENT. Every Playwright interaction that starts from admin/patterns (post-login) corrupts Turbo navigation context. The `pattern_form_controller` intercepts form submissions and keyboard inputs across all subsequent pages. This blocks testing of PER-231 and form submission tests.

2. **[BUG — HIGH] Session expires aggressively (PER-213)** — STILL PRESENT, NOT FIXED by the targeted fix. Session expiry occurs during Turbo interactions and causes account lockout cascade when combined with Rack::Attack throttling.

3. **[BUG — MEDIUM] Validation error messages "Provider" and "Bank name" field labels in English** — NOT RETESTED this run due to Turbo form submission being intercepted. Still assumed to be present based on Run 1 findings (not part of PER-191 targeted fix).

4. **[BUG — MEDIUM] CD-065 validation redirect to index instead of re-rendering form** — NOT RETESTED this run.

5. **[BUG — LOW] CD-064 redirect to index not show page** — NOT RETESTED this run.

### Run 2 — New Data Available

A completed sync session (ID 3, 30 minutes duration, "Completado") and a cancelled sync session (ID 4, "Cancelado") now exist in the database. This unlocks several previously blocked scenarios for Run 3:
- CD-076: Completed and cancelled badge colors can now be verified
- CD-085: Performance metrics for completed session (session 3 has 15 emails processed, 5 expenses)
- CD-090: "Última Sincronización" card time-ago display (session 3 is the last completed)
- CD-092: Duration display for completed sessions
- CD-084: Retry button for cancelled session (session 4)

### Run 2 — Test Cleanup Note

Created test EmailAccount (ID 7): `test-custom-per191@test.com` / BCR / custom provider — used to verify PER-191 "Personalizado" display. Should be removed after testing if database cleanliness is required.

### Critical Issues Found

1. **[BUG — CRITICAL] Turbo Drive navigation pollution from admin/patterns controllers**: When navigating from `/admin/patterns` to `/email_accounts/new`, Stimulus controllers from the patterns page persist across Turbo navigation. The `pattern_form_controller` fires `change->pattern-form#updateValueHelp` events on this unrelated page. Typing into the email input triggers a form submission to `/admin/patterns` (422) which then navigates the page to `/expenses/dashboard` or other pages. The email field on the new account form is **completely unusable via keyboard input through the normal Turbo navigation flow**. Reproduction: log in via admin login, navigate to `/email_accounts/new`, type in the email field. **Workaround for testing:** open a fresh browser tab (new page context) and disable Turbo before filling.

2. **[BUG — HIGH] Session expires aggressively during Turbo form submissions**: Session is lost when a Turbo form submission triggers certain navigation paths. Multiple test runs showed sessions expiring without explicit logout. Compounded by the rate limiter on admin login (10 attempts / 15 minutes per IP using in-memory MemoryStore), which blocks retesting when sessions expire during automated runs.

3. **[BUG — MEDIUM] Validation error messages partially in English**: When submitting the empty email account form, validation messages include "Provider no puede estar en blanco" and "Bank name no puede estar en blanco" — "Provider" and "Bank name" are not translated to Spanish. Expected: "Proveedor no puede estar en blanco" and "Nombre del banco no puede estar en blanco".

4. **[BUG — MEDIUM] Provider displayed as "Custom" instead of "Personalizado"**: The show page for an email account with provider `custom` displays "Custom" (English) instead of "Personalizado" (Spanish). Affects CD-066.

5. **[BUG — MEDIUM] Validation errors redirect to index instead of re-rendering form**: When submitting empty email account form (CD-065), the expected behavior is a 422 response re-rendering the form at `/email_accounts/new`. Actual behavior: redirects to `/email_accounts` (index page) while showing error messages. The URL does not remain on the form page.

6. **[BUG — LOW] CD-064 redirects to index not show page**: After creating an email account, the expected redirect is to `/email_accounts/:id` (show page). Actual: redirects to `/email_accounts` (index). Flash message "Cuenta de correo actualizada exitosamente" appears correctly. Account IS created.

7. **[BUG — LOW] Sync session status badges display "Failed" in English**: Status badges in the sync history table show "Failed" instead of a Spanish equivalent. The color scheme (rose/red for failed) is correct per spec.

8. **[BLOCKED] API sync status endpoint requires API token**: `GET /api/sync_sessions/:id/status` returns 401 Unauthorized even with an active browser session. The API requires an `Authorization: Token` header (iPhone Shortcuts integration design). All CD-088 API tests require pre-configured API token — marked BLOCKED.

9. **[BLOCKED] Sync Conflicts and Undo History**: All 24 scenarios for these sections could not be executed due to admin login rate limit (429 Too Many Requests) triggered by repeated session expiry during testing. The rate limit is 10 attempts per 15 minutes stored in server's MemoryStore (not clearable from rails runner).

### Observations

- CD-062 (empty state): Only 2 email accounts existed at start; created test accounts during testing. CD-062 is BLOCKED as it requires a clean state with zero accounts.
- CD-091 (no previous syncs card): The "Última Sincronización" card shows "No hay sincronizaciones previas" even when failed sessions exist. Appears to only count completed sessions, which may be by design but was not clarified in the playbook.
- CD-085 (performance metrics): Not tested — no completed sync sessions exist (both are failed). BLOCKED.
- CD-092 (duration display): Confirmed from CD-075 — sessions show "menos de 10 segundos" for failed sessions. Duration column appears to work.
- Screenshots saved: `screenshot-cd064-email-form.png`, `screenshot-cd064-after-submit.png`, `screenshot-cd065-validation.png`, `screenshot-cd075-sync-index.png`, `screenshot-cd082-sync-detail.png`, `screenshot-cd077-sync-start.png`, `screenshot-session-expired-rate-limited.png`

---

## Email Accounts

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
- [ ] "Mantener Nuevo" resolves the conflict **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Existing expense is replaced by the new expense **BLOCKED** — See above.
- [ ] Success notification appears **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Both expenses are preserved **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Conflict is resolved **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Merge options section shows for each differing field **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Radio buttons allow choosing existing or new value per field **BLOCKED** — See above.
- [ ] Submit merges the fields correctly **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Undo button is visible for resolvable conflicts **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Undo reverts the conflict to unresolved state **BLOCKED** — See above.
- [ ] Row updates via Turbo Stream **BLOCKED** — See above.
- [ ] Toast notification appears **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Resolution history section is visible **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Each resolution entry shows timestamp and action **BLOCKED** — See above.
- [ ] Undone resolutions are marked with "(Deshecho)" **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Multiple conflicts can be selected **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Bulk resolve processes all selected conflicts **BLOCKED** — See above.
- [ ] Toast notification shows count of resolved conflicts **BLOCKED** — See above.
- [ ] Rows update individually via Turbo Stream **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Select all checks all conflict checkboxes **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Bulk resolve button becomes enabled **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Preview returns merged data without modifying the database **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Changes object lists from/to values for each changed field **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Status filter correctly limits displayed conflicts **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Stats reflect the filtered set **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Type filter correctly limits displayed conflicts **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Only conflicts matching the type are shown **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Undo notification appears after deletion **BLOCKED** — Admin login rate limit (429 Too Many Requests) was in effect. Could not log in to access the expense dashboard for this test section.
- [ ] Notification has "Deshacer" button **BLOCKED** — See above.
- [ ] Countdown progress bar is visible **BLOCKED** — See above.
- [ ] Timer text shows remaining time with "para deshacer" label **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Clicking undo restores the deleted expense **BLOCKED** — Rate limit lockout; could not access the application.
- [ ] Expense reappears in the list **BLOCKED** — See above.
- [ ] Undo notification disappears after clicking **BLOCKED** — See above.
- [ ] No errors in the console **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Countdown timer displays and decrements **BLOCKED** — Rate limit lockout; could not access the application.
- [ ] Progress bar animates downward **BLOCKED** — See above.
- [ ] Notification auto-dismisses when timer expires **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] X button dismisses the notification **BLOCKED** — Rate limit lockout; could not access the application.
- [ ] Deletion is not undone **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Expired undo operations return error **BLOCKED** — Rate limit lockout; could not access the application. Could not create a deletion to trigger and then expire the undo timer.
- [ ] Message indicates the action can no longer be undone **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] `role="alert"` is present on the notification container **BLOCKED** — Rate limit lockout; could not access the application to trigger the undo notification.
- [ ] `aria-live="polite"` is present **BLOCKED** — See above.
- [ ] Both buttons have descriptive `aria-label` attributes **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] 404 status returned **BLOCKED** — Rate limit lockout; could not obtain an authenticated session to make requests to the undo_histories endpoint (requires session authentication).
- [ ] Error message indicates record not found **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Bulk delete creates an undoable operation **BLOCKED** — Rate limit lockout; could not access the application to perform a bulk delete.
- [ ] Undo restores all deleted expenses **BLOCKED** — See above.
- [ ] Affected count matches the number of deleted expenses **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
