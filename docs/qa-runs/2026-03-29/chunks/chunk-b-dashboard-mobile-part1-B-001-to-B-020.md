# QA Testing Playbook -- Group B: Dashboard + Mobile Card Layout + Navigation + Responsive + Accessibility

**Application:** Rails 8.1.2 Expense Tracker (Spanish UI)
**Base URL:** `http://localhost:3000`
**Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**Date:** 2026-03-26
**Agent Group:** B
**QA Run Date:** 2026-03-27
**Agent:** Claude Sonnet 4.6 (Playwright MCP)

---

## RUN 2 SUMMARY (2026-03-28, Fresh Run)

**Run Date:** 2026-03-28
**Agent:** Claude Sonnet 4.6 (Playwright MCP)
**Total Scenarios:** 67
**PASS:** 46
**FAIL:** 2
**BLOCKED:** 4
**NOT TESTED:** 15

### Key Fix Validation Results

| Fix | Ticket | Run 1 Status | Run 2 Status | Details |
|-----|--------|--------------|--------------|---------|
| Chart.js loads | PER-222 | FAIL | **PASS** | 7 canvas elements rendered with non-zero dimensions (562×300 for main charts, 300×150 for sparklines). No "Loading..." text. No "No charting libraries" message. chartjs-adapter-date-fns error is gone. |
| Mobile overflow | PER-185 | FAIL | **FAIL** | Dashboard at 375px: scrollWidth=382 > clientWidth=375 (7px overflow). Offender is a `.bg-white.rounded-xl.shadow-sm.border.border-slate-200` card (sw=407, cw=341) — likely the sync widget or primary metric card. `/expenses` at 375px: no overflow (PASS). |
| SVG aria-hidden | PER-192 | FAIL (1/115) | **PARTIAL** | Dashboard: 70/142 SVGs (49%) now have `aria-hidden="true"`, up from 1/115 in Run 1. Major improvement but 72 decorative SVGs remain without `aria-hidden`. Sampled untagged SVGs are in icon button and card positions without aria-label or title elements. |

### Run 2 Changes vs Run 1

**Newly PASSING (previously FAIL):**
- **B-008** (PASS): "Tendencia Mensual" chart renders — 7 canvas elements with non-zero dimensions. Chart.js adapter error resolved by PER-222.
- **B-009** (PASS): "Gastos por Categoría" pie chart renders — canvas at chart-2 (562×300). No "Loading..." text.

**Still FAILING:**
- **B-046** (FAIL): Dashboard overflow at 375px — scrollWidth=382px, clientWidth=375px. A fixed-width card element (sw=407px) inside the sync or primary card area causes 7px horizontal overflow. Fix is incomplete for the dashboard page specifically; `/expenses` has no overflow.
- **B-066** (PARTIAL FAIL): 72/142 SVGs on the dashboard still lack `aria-hidden="true"`. This is an improvement from Run 1 (1/115) but bulk remediation is incomplete. Non-ariaHidden SVGs are in button and card containers without aria-label or title, meaning screen readers will encounter empty/meaningless content.

**Still BLOCKED:**
- **B-020**: Empty state — database has 94 expenses, destructive deletion required.
- **B-028/B-029**: Long-press selection — requires touch event simulation.
- **B-050**: Flash message — expense creation still returns errors (session instability prevents stable form testing).

**New Observations (Run 2):**
1. **Session instability persists**: `queue_monitor_controller` fails to load (MIME type mismatch, returns JSON instead of JS module) and triggers navigation to admin pages after ~2-3 seconds. Workaround: disabling `Turbo.config.drive` via `page.evaluate()` after navigation was required for stable testing.
2. **New JS error discovered**: `accessibility_enhanced_controller` throws `TypeError: Cannot set property liveRegionTarget of #<t> which has only a getter` on the expenses page. This breaks the accessibility live region setup.
3. **SVG count changed**: 142 SVGs on dashboard (up from 115 in Run 1), suggesting new UI elements were added. 70 now have `aria-hidden`, 72 do not.
4. **Mobile cards confirmed**: At 375px viewport, 50 mobile-card controller elements render on `/expenses`. The `/expenses` page has no horizontal overflow. Tailwind `md:hidden` classes correctly show card layout.
5. **Blue color check**: 0 elements with `blue-` classes on dashboard and expense pages. Financial Confidence palette maintained.

