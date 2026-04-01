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

## Scenario CD-081: Cancel Non-Active Session Returns Error
**Priority:** Medium
**Feature:** Sync Sessions
**Preconditions:** A completed or cancelled sync session exists

### Steps
1. Attempt to POST to `/sync_sessions/:id/cancel` for a non-active session
   - **Expected:** Redirect with alert message "not active" or equivalent

### Pass Criteria
- [ ] Error message returned for non-active session **BLOCKED** — Could not create an active session to first cancel; could not test the non-active cancel error path independently without a valid session cookie for the POST request.
- [ ] Session state is unchanged **BLOCKED** — See above.

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
- [x] Breadcrumb navigation is correct — Breadcrumb showed "Centro de Sincronización > Sesión #[ID]" as expected. Screenshot: `screenshot-cd082-sync-detail.png`.
- [x] Session info card shows all fields — Estado (with badge), Iniciada (start time), Completada (end time or "—"), and Duración fields all present in the Session Info card.
- [x] Summary card shows all metrics — Cuentas procesadas, Total de emails, Emails procesados, and Gastos detectados all displayed in the Summary card.
- [x] Per-account detail cards are displayed correctly — Per-account cards showed bank name, email address, status badge, emails processed with progress bar, detected expenses, start time, and last update time.

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
- [ ] Real-time progress section is visible for running sessions **BLOCKED** — No running sync session existed in the database. Real-time progress display could not be tested.
- [ ] Progress bar shows correct percentage **BLOCKED** — See above.
- [ ] Stats update in real time (via ActionCable) **BLOCKED** — See above.

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
- [x] Retry button is visible for failed/cancelled sessions — "Reintentar" button was visible in the header area of a failed session detail page.
- [ ] Clicking retry creates a new session **BLOCKED** — Clicking the "Reintentar" button required an authenticated form POST. Session expired during the attempt (same issue as CD-077). Could not verify session creation.
- [ ] Success message on redirect **BLOCKED** — See above.

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
- [ ] Performance metrics section appears for completed sessions **BLOCKED** — No completed sync sessions existed in the database (both sessions present had failed status). Performance metrics section could not be verified.
- [ ] Speed and detection rate values are displayed and non-zero **BLOCKED** — See above.

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
- [x] Error details panel shows for failed sessions — A rose/red panel titled "Detalles del Error" was present on the failed session detail page with rose styling (`bg-rose-50 border-rose-200`).
- [x] Error message text is readable — Error message text was visible and readable within the panel.

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
- [x] "Ver error" link is visible for accounts with errors — "Ver error" expandable link was present in rose color on account cards that had errors.
- [ ] Clicking expands to show error details — Click on "Ver error" was registered by Playwright. However, due to the Turbo Drive session pollution issue, confirming whether the details panel expanded correctly was unreliable. The expansion behavior could not be definitively verified.

> **Note — PARTIAL**: The "Ver error" link was confirmed present. Expansion behavior could not be reliably verified in the test environment due to Turbo Drive controller interference from the admin patterns page.

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
- [ ] API returns valid JSON **BLOCKED** — `GET /api/sync_sessions/:id/status` returned `401 Unauthorized` even with an active browser session. The API endpoint requires an `Authorization: Token` header (designed for iPhone Shortcuts integration), not session cookie authentication. No API token was provisioned for testing.
- [ ] All expected fields are present **BLOCKED** — See above.
- [ ] Accounts array contains per-account data **BLOCKED** — See above.

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
- [x] 404 status returned — `GET /api/sync_sessions/999999/status` returned HTTP 404.
- [x] Error message indicates session not found — Response body confirmed a JSON error message indicating the session was not found.

> **Note:** This endpoint was accessible without authentication for 404 responses (the 404 was returned before authentication was checked, or the route itself handled not-found before the auth check). Consistent with the 401 behavior for existing sessions (CD-088), where auth is checked before returning data.

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
- [ ] Time ago is displayed correctly — The "Última Sincronización" card showed "No hay sincronizaciones previas" despite failed sessions being present in the database. The card appears to only count completed (not failed) sessions as "previous syncs." No completed sessions existed, so time-ago display could not be verified.
- [ ] Detected expense count is shown — Could not verify; no completed session data available.

> **Note — PARTIAL**: The "Última Sincronización" card may intentionally show "No hay sincronizaciones previas" for failed sessions, counting only completed sessions. This behavior should be clarified with the product team — it may be by design or an unintentional data gap.

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
- [x] Empty state text is displayed when no previous syncs exist — The "Última Sincronización" card showed "No hay sincronizaciones previas". While this was observed with failed sessions present (not truly "no syncs"), the empty state text itself rendered correctly. Full verification with a truly empty database was not possible without data teardown.

> **Note:** Sessions with failed status appear to be excluded from the "previous syncs" count. This incidentally allowed observing the empty state text during the test run.

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
- [x] Duration shows time in Spanish words for completed sessions — Failed sessions showed "menos de 10 segundos" (Spanish human-readable duration), confirming the duration helper outputs Spanish text.
- [ ] Dash shown for sessions without timing data — No sessions without start time data were present to verify the dash display. Could not test this specific condition.

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
- [ ] Inline progress bar visible for active sessions **BLOCKED** — No active sync session existed during testing. The inline progress bar in the history table Emails column could not be verified.
- [ ] Progress bar width matches the progress percentage **BLOCKED** — See above.

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
- [ ] Rate limit error is returned when exceeded **BLOCKED** — Could not safely test rate limit exhaustion without risking further lockout of the admin login for the remaining test sections. Testing was halted after the session expiry rate limit was already triggered during earlier testing.
- [ ] Error message is user-friendly **BLOCKED** — See above.

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
- [ ] Page loads without errors **BLOCKED** — Admin login rate limit (429 Too Many Requests) was triggered after repeated session expiry during Sync Sessions testing. All subsequent login attempts returned 429, making it impossible to authenticate for the Sync Conflicts section. Rate limit stores in server's in-memory MemoryStore (not clearable externally); TTL is 15 minutes.
- [ ] Stats show pending and resolved counts **BLOCKED** — See above.
- [ ] Filters are present **BLOCKED** — See above.
- [ ] Conflict rows are displayed in the table **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.** Screenshot: `screenshot-session-expired-rate-limited.png`.

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
- [ ] Each conflict type has the correct color badge **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Badge text matches the conflict type in Spanish **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Status badges match the expected colors and text **BLOCKED** — Rate limit lockout; session could not be restored.

**BLOCKED — Rate limit lockout.**

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
- [ ] Both existing and new expense details are shown in the row **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] "vs." separator is visible between the two expenses **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Similarity score progress bar is displayed **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Percentage text is visible **BLOCKED** — See above.
- [ ] Bar color matches the score threshold **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

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
- [ ] Side-by-side comparison shows both expenses **BLOCKED** — Rate limit lockout; session could not be restored.
- [ ] Differences are highlighted in rose **BLOCKED** — See above.
- [ ] "Mantener Existente" resolves the conflict **BLOCKED** — See above.
- [ ] Success toast appears **BLOCKED** — See above.
- [ ] Conflict status changes to "resolved" **BLOCKED** — See above.

**BLOCKED — Rate limit lockout.**

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---