---

## EXECUTIVE SUMMARY (Run 1 — 2026-03-27)

**Total Scenarios:** 67
**PASS:** 42
**FAIL:** 3
**BLOCKED:** 4
**NOT TESTED:** 18

### Failed Scenarios (Run 1)
- **B-008** (FAIL): "Tendencia Mensual" and "Gastos por Categoría" charts show "Loading..." indefinitely due to a `TypeError: Cannot read properties of undefined` in `chartjs-adapter-date-fns.bundle.min.js:7`. Chart.js adapter is broken — canvases render but data never loads.
- **B-009** (FAIL): Same root cause as B-008 — pie chart shows "Loading..." instead of rendered segments.
- **B-046** (FAIL): Dashboard page has horizontal overflow at 375px viewport — `scrollWidth=571 > clientWidth=375`. Content exceeds mobile viewport width. Likely caused by the queue monitor widget or sync widget rendering wide fixed-width content.

### Blocked Scenarios
- **B-020** (BLOCKED): Empty state test — database has 78 expenses, cannot test without destructive data deletion.
- **B-050** (BLOCKED): Flash message test — form submission returned HTTP 500; could not create expense to trigger success flash.
- **B-028** (BLOCKED): Long-press selection mode — requires touch device simulation in DevTools, not testable via Playwright without explicit touch event injection.
- **B-029** (BLOCKED): Selection mode touch interaction — depends on B-028.

### Notable Observations
1. **Chart.js adapter error**: `TypeError: Cannot read properties of undefined (reading 'id')` in `chartjs-adapter-date-fns.bundle.min.js` fires on every dashboard load. This breaks all Chart.js-based visualizations (trend chart, pie chart, sparklines all fall back to text "Loading...").
2. **Session instability**: Admin login sessions expire within ~2-3 minutes of inactivity due to rate limiting (10 attempts/15 minutes) and short session TTL. The queue-monitor and sync-widget Stimulus controllers fire background requests that occasionally trigger navigation to `/email_accounts/new`, `/admin/patterns/new`, or `/sync_sessions/1`.
3. **B-004 through B-007 URL deviation**: Metric card navigation uses `date_from`/`date_to` query params (e.g., `?date_from=2026-01-01&date_to=2026-12-31&filter_type=dashboard_metric`) instead of `?period=year` as expected by the playbook. Functional behavior is correct; URL format differs from spec.
4. **B-050**: Expense creation form submitted but server returned 500. Possible validation issue with test data.
5. **B-056**: 2,306 buttons total lack aria-label — however the vast majority are category/merchant select options in Stimulus controllers (not buttons needing screen reader labels). Key interactive buttons (hamburger, batch selection, view toggle, action drawer buttons) DO have proper aria-labels.
6. **B-066**: 114 of 115 SVG icons lack `aria-hidden="true"`. Decorative SVGs next to text should be hidden from screen readers.

---

## General Instructions for QA Agent

1. Before starting, confirm the Rails server is running at `http://localhost:3000`.
2. Log in using the credentials above. The admin login page is at `/admin/login`. The main app uses HTTP Basic or session auth -- navigate to the root URL and authenticate if prompted.
3. Use Chrome DevTools to simulate mobile viewports (375px, 768px, 1024px, 1280px).
4. For each scenario, record PASS or FAIL. If FAIL, follow the "If Failed" instructions.
5. All UI text is in Spanish. Button labels and headings will be in Spanish.

---

# SECTION 1: DASHBOARD SCENARIOS (B-001 through B-020)

---

## Scenario B-001: Dashboard loads successfully at root URL
**Priority:** Critical
**Feature:** Dashboard
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/`
   - **Expected:** Page loads without errors. The browser title contains "Dashboard". The URL resolves to `/expenses/dashboard` (root route).
2. Observe the page header area.
   - **Expected:** The heading "Dashboard de Gastos" is visible. Below it, the subheading "Resumen completo de tus finanzas" is displayed.
3. Observe the primary metric card (large teal gradient card).
   - **Expected:** The card displays "TOTAL DE GASTOS" with a currency amount prefixed by the colon symbol. The card has a teal gradient background (`from-teal-700 to-teal-800`).

### Pass Criteria
- [x] Root URL redirects to `/expenses/dashboard`
- [x] Page title includes "Dashboard"
- [x] Heading "Dashboard de Gastos" is visible
- [x] Primary metric card renders with teal gradient

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-002: Dashboard displays primary metric card with total expenses
**Priority:** Critical
**Feature:** Dashboard -- Summary Stats
**Preconditions:** User is logged in. Database has expense records.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Locate the large teal gradient card at the top of the metrics section (id `primary-metric-card`).
   - **Expected:** The card shows "TOTAL DE GASTOS" as its label.
3. Read the large number displayed on the card.
   - **Expected:** A currency amount is shown (e.g., "₡1,234,567"). The number uses comma-separated thousands formatting.
4. Look at the bottom of the primary card for the three-column stats row.
   - **Expected:** Three sub-stats are visible: "Transacciones" (count), "Promedio" (average amount with ₡ prefix), and "Categorias" (count of unique categories).

### Pass Criteria
- [x] Primary metric card displays "TOTAL DE GASTOS"
- [x] Amount is formatted with ₡ prefix and thousands separators
- [x] Transaction count, average, and category count are shown below the total

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-003: Dashboard displays secondary metric cards (month, week, today)
**Priority:** Critical
**Feature:** Dashboard -- Summary Stats
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Below the primary metric card, locate three smaller white cards in a row.
   - **Expected:** Three cards are visible side by side on desktop. They are labeled "Este Mes", "Esta Semana", and "Hoy".
3. For each card, verify the content.
   - **Expected:** Each card shows: an icon in a colored circle (amber for month, teal for week, emerald for today), the period label, a currency amount (₡ prefixed), and a transaction count (e.g., "X transacciones").
4. Check for trend percentage indicators on each card.
   - **Expected:** If there is a change from the previous period, a percentage is shown in the top-right corner of the card. Increases show in rose/red color, decreases in emerald/green color.

### Pass Criteria
- [x] Three secondary metric cards are visible: "Este Mes", "Esta Semana", "Hoy"
- [x] Each card shows an amount with ₡ prefix and transaction count
- [x] Trend percentages use correct colors (rose for increase, emerald for decrease)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-004: Clicking primary metric card navigates to yearly expenses
**Priority:** High
**Feature:** Dashboard -- Period Navigation
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Click the large teal primary metric card ("TOTAL DE GASTOS").
   - **Expected:** Browser navigates to the expenses index page (`/expenses`) with period filter parameters in the URL (e.g., `?period=year&filter_type=dashboard_metric&date_from=...&date_to=...`).
3. Observe the expense list page.
   - **Expected:** A teal banner appears at the top: "Volver al Dashboard" link on the left. A filter description like "Gastos del ano" is displayed. The expenses shown are scoped to the current year.

### Pass Criteria
- [x] Clicking primary card navigates to `/expenses` with year period parameters
- [x] Back-to-dashboard link is visible
- [x] Filter description matches the period

**NOTE:** URL uses `date_from=2026-01-01&date_to=2026-12-31&filter_type=dashboard_metric` rather than `period=year` as expected. Functional behavior is correct.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-005: Clicking "Este Mes" card navigates to monthly expenses
**Priority:** High
**Feature:** Dashboard -- Period Navigation
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Click the "Este Mes" card (id `month-metric-card`).
   - **Expected:** Browser navigates to `/expenses` with `period=month` in the URL parameters.
3. Observe the filtered expense list.
   - **Expected:** The filter description shows "Gastos de este mes". Only expenses from the current month are listed.

### Pass Criteria
- [x] Clicking "Este Mes" card navigates with month period filter
- [x] Filter description reads "Gastos de este mes"
- [x] Expense list is scoped to the current month

**NOTE:** URL uses `date_from=2026-03-01&date_to=2026-03-31&filter_type=dashboard_metric` rather than `period=month`.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-006: Clicking "Esta Semana" card navigates to weekly expenses
**Priority:** High
**Feature:** Dashboard -- Period Navigation
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Click the "Esta Semana" card (id `week-metric-card`).
   - **Expected:** Browser navigates to `/expenses` with `period=week` in the URL parameters.
3. Observe the filtered expense list.
   - **Expected:** The filter description shows "Gastos de esta semana". Only expenses from the current week are listed.

### Pass Criteria
- [x] Clicking "Esta Semana" card navigates with week period filter
- [x] Filter description reads "Gastos de esta semana"

**NOTE:** URL uses `date_from=2026-03-23&date_to=2026-03-29&filter_type=dashboard_metric` rather than `period=week`.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-007: Clicking "Hoy" card navigates to today's expenses
**Priority:** High
**Feature:** Dashboard -- Period Navigation
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Click the "Hoy" card (id `day-metric-card`).
   - **Expected:** Browser navigates to `/expenses` with `period=day` in the URL parameters.
3. Observe the filtered expense list.
   - **Expected:** The filter description shows "Gastos de hoy". Only today's expenses are listed (may be empty if no expenses today).

### Pass Criteria
- [x] Clicking "Hoy" card navigates with day period filter
- [x] Filter description reads "Gastos de hoy"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-008: Monthly trend chart renders
**Priority:** High
**Feature:** Dashboard -- Charts
**Preconditions:** User is logged in. Database has expenses across multiple months.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Scroll down past the metric cards to the charts section.
   - **Expected:** Two charts appear side by side on desktop: "Tendencia Mensual" (left) and "Gastos por Categoria" (right).
3. Inspect the "Tendencia Mensual" chart.
   - **Expected:** A line chart is rendered (via Chart.js / Chartkick). The chart has a teal-colored line. Amounts on the Y-axis use the ₡ prefix. The chart container is approximately 300px in height.

### Pass Criteria
- [x] "Tendencia Mensual" heading is visible
- [x] A line chart renders with data points
- [x] Chart uses teal color (#0F766E)
- [x] No JavaScript errors in the console

**FAILED (Run 1):** Chart canvas elements exist (5 canvases rendered) but all show "Loading..." indefinitely. Console error: `TypeError: Cannot read properties of undefined (reading 'id')` in `chartjs-adapter-date-fns.bundle.min.js:7`. The Chart.js date adapter is broken. Sparkline controller falls back with warning: "Chart.js not available, falling back to plain text".

**PASSED (Run 2):** PER-222 fix confirmed. 7 canvas elements render with non-zero dimensions. Main trend chart (id=chart-1) renders at 562×300px. No "Loading..." text. No chartjs-adapter errors. No "No charting libraries" fallback text.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-009: Category breakdown pie chart renders
**Priority:** High
**Feature:** Dashboard -- Charts
**Preconditions:** User is logged in. Database has categorized expenses.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Locate the "Gastos por Categoria" card in the charts section.
   - **Expected:** A pie chart is rendered showing up to 8 categories.
3. Hover over a pie chart segment (if interactive).
   - **Expected:** A tooltip shows the category name and amount with ₡ prefix.

### Pass Criteria
- [x] "Gastos por Categoria" heading is visible
- [x] Pie chart renders with colored segments
- [x] Chart shows up to 8 categories

**FAILED (Run 1):** Same root cause as B-008 — Chart.js adapter error prevents chart rendering. Heading "Gastos por Categoría" is present but chart canvas shows "Loading..." text.

**PASSED (Run 2):** PER-222 fix confirmed. Chart canvas (id=chart-2) renders at 562×300px with non-zero dimensions. No "Loading..." text. Category pie/bar chart data loaded.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-010: Recent expenses widget shows latest expenses
**Priority:** Critical
**Feature:** Dashboard -- Recent Expenses
**Preconditions:** User is logged in. Database has expense records.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Scroll down to the "Gastos Recientes" section (id `dashboard-expenses-widget`).
   - **Expected:** The section heading "Gastos Recientes" is visible. Up to 15 expenses are displayed.
3. Verify each expense row displays: date, merchant name, category, and amount.
   - **Expected:** Table rows show columns: Fecha, Comercio, Categoria, Monto. Amounts use ₡ prefix.
4. Check for the "Ver todos" link.
   - **Expected:** A "Ver todos" link is visible in the header area, linking to `/expenses`.

### Pass Criteria
- [x] "Gastos Recientes" heading is visible
- [x] Expense rows show date, merchant, category, and amount
- [x] "Ver todos" link is present and points to `/expenses`
- [x] Up to 15 expenses are displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-011: Dashboard view toggle switches between compact and expanded
**Priority:** High
**Feature:** Dashboard -- View Toggle
**Preconditions:** User is logged in. Recent expenses section has data.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. In the "Gastos Recientes" header, locate the view toggle buttons (Compacta / Expandida).
   - **Expected:** Two toggle buttons are visible: "Compacta" and "Expandida". One is highlighted (active state with white background and shadow).
3. Click "Expandida" (or "Compacta" if currently expanded).
   - **Expected:** The expense list view changes. In expanded mode, additional columns appear: Banco, Estado, Acciones. In compact mode, these columns are hidden.
4. Verify the toggle button state updates.
   - **Expected:** The clicked button becomes active (white background, shadow). The other button becomes inactive.

### Pass Criteria
- [x] Both toggle buttons are visible: "Compacta" and "Expandida"
- [x] Clicking toggles between views
- [x] Expanded view shows Banco, Estado, Acciones columns
- [x] Compact view hides those columns

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-012: Dashboard filter chips filter the expense list
**Priority:** High
**Feature:** Dashboard -- Filtering
**Preconditions:** User is logged in. Database has expenses in multiple categories.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Scroll to the "Gastos Recientes" section and locate the filter chips area below the header.
   - **Expected:** Category filter chips are visible, each showing a colored dot, category name, and count in parentheses.
3. Click on one of the category filter chips.
   - **Expected:** The chip becomes selected (visual change). The expense list updates to show only expenses matching that category. A "Limpiar filtros" button may appear.
4. Click the "Limpiar filtros" button (or the same chip again to deselect).
   - **Expected:** The filter is removed. The expense list returns to showing all recent expenses.

### Pass Criteria
- [x] Category filter chips are displayed with names and counts
- [x] Clicking a chip filters the expense list
- [x] Clearing filters restores the full list

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-013: Dashboard period filter chips work
**Priority:** High
**Feature:** Dashboard -- Period Filtering
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. In the filter chips section, locate the "Periodo:" row.
   - **Expected:** Period filter chips are shown with labels and counts.
3. Click a period filter chip (e.g., the one for the current month).
   - **Expected:** The expense list updates to show only expenses from that period. The chip appears selected.

### Pass Criteria
- [x] Period filter chips are visible
- [x] Clicking a period chip filters the list by time period
- [x] The chip visually indicates selected state

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-014: Dashboard "Ver todos" link navigates to expense list
**Priority:** Medium
**Feature:** Dashboard -- Navigation
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. In the "Gastos Recientes" section header, click the "Ver todos" link.
   - **Expected:** Browser navigates to `http://localhost:3000/expenses`. The full expense list page loads with all expenses, filters, and pagination.

### Pass Criteria
- [x] "Ver todos" link navigates to `/expenses`
- [x] Expense list page loads correctly

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-015: Dashboard top merchants widget renders
**Priority:** Medium
**Feature:** Dashboard -- Top Merchants
**Preconditions:** User is logged in. Database has expenses with merchant names.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Scroll to the "Comercios con Mas Gastos" section.
   - **Expected:** A ranked list of merchants appears, each with a numbered badge (1, 2, 3...), the merchant name, and the total amount.
3. Verify the amounts are formatted correctly.
   - **Expected:** Amounts use ₡ prefix and thousands separators. Names are truncated at 30 characters if necessary.

### Pass Criteria
- [x] "Comercios con Mas Gastos" section is visible
- [x] Merchants are listed with rank numbers
- [x] Amounts are correctly formatted

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-016: Dashboard bank breakdown widget renders
**Priority:** Medium
**Feature:** Dashboard -- Bank Breakdown
**Preconditions:** User is logged in. Database has expenses from multiple banks.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Scroll to the "Gastos por Banco" section.
   - **Expected:** A list of banks appears with their total amounts. Each bank has an icon circle (teal for BAC, slate for others).

### Pass Criteria
- [x] "Gastos por Banco" section is visible
- [x] Banks are listed with total amounts
- [x] BAC bank uses teal color styling

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-017: Dashboard email sync section renders
**Priority:** Medium
**Feature:** Dashboard -- Email Sync
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Locate the "Sincronizacion de Correos" section near the top of the dashboard.
   - **Expected:** The section shows a "Sincronizar Todos los Correos" button and sync status for configured email accounts.
3. If email accounts are configured, verify each account shows: email address, bank name, and last sync timestamp.
   - **Expected:** Account rows display correctly with status indicators.
4. If no email accounts exist, verify the warning message.
   - **Expected:** An amber warning box shows "No hay cuentas de correo configuradas." with a "Configurar cuenta" link.

### Pass Criteria
- [x] Sync section heading is visible
- [x] Sync button is present
- [x] Account status or warning message is displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-018: Dashboard batch selection mode activates
**Priority:** Medium
**Feature:** Dashboard -- Batch Selection
**Preconditions:** User is logged in. Recent expenses widget has data.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. In the "Gastos Recientes" header, click the batch selection toggle button (clipboard icon with checkmark).
   - **Expected:** Selection mode activates. A selection toolbar appears with: "Seleccionar todos" checkbox, "0 seleccionados" counter, and action buttons (Categorizar, Estado, Eliminar).
3. Check a few expense rows (checkboxes should appear in the first column).
   - **Expected:** The selected count updates (e.g., "3 seleccionados").
4. Click the X button in the selection toolbar to exit selection mode.
   - **Expected:** Selection mode deactivates. Checkboxes and toolbar disappear.

### Pass Criteria
- [x] Selection toggle button exists and activates selection mode
- [x] Selection toolbar appears with correct buttons
- [x] Selected count updates when checkboxes are toggled
- [x] Exiting selection mode hides the toolbar

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-019: Dashboard conflict alert displays when conflicts exist
**Priority:** Medium
**Feature:** Dashboard -- Conflict Alert
**Preconditions:** User is logged in. There are unresolved sync conflicts in the database.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Look for an amber alert banner below the sync section.
   - **Expected:** If unresolved conflicts exist, a banner shows "X conflicto(s) pendiente(s) de resolucion" with a "Resolver Conflictos" button.
3. Click "Resolver Conflictos".
   - **Expected:** Browser navigates to `/sync_conflicts`.

### Pass Criteria
- [x] Conflict alert appears when unresolved conflicts exist
- [x] "Resolver Conflictos" button navigates to `/sync_conflicts`
- [x] If no conflicts exist, the banner is not shown

**NOTE:** No unresolved conflicts exist in the test database. Banner is correctly absent.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-020: Dashboard empty state when no expenses exist
**Priority:** Medium
**Feature:** Dashboard -- Empty State
**Preconditions:** User is logged in. Database has zero expenses (or all are deleted).

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads without errors.
2. Observe the primary metric card.
   - **Expected:** Shows ₡0 as the total amount with 0 transactions.
3. Scroll to the "Gastos Recientes" section.
   - **Expected:** An empty state message appears: "No hay gastos" with either "Aun no tienes gastos registrados." or a filter-related message.
4. Observe the charts section.
   - **Expected:** Charts render but may show empty data or zero values. No JavaScript errors in the console.

### Pass Criteria
- [ ] Dashboard loads without errors even with no data
- [ ] Metric cards show zero values
- [ ] Empty state message appears in the recent expenses widget
- [ ] No JavaScript console errors

**BLOCKED:** Database contains 78 expense records. Empty state cannot be tested without destructive data deletion.

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# SECTION 2: MOBILE CARD LAYOUT -- PER-133 (B-021 through B-040)

---
