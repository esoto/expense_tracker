# QA Testing Playbook -- Group B: Dashboard + Mobile Card Layout + Navigation + Responsive + Accessibility

**Application:** Rails 8.1.2 Expense Tracker (Spanish UI)
**Base URL:** `http://localhost:3000`
**Login:** `admin@expense-tracker.com` / `AdminPassword123!`
**Date:** 2026-03-26
**Agent Group:** B

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
- [ ] Root URL redirects to `/expenses/dashboard`
- [ ] Page title includes "Dashboard"
- [ ] Heading "Dashboard de Gastos" is visible
- [ ] Primary metric card renders with teal gradient

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
- [ ] Primary metric card displays "TOTAL DE GASTOS"
- [ ] Amount is formatted with ₡ prefix and thousands separators
- [ ] Transaction count, average, and category count are shown below the total

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
- [ ] Three secondary metric cards are visible: "Este Mes", "Esta Semana", "Hoy"
- [ ] Each card shows an amount with ₡ prefix and transaction count
- [ ] Trend percentages use correct colors (rose for increase, emerald for decrease)

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
- [ ] Clicking primary card navigates to `/expenses` with year period parameters
- [ ] Back-to-dashboard link is visible
- [ ] Filter description matches the period

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
- [ ] Clicking "Este Mes" card navigates with month period filter
- [ ] Filter description reads "Gastos de este mes"
- [ ] Expense list is scoped to the current month

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
- [ ] Clicking "Esta Semana" card navigates with week period filter
- [ ] Filter description reads "Gastos de esta semana"

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
- [ ] Clicking "Hoy" card navigates with day period filter
- [ ] Filter description reads "Gastos de hoy"

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
- [ ] "Tendencia Mensual" heading is visible
- [ ] A line chart renders with data points
- [ ] Chart uses teal color (#0F766E)
- [ ] No JavaScript errors in the console

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
- [ ] "Gastos por Categoria" heading is visible
- [ ] Pie chart renders with colored segments
- [ ] Chart shows up to 8 categories

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
- [ ] "Gastos Recientes" heading is visible
- [ ] Expense rows show date, merchant, category, and amount
- [ ] "Ver todos" link is present and points to `/expenses`
- [ ] Up to 15 expenses are displayed

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
- [ ] Both toggle buttons are visible: "Compacta" and "Expandida"
- [ ] Clicking toggles between views
- [ ] Expanded view shows Banco, Estado, Acciones columns
- [ ] Compact view hides those columns

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
- [ ] Category filter chips are displayed with names and counts
- [ ] Clicking a chip filters the expense list
- [ ] Clearing filters restores the full list

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
- [ ] Period filter chips are visible
- [ ] Clicking a period chip filters the list by time period
- [ ] The chip visually indicates selected state

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
- [ ] "Ver todos" link navigates to `/expenses`
- [ ] Expense list page loads correctly

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
- [ ] "Comercios con Mas Gastos" section is visible
- [ ] Merchants are listed with rank numbers
- [ ] Amounts are correctly formatted

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
- [ ] "Gastos por Banco" section is visible
- [ ] Banks are listed with total amounts
- [ ] BAC bank uses teal color styling

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
- [ ] Sync section heading is visible
- [ ] Sync button is present
- [ ] Account status or warning message is displayed

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
- [ ] Selection toggle button exists and activates selection mode
- [ ] Selection toolbar appears with correct buttons
- [ ] Selected count updates when checkboxes are toggled
- [ ] Exiting selection mode hides the toolbar

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
- [ ] Conflict alert appears when unresolved conflicts exist
- [ ] "Resolver Conflictos" button navigates to `/sync_conflicts`
- [ ] If no conflicts exist, the banner is not shown

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

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# SECTION 2: MOBILE CARD LAYOUT -- PER-133 (B-021 through B-040)

---

## Scenario B-021: Mobile viewport shows cards, hides table
**Priority:** Critical
**Feature:** Mobile Card Layout
**Preconditions:** User is logged in. Database has expense records.

### Steps
1. Open Chrome DevTools (F12) and enable Device Toolbar (Ctrl+Shift+M).
2. Set viewport to 375px width (iPhone SE or similar).
3. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads successfully.
4. Look for the expense list section.
   - **Expected:** The `#expense_cards` container (class `md:hidden`) is visible, showing expense cards. The `#expense_list` container (class `hidden md:block`) is NOT visible -- the table is hidden.

### Pass Criteria
- [ ] At 375px viewport, the card-based layout is visible
- [ ] At 375px viewport, the table layout is hidden
- [ ] Cards are rendered inside `#expense_cards`

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-022: Desktop viewport shows table, hides cards
**Priority:** Critical
**Feature:** Mobile Card Layout
**Preconditions:** User is logged in. Database has expense records.

### Steps
1. Open Chrome DevTools and set viewport to 1280px width.
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads successfully.
3. Look for the expense list section.
   - **Expected:** The `#expense_list` container is visible, showing the table with columns: Fecha, Comercio, Categoria, Monto, etc. The `#expense_cards` container is NOT visible.

### Pass Criteria
- [ ] At 1280px viewport, the table layout is visible
- [ ] At 1280px viewport, the card layout is hidden

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-023: Mobile card displays merchant name, amount, date, category
**Priority:** Critical
**Feature:** Mobile Card Layout -- Card Content
**Preconditions:** User is logged in. Viewport set to 375px. Database has a categorized expense.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Inspect the first expense card.
   - **Expected:** The card shows:
     - A colored dot on the left representing the category color
     - The merchant name (truncated if long) in bold text
     - The amount on the right side, formatted as ₡X,XXX
     - Below: the date in DD/MM/YYYY format, a dot separator, and the category name
3. Verify the card styling matches the Financial Confidence design system.
   - **Expected:** Card has classes: `bg-white rounded-xl shadow-sm border border-slate-200`. No blue colors are used.

### Pass Criteria
- [ ] Merchant name is displayed in bold
- [ ] Amount shows with ₡ prefix and thousands formatting
- [ ] Date is in DD/MM/YYYY format
- [ ] Category color dot and name are shown
- [ ] Card uses Financial Confidence styling (no blue)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-024: Mobile card shows status badge for non-processed expenses
**Priority:** High
**Feature:** Mobile Card Layout -- Status Badge
**Preconditions:** User is logged in. Viewport set to 375px. Database has expenses with status "pending", "duplicate", or "failed".

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Find a card for an expense with "pending" status.
   - **Expected:** The card shows a status badge "Pendiente" in an amber pill (bg-amber-100 text-amber-800).
3. Find a card for an expense with "duplicate" status (if available).
   - **Expected:** Badge shows "Duplicado" in rose pill (bg-rose-100 text-rose-800).
4. Find a card for an expense with "processed" status.
   - **Expected:** No status badge is shown (status badge is hidden for "processed").

### Pass Criteria
- [ ] "Pendiente" badge appears for pending expenses (amber styling)
- [ ] "Duplicado" badge appears for duplicate expenses (rose styling)
- [ ] No badge appears for processed expenses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-025: Tapping a mobile card expands the action drawer
**Priority:** Critical
**Feature:** Mobile Card Layout -- Action Drawer
**Preconditions:** User is logged in. Viewport set to 375px. Cards are visible.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed. No action drawers are visible.
2. Tap (click) on the first expense card.
   - **Expected:** The card expands to reveal an action drawer at the bottom. The drawer has a light gray background (bg-slate-50) and a top border (border-slate-100).
3. Inspect the action drawer contents.
   - **Expected:** Four action buttons are visible side by side:
     - "Categoria" (teal styling, tag icon)
     - "Estado" (emerald styling, checkmark icon)
     - "Editar" (slate styling, pencil icon)
     - "Eliminar" (rose styling, trash icon)

### Pass Criteria
- [ ] Tapping a card reveals the action drawer
- [ ] Four buttons are visible: Categoria, Estado, Editar, Eliminar
- [ ] Buttons use correct Financial Confidence colors (teal, emerald, slate, rose)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-026: Tapping another card collapses the previous card
**Priority:** High
**Feature:** Mobile Card Layout -- Single Expand
**Preconditions:** User is logged in. Viewport set to 375px. First card is already expanded.

### Steps
1. From Scenario B-025, the first card's action drawer is open.
2. Tap (click) on the second expense card.
   - **Expected:** The first card's action drawer collapses (hides). The second card's action drawer expands.
3. Verify only one action drawer is open at a time.
   - **Expected:** Only the second card shows its action drawer. All other cards are collapsed.

### Pass Criteria
- [ ] Tapping a new card collapses the previously expanded card
- [ ] Only one card's action drawer is open at a time

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-027: Tapping an expanded card again collapses it
**Priority:** High
**Feature:** Mobile Card Layout -- Toggle Collapse
**Preconditions:** User is logged in. Viewport set to 375px. A card is expanded.

### Steps
1. From an expanded card state, tap (click) on the same expanded card (in the main content area, not the action buttons).
   - **Expected:** The action drawer collapses. The card returns to its default compact state.
2. Verify no action drawers are visible.
   - **Expected:** All cards are in their collapsed state.

### Pass Criteria
- [ ] Tapping an expanded card collapses its action drawer
- [ ] Card returns to compact state

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-028: Long-press (500ms) enters selection mode
**Priority:** High
**Feature:** Mobile Card Layout -- Selection Mode
**Preconditions:** User is logged in. Viewport set to 375px. Using touch simulation in DevTools.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Enable touch simulation in DevTools (toggle device toolbar to a touch device).
3. Long-press (press and hold for 500ms) on any expense card.
   - **Expected:** After 500ms, selection mode activates. A haptic vibration may occur (on supported devices). Checkboxes appear on ALL cards (the hidden checkbox divs become visible).
4. Verify the long-pressed card's checkbox is checked.
   - **Expected:** The card you long-pressed has its checkbox checked. Other cards show unchecked checkboxes.

### Pass Criteria
- [ ] Long-press (500ms) activates selection mode
- [ ] Checkboxes appear on all cards
- [ ] The long-pressed card's checkbox is automatically checked

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-029: In selection mode, tapping a card toggles its checkbox
**Priority:** High
**Feature:** Mobile Card Layout -- Selection Mode Interaction
**Preconditions:** Selection mode is active (from Scenario B-028).

### Steps
1. With selection mode active (checkboxes visible), tap on a different card.
   - **Expected:** That card's checkbox toggles (checked if it was unchecked, unchecked if it was checked). The action drawer does NOT expand.
2. Tap the same card again.
   - **Expected:** The checkbox toggles back to its previous state.

### Pass Criteria
- [ ] Tapping a card in selection mode toggles its checkbox
- [ ] Action drawer does not expand during selection mode

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-030: Edit button in action drawer navigates to edit page
**Priority:** Critical
**Feature:** Mobile Card Layout -- Edit Action
**Preconditions:** User is logged in. Viewport set to 375px. A card is expanded.

### Steps
1. Expand a card by tapping it.
   - **Expected:** Action drawer is visible with 4 buttons.
2. Tap the "Editar" button (link with pencil icon).
   - **Expected:** Browser navigates to `/expenses/:id/edit` where `:id` is the expense's ID. The edit form loads with the expense data pre-filled.
3. Verify the edit page loads correctly.
   - **Expected:** The page shows a form with fields for amount, merchant name, category, date, etc.

### Pass Criteria
- [ ] "Editar" button navigates to the correct edit page
- [ ] Edit form is pre-filled with the expense data

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-031: Status toggle button sends PATCH request
**Priority:** High
**Feature:** Mobile Card Layout -- Status Toggle
**Preconditions:** User is logged in. Viewport set to 375px. A card is expanded. Open Network tab in DevTools.

### Steps
1. Expand a card by tapping it.
   - **Expected:** Action drawer is visible.
2. Note the current status of the expense (check for a "Pendiente" or other badge, or absence of badge for "processed").
3. Tap the "Estado" button (emerald, checkmark icon).
   - **Expected:** A PATCH request is sent to `/expenses/:id/update_status`. The Network tab shows the request with status 200. The card's status badge updates (e.g., "Pendiente" toggles to no badge for "processed", or vice versa).

### Pass Criteria
- [ ] Tapping "Estado" sends a PATCH request to `/expenses/:id/update_status`
- [ ] The response is successful (200 or similar)
- [ ] The card's status badge updates visually

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-032: Delete button shows confirmation and removes card
**Priority:** Critical
**Feature:** Mobile Card Layout -- Delete Action
**Preconditions:** User is logged in. Viewport set to 375px. A card is expanded.

### Steps
1. Expand a card by tapping it and note the expense's merchant name.
   - **Expected:** Action drawer is visible.
2. Tap the "Eliminar" button (rose, trash icon).
   - **Expected:** A browser confirmation dialog appears: "Estas seguro de eliminar este gasto?"
3. Click "Cancel" on the confirmation dialog.
   - **Expected:** Nothing happens. The card remains in place.
4. Tap "Eliminar" again and click "OK" on the confirmation dialog.
   - **Expected:** The card fades out and slides to the right (opacity and transform animation). After ~300ms, the card is removed from the DOM. A DELETE request is sent to `/expenses/:id`.

### Pass Criteria
- [ ] Confirmation dialog appears before deletion
- [ ] Canceling the dialog preserves the card
- [ ] Confirming deletion removes the card with animation
- [ ] DELETE request is sent to the server

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-033: Collapsible "Filtrar" button on mobile expense list
**Priority:** High
**Feature:** Mobile Card Layout -- Collapsible Filters
**Preconditions:** User is logged in. Viewport set to 375px.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Page loads. The filter form is HIDDEN by default on mobile (the `collapsible-filter` content target has class `hidden`).
2. Locate the "Filtrar" button (visible only on mobile, class `md:hidden`).
   - **Expected:** A button labeled "Filtrar" with a filter icon is visible.
3. Tap the "Filtrar" button.
   - **Expected:** The filter form section expands/becomes visible. The button's `aria-expanded` attribute changes to "true".
4. Tap the "Filtrar" button again.
   - **Expected:** The filter form collapses back to hidden. `aria-expanded` changes to "false".

### Pass Criteria
- [ ] "Filtrar" button is visible on mobile
- [ ] Tapping the button reveals the filter form
- [ ] Tapping again hides the filter form
- [ ] `aria-expanded` attribute toggles correctly

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-034: Filter count badge shows active filter count
**Priority:** Medium
**Feature:** Mobile Card Layout -- Filter Badge
**Preconditions:** User is logged in. Viewport set to 375px.

### Steps
1. Navigate to `http://localhost:3000/expenses?category=Alimentacion` at 375px viewport (substitute a real category name from the database).
   - **Expected:** Page loads with the category filter applied.
2. Locate the "Filtrar" button.
   - **Expected:** A small teal badge (rounded-full, bg-teal-600 text-white) appears next to the "Filtrar" text showing the number "1" (one active filter).
3. Navigate to `http://localhost:3000/expenses?category=Alimentacion&bank=BAC` at 375px viewport.
   - **Expected:** The badge shows "2" (two active filters).
4. Navigate to `http://localhost:3000/expenses` (no filters).
   - **Expected:** No badge is shown next to the "Filtrar" button.

### Pass Criteria
- [ ] Badge appears when filters are active
- [ ] Badge count matches the number of active filters
- [ ] Badge is hidden when no filters are active

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-035: "Ver resumen" toggle shows/hides category summary on mobile
**Priority:** Medium
**Feature:** Mobile Card Layout -- Category Summary Toggle
**Preconditions:** User is logged in. Viewport set to 375px. No category filter is applied (summary section exists).

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Page loads. The "Resumen por Categoria" section is present.
2. Locate the "Ver resumen" button (visible only on mobile, class `md:hidden`).
   - **Expected:** The button text reads "Ver resumen" in teal color.
3. Tap "Ver resumen".
   - **Expected:** The category summary grid expands, showing category names and their total amounts (up to 6 categories).
4. Tap "Ver resumen" again.
   - **Expected:** The summary grid collapses/hides.

### Pass Criteria
- [ ] "Ver resumen" button is visible on mobile
- [ ] Tapping reveals the category summary grid
- [ ] Tapping again hides the summary
- [ ] Summary shows category names and amounts

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-036: Mobile pagination works on card layout
**Priority:** High
**Feature:** Mobile Card Layout -- Pagination
**Preconditions:** User is logged in. Viewport set to 375px. Database has more than 50 expenses (default per_page).

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed. At the bottom of the card list, pagination controls are visible.
2. Verify the pagination info text.
   - **Expected:** Text reads "Mostrando X-Y de Z gastos" where X-Y is the current range and Z is the total count.
3. Tap the "Next" page button (or page 2).
   - **Expected:** The page reloads with the next set of expenses. The URL updates with `?page=2`. New cards are displayed.
4. Verify the card layout persists on page 2.
   - **Expected:** Cards are still displayed (not a table). Pagination controls remain at the bottom.

### Pass Criteria
- [ ] Pagination controls appear when total exceeds per_page
- [ ] Pagination info text shows correct range
- [ ] Navigating to page 2 loads new cards
- [ ] Card layout persists across pages

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-037: Touch targets meet 44px minimum on mobile cards
**Priority:** High
**Feature:** Mobile Card Layout -- Touch Targets
**Preconditions:** User is logged in. Viewport set to 375px. A card is expanded to show action buttons.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
2. Expand a card by tapping it.
   - **Expected:** Action drawer is visible with 4 buttons.
3. Using DevTools Elements panel, inspect each action button's rendered size.
   - **Expected:** Each button (Categoria, Estado, Editar, Eliminar) has a minimum height of 44px. The buttons have `py-2 px-3` padding which should yield at least 44px total height with the icon and text.
4. Inspect the card itself as a tap target.
   - **Expected:** The card's content area (`px-4 py-3`) provides a sufficiently large touch target (well above 44px).

### Pass Criteria
- [ ] Action buttons have a minimum effective height of 44px
- [ ] Card content area provides adequate touch target size
- [ ] Visual inspection confirms buttons are easily tappable

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-038: Keyboard Enter/Space expands card, Escape collapses
**Priority:** High
**Feature:** Mobile Card Layout -- Keyboard Accessibility
**Preconditions:** User is logged in. Viewport set to 375px (cards visible).

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Press Tab to focus the first expense card.
   - **Expected:** The card receives focus (visible focus ring). The card has `tabindex="0"` so it is focusable.
3. Press Enter while the card is focused.
   - **Expected:** The card's action drawer expands (same as tapping). The `data-action` includes `keydown.enter->mobile-card#toggleActions`.
4. Press Escape while the card is expanded.
   - **Expected:** The action drawer collapses. The `data-action` includes `keydown.escape->mobile-card#collapseActions`.
5. Focus the card again and press Space.
   - **Expected:** The action drawer expands (same as Enter). The `data-action` includes `keydown.space->mobile-card#toggleActions`.

### Pass Criteria
- [ ] Cards are focusable via Tab key
- [ ] Enter key expands the action drawer
- [ ] Space key expands the action drawer
- [ ] Escape key collapses the action drawer

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-039: Card handles uncategorized expense correctly
**Priority:** Medium
**Feature:** Mobile Card Layout -- Uncategorized Display
**Preconditions:** User is logged in. Viewport set to 375px. Database has an expense with no category.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Find a card for an uncategorized expense.
   - **Expected:** Instead of a colored category dot, a gray dot is shown (`bg-slate-400`). The title attribute says "Sin categoria". No category name appears in the bottom row.

### Pass Criteria
- [ ] Uncategorized expense shows gray dot instead of colored dot
- [ ] No category name appears in the details row
- [ ] Layout does not break for uncategorized expenses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-040: Card handles missing merchant name
**Priority:** Medium
**Feature:** Mobile Card Layout -- Missing Merchant
**Preconditions:** User is logged in. Viewport set to 375px. Database has an expense with no merchant_name.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Find a card for an expense without a merchant name.
   - **Expected:** Instead of the merchant name, the text "Sin comercio" appears in rose-colored italic text (`text-rose-600 italic`).
3. Verify the card's aria-label.
   - **Expected:** The card's `aria-label` contains "Sin comercio" followed by the amount.

### Pass Criteria
- [ ] "Sin comercio" text appears in rose italic for missing merchants
- [ ] Card aria-label reflects "Sin comercio"
- [ ] Layout does not break

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# SECTION 3: NAVIGATION & LAYOUT (B-041 through B-055)

---

## Scenario B-041: Desktop nav shows all navigation links
**Priority:** Critical
**Feature:** Navigation
**Preconditions:** User is logged in. Viewport at 1280px.

### Steps
1. Navigate to `http://localhost:3000/` at 1280px viewport.
   - **Expected:** Page loads with the top navigation bar visible.
2. Inspect the navigation bar (id `main-navigation`).
   - **Expected:** The desktop nav container (class `hidden md:flex`) is visible. The following links are present (using i18n keys, so actual text depends on locale):
     - Dashboard (links to `/expenses/dashboard`)
     - Gastos (links to `/expenses`)
     - Categorizar (links to `/bulk_categorizations`)
     - Analytics (links to `/analytics/pattern_dashboard`)
     - Cuentas (links to `/email_accounts`)
     - Sincronizacion (links to `/sync_sessions`)
     - Patrones (links to `/admin/patterns`)
     - Nuevo Gasto (links to `/expenses/new`, styled as primary button)

### Pass Criteria
- [ ] All 8 navigation links are visible on desktop
- [ ] Each link points to the correct URL
- [ ] "Nuevo Gasto" is styled as a teal primary button

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-042: Nav highlights current page
**Priority:** High
**Feature:** Navigation -- Active State
**Preconditions:** User is logged in. Viewport at 1280px.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** The "Dashboard" nav link has the active styling: `bg-teal-50 text-teal-700`. It also has `aria-current="page"` attribute.
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** The "Gastos" nav link now has the active styling. The "Dashboard" link no longer has active styling.
3. Navigate to `http://localhost:3000/email_accounts`
   - **Expected:** The "Cuentas" nav link has the active styling.

### Pass Criteria
- [ ] Active page link has `bg-teal-50 text-teal-700` styling
- [ ] Active page link has `aria-current="page"` attribute
- [ ] Only the current page link is highlighted

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-043: Mobile hamburger menu opens and closes
**Priority:** Critical
**Feature:** Navigation -- Mobile Menu
**Preconditions:** User is logged in. Viewport set to 375px.

### Steps
1. Navigate to `http://localhost:3000/` at 375px viewport.
   - **Expected:** The desktop nav links are hidden. A hamburger button (three horizontal lines icon) is visible on the right side of the header.
2. Verify the hamburger button attributes.
   - **Expected:** Button has `aria-label="Abrir menu de navegacion"`, `aria-expanded="false"`, and `aria-controls="mobile-menu"`.
3. Tap (click) the hamburger button.
   - **Expected:** The mobile menu (id `mobile-menu`) slides open with an opacity transition. The menu shows all navigation links stacked vertically. `aria-expanded` changes to "true".
4. Verify all nav links are present in the mobile menu.
   - **Expected:** Dashboard, Gastos, Categorizar, Analytics, Cuentas, Sincronizacion, Patrones links are visible. "Nuevo Gasto" appears as a separate teal button below a divider.
5. Tap the hamburger button again.
   - **Expected:** The mobile menu closes. `aria-expanded` changes to "false".

### Pass Criteria
- [ ] Hamburger button is visible on mobile
- [ ] Tapping opens the mobile menu with all nav links
- [ ] `aria-expanded` toggles correctly
- [ ] Tapping again closes the menu

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-044: Mobile menu link navigates and closes menu
**Priority:** High
**Feature:** Navigation -- Mobile Menu Interaction
**Preconditions:** User is logged in. Viewport set to 375px. Mobile menu is open.

### Steps
1. Open the mobile menu by tapping the hamburger button.
   - **Expected:** Menu is open with nav links visible.
2. Tap the "Gastos" link in the mobile menu.
   - **Expected:** Browser navigates to `/expenses`. The mobile menu closes after navigation.

### Pass Criteria
- [ ] Clicking a mobile menu link navigates to the correct page
- [ ] The menu is not visible after navigation

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-045: Skip-to-content link works
**Priority:** High
**Feature:** Navigation -- Accessibility
**Preconditions:** User is logged in. Any viewport size.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Press Tab once from the page load.
   - **Expected:** A "Saltar al contenido principal" link becomes visible (class `sr-only-focusable` makes it visible on focus). A second Tab press reveals "Saltar a la navegacion".
3. Press Enter on the "Saltar al contenido principal" link.
   - **Expected:** Focus jumps to the `#main-content` element. The page scrolls to the main content area, skipping the navigation.

### Pass Criteria
- [ ] Skip link appears on first Tab press
- [ ] Skip link text is "Saltar al contenido principal"
- [ ] Activating the link moves focus to `#main-content`

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-046: Responsive layout at 375px (mobile)
**Priority:** High
**Feature:** Responsive Layout
**Preconditions:** User is logged in.

### Steps
1. Set viewport to 375px width.
2. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads. Content is not overflowing horizontally. No horizontal scrollbar appears.
3. Verify metric cards stack vertically.
   - **Expected:** The three secondary metric cards (Este Mes, Esta Semana, Hoy) stack in a single column (grid-cols-1 applies at this width).
4. Verify charts stack vertically.
   - **Expected:** The two chart cards (Tendencia Mensual, Gastos por Categoria) stack vertically instead of side by side.

### Pass Criteria
- [ ] No horizontal overflow at 375px
- [ ] Metric cards stack vertically
- [ ] Charts stack vertically
- [ ] All content is readable

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-047: Responsive layout at 768px (tablet)
**Priority:** Medium
**Feature:** Responsive Layout
**Preconditions:** User is logged in.

### Steps
1. Set viewport to 768px width.
2. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads. Desktop navigation becomes visible (the `md:flex` breakpoint activates at 768px). Hamburger button is hidden.
3. Navigate to `http://localhost:3000/expenses`
   - **Expected:** The table layout is visible (class `hidden md:block` activates). Card layout is hidden (class `md:hidden`).
4. Verify the filter form is visible by default (not collapsed).
   - **Expected:** The filter form (`collapsible-filter` content) has class `md:block`, so it is visible on tablet without needing to tap "Filtrar".

### Pass Criteria
- [ ] Desktop nav visible at 768px
- [ ] Table layout visible, card layout hidden
- [ ] Filter form is visible by default at 768px

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-048: Responsive layout at 1024px (small desktop)
**Priority:** Medium
**Feature:** Responsive Layout
**Preconditions:** User is logged in.

### Steps
1. Set viewport to 1024px width.
2. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads. The two-column chart grid is visible (lg:grid-cols-2 activates at 1024px).
3. Verify the top merchants and bank breakdown sections are side by side.
   - **Expected:** Both sections display in a two-column grid.

### Pass Criteria
- [ ] Charts display in two-column layout at 1024px
- [ ] Merchants and bank sections are side by side
- [ ] No layout issues

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-049: Responsive layout at 1280px (full desktop)
**Priority:** Medium
**Feature:** Responsive Layout
**Preconditions:** User is logged in.

### Steps
1. Set viewport to 1280px width.
2. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads at full desktop width. All content fits within the `max-w-7xl` container. The sync section uses a two-column grid (lg:grid-cols-2).
3. Verify the expense table in "Gastos Recientes" has all columns visible.
   - **Expected:** Table columns include Fecha, Comercio, Categoria, Monto, and in expanded mode: Banco, Estado, Acciones.

### Pass Criteria
- [ ] Page layout maximizes at 7xl container width
- [ ] All dashboard sections render correctly at full width
- [ ] Sync section uses two-column layout

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-050: Flash messages render and are visible
**Priority:** Medium
**Feature:** Layout -- Flash Messages
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** The new expense form loads.
2. Fill in the form with valid data (amount: 1000, merchant: "Test Merchant", date: today, select a category).
3. Submit the form.
   - **Expected:** A success flash message appears (green/emerald styling). The message text should be related to successful creation (e.g., "Gasto creado exitosamente").
4. Verify the flash message is inside the `max-w-7xl` container.
   - **Expected:** The flash message is centered and aligned with the rest of the page content.

### Pass Criteria
- [ ] Flash message appears after successful action
- [ ] Message uses the Financial Confidence success styling (emerald)
- [ ] Message is properly positioned within the page container

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-051: Page titles reflect current section
**Priority:** Medium
**Feature:** Layout -- Page Titles
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Browser tab title includes "Dashboard" or the i18n equivalent.
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Browser tab title includes "Gastos" or the i18n equivalent for expense index.
3. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** Browser tab title reflects the new expense page.

### Pass Criteria
- [ ] Dashboard page has a meaningful title
- [ ] Expense list page has a meaningful title
- [ ] Each page title is distinct

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-052: Expense Tracker logo/link navigates to expense list
**Priority:** Medium
**Feature:** Navigation -- Logo Link
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Click the "Expense Tracker" text in the top-left of the navigation bar.
   - **Expected:** Browser navigates to `/expenses` (the `expenses_path`). The link has `aria-label="Expense Tracker - Pagina principal"`.

### Pass Criteria
- [ ] Logo text links to `/expenses`
- [ ] Logo link has an `aria-label`

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-053: Nuevo Gasto button navigates to new expense form
**Priority:** High
**Feature:** Navigation -- New Expense
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard` at 1280px viewport.
   - **Expected:** Page loads with desktop navigation visible.
2. Click the "Nuevo Gasto" button in the navigation bar (teal primary button styling).
   - **Expected:** Browser navigates to `/expenses/new`. The new expense form loads.
3. Repeat at 375px viewport using the mobile menu.
   - **Expected:** Open mobile menu. Tap "Nuevo Gasto" (styled as a block-level teal button at the bottom of the menu). Browser navigates to `/expenses/new`.

### Pass Criteria
- [ ] "Nuevo Gasto" button works on desktop
- [ ] "Nuevo Gasto" button works on mobile menu
- [ ] Both navigate to `/expenses/new`

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-054: Navigation uses Financial Confidence color palette
**Priority:** Medium
**Feature:** Navigation -- Design System
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/` at 1280px viewport.
   - **Expected:** Page loads.
2. Inspect the navigation bar styles using DevTools.
   - **Expected:** The nav background is `bg-white` with `border-b border-slate-200`. The logo icon uses `bg-teal-700`. Active nav links use `bg-teal-50 text-teal-700`. The "Nuevo Gasto" button uses `bg-teal-700 hover:bg-teal-800`.
3. Search for any `blue-` classes in the navigation HTML.
   - **Expected:** No `blue-` classes are found anywhere in the nav markup.

### Pass Criteria
- [ ] Navigation uses teal, slate, and white colors only
- [ ] No `blue-` CSS classes in navigation
- [ ] Active state uses teal-50/teal-700

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-055: Mobile menu aria-expanded toggles correctly
**Priority:** Medium
**Feature:** Navigation -- Accessibility
**Preconditions:** User is logged in. Viewport set to 375px.

### Steps
1. Navigate to `http://localhost:3000/` at 375px viewport.
   - **Expected:** Hamburger button is visible.
2. Inspect the hamburger button's `aria-expanded` attribute.
   - **Expected:** Value is `"false"`.
3. Tap the hamburger button.
   - **Expected:** `aria-expanded` changes to `"true"`. The `aria-controls` attribute is `"mobile-menu"`, and the `#mobile-menu` element becomes visible.
4. Tap the hamburger button again.
   - **Expected:** `aria-expanded` changes back to `"false"`. The `#mobile-menu` element is hidden.

### Pass Criteria
- [ ] `aria-expanded` is "false" when menu is closed
- [ ] `aria-expanded` is "true" when menu is open
- [ ] `aria-controls` references the correct menu element ID

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# SECTION 4: ACCESSIBILITY (B-056 through B-067)

---

## Scenario B-056: All interactive elements have aria-labels
**Priority:** Critical
**Feature:** Accessibility -- ARIA Labels
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads successfully.
2. Using DevTools, run this in the console: `document.querySelectorAll('button:not([aria-label]), a.btn:not([aria-label])').length`
   - **Expected:** The result is 0, or any buttons without labels are purely decorative.
3. Inspect specific interactive elements:
   - Hamburger button: should have `aria-label="Abrir menu de navegacion"`
   - Batch selection toggle: should have `aria-label="Activar seleccion multiple"`
   - View toggle buttons: should have `aria-label="Vista compacta"` and `aria-label="Vista expandida"`
   - Metric cards: should have `aria-label` describing their navigation target (e.g., "Ver gastos del ano completo")
4. Navigate to `http://localhost:3000/expenses` at 375px viewport.
5. Inspect expense card elements.
   - **Expected:** Each card has an `aria-label` like "Merchant Name 1,234" describing the expense. Action buttons inside cards have `aria-label` attributes: "Categorizar gasto", "Cambiar estado del gasto", "Editar gasto", "Eliminar gasto".

### Pass Criteria
- [ ] Hamburger button has aria-label
- [ ] Metric cards have descriptive aria-labels
- [ ] View toggle buttons have aria-labels
- [ ] Mobile card action buttons have aria-labels
- [ ] Expense cards have descriptive aria-labels

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-057: Tab navigation through page elements
**Priority:** Critical
**Feature:** Accessibility -- Keyboard Navigation
**Preconditions:** User is logged in. Viewport at 1280px.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Press Tab repeatedly from the top of the page.
   - **Expected:** Focus moves through elements in a logical order:
     1. Skip link ("Saltar al contenido principal")
     2. Skip link ("Saltar a la navegacion")
     3. Logo/home link
     4. Nav links (Dashboard, Gastos, Categorizar, etc.)
     5. "Nuevo Gasto" button
     6. Main content interactive elements (sync buttons, metric cards, etc.)
3. Verify that every focused element shows a visible focus indicator.
   - **Expected:** Each element has a visible outline or ring when focused (no `outline: none` without replacement).
4. Press Shift+Tab to move focus backwards.
   - **Expected:** Focus moves in reverse order through the same elements.

### Pass Criteria
- [ ] Tab order follows a logical sequence
- [ ] All interactive elements are reachable via Tab
- [ ] Visible focus indicators on every focused element
- [ ] Shift+Tab reverses the tab order

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-058: Screen reader landmarks present
**Priority:** High
**Feature:** Accessibility -- Landmarks
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Using DevTools, inspect the landmark roles in the page.
   - **Expected:** The following landmarks are present:
     - `<nav>` element with `role="navigation"` and `aria-label="Navegacion principal"` (id `main-navigation`)
     - `<main>` element with `role="main"` (id `main-content`)
     - Mobile nav menu has `role="navigation"` and `aria-label="Menu de navegacion movil"`
3. Check for an `aria-live` polite region.
   - **Expected:** An element with `id="accessibility-status"` exists with `role="status"` and `aria-live="polite"`.
4. Check for an `aria-live` assertive region.
   - **Expected:** An element with `id="accessibility-alerts"` exists with `role="alert"` and `aria-live="assertive"`.

### Pass Criteria
- [ ] `<nav>` landmark with correct aria-label exists
- [ ] `<main>` landmark with `role="main"` exists
- [ ] Polite live region (`accessibility-status`) exists
- [ ] Assertive live region (`accessibility-alerts`) exists

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-059: Color contrast meets WCAG 2.1 AA
**Priority:** High
**Feature:** Accessibility -- Color Contrast
**Preconditions:** User is logged in. Chrome DevTools or axe DevTools extension installed.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Open DevTools and run a Lighthouse Accessibility audit (or use axe DevTools extension).
   - **Expected:** No color contrast failures are reported for text elements.
3. Manually check critical text elements:
   - Primary metric card: white text on teal-700/teal-800 gradient
   - Secondary metric cards: slate-900 text on white background
   - Navigation links: slate-600 text on white background
   - Status badges: amber-800 on amber-100, rose-800 on rose-100
4. Verify contrast ratios.
   - **Expected:** All text meets minimum 4.5:1 contrast ratio for normal text, 3:1 for large text (WCAG 2.1 AA).

### Pass Criteria
- [ ] No contrast failures in automated audit
- [ ] Primary card white-on-teal meets ratio
- [ ] Body text (slate-900 on white) meets ratio
- [ ] Status badge text meets ratio

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-060: Focus indicators visible on keyboard navigation
**Priority:** High
**Feature:** Accessibility -- Focus Indicators
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Press Tab to focus the first interactive element.
   - **Expected:** A visible focus ring or outline appears around the element.
3. Continue tabbing through multiple elements (navigation links, buttons, metric cards).
   - **Expected:** Every focused element has a visible focus indicator. Common patterns: `focus:ring-2 focus:ring-teal-500`, `focus:outline-none focus:ring-2 focus:ring-offset-1`.
4. Navigate to the expense list at 375px and tab through mobile cards.
   - **Expected:** Cards show focus indicators when focused (they have `tabindex="0"`).

### Pass Criteria
- [ ] Navigation links show focus ring
- [ ] Buttons show focus ring
- [ ] Metric cards show focus indicator
- [ ] Mobile cards show focus indicator when focused

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-061: aria-expanded on collapsible sections
**Priority:** High
**Feature:** Accessibility -- Expandable Content
**Preconditions:** User is logged in. Viewport set to 375px.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Page loads.
2. Locate the "Filtrar" button and inspect its `aria-expanded` attribute.
   - **Expected:** `aria-expanded="false"` (filters are collapsed on mobile by default).
3. Tap the "Filtrar" button.
   - **Expected:** `aria-expanded` changes to `"true"`.
4. Tap the "Filtrar" button again.
   - **Expected:** `aria-expanded` changes back to `"false"`.
5. Locate the mobile hamburger button and verify its `aria-expanded` behavior (same as Scenario B-055).
   - **Expected:** Toggles between "true" and "false".

### Pass Criteria
- [ ] "Filtrar" button has `aria-expanded` that toggles
- [ ] Hamburger button has `aria-expanded` that toggles
- [ ] Values match the actual expanded/collapsed state

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-062: Mobile card checkbox has aria-label
**Priority:** Medium
**Feature:** Accessibility -- Mobile Cards
**Preconditions:** User is logged in. Viewport set to 375px. Selection mode active.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
2. Enter selection mode (long-press a card or simulate it).
   - **Expected:** Checkboxes appear on all cards.
3. Inspect a checkbox element.
   - **Expected:** The checkbox has `aria-label="Seleccionar gasto [merchant name]"` (where merchant name is the expense's merchant).

### Pass Criteria
- [ ] Each checkbox has a descriptive `aria-label`
- [ ] The label includes the merchant name for identification

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-063: Dashboard metric cards are keyboard navigable
**Priority:** High
**Feature:** Accessibility -- Keyboard Navigation
**Preconditions:** User is logged in. Viewport at 1280px.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Tab to the primary metric card (id `primary-metric-card`).
   - **Expected:** The card receives focus (it has `tabindex="0"` and `role="button"`). A visible focus indicator appears.
3. Press Enter while the card is focused.
   - **Expected:** The card navigates to the expenses list with the year period filter (same as clicking). The `data-action` includes `keydown.enter->dashboard-card-navigation#navigate`.
4. Go back and tab to the "Este Mes" card. Press Space.
   - **Expected:** The card navigates to the expenses list with the month period filter. The `data-action` includes `keydown.space->dashboard-card-navigation#navigate`.

### Pass Criteria
- [ ] Metric cards are focusable via Tab
- [ ] Enter key activates navigation on focused card
- [ ] Space key activates navigation on focused card
- [ ] Cards have `role="button"` attribute

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-064: Color is not the sole indicator of status
**Priority:** High
**Feature:** Accessibility -- Color Independence
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses` at 375px viewport.
   - **Expected:** Cards are displayed.
2. Find cards with different status badges.
   - **Expected:** Status badges include text labels, not just color:
     - Pending: "Pendiente" text (amber background)
     - Duplicate: "Duplicado" text (rose background)
     - Failed: "Fallido" text (rose background)
     - Processed: no badge (absence conveys status)
3. Check category indicators on cards.
   - **Expected:** Categories show both a colored dot AND the category name text. The category name provides the information even without color.

### Pass Criteria
- [ ] Status badges include text labels, not just color
- [ ] Category information includes text names, not just color dots
- [ ] A user who cannot perceive color can still understand the information

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-065: No blue color classes in rendered UI
**Priority:** Medium
**Feature:** Accessibility / Design System -- Financial Confidence Palette
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Open DevTools Console and run:
   ```javascript
   document.querySelectorAll('[class*="blue-"]').length
   ```
   - **Expected:** The result is `0`. No elements have `blue-` class names.
3. Navigate to `http://localhost:3000/expenses` and repeat the check.
   - **Expected:** The result is `0`.

### Pass Criteria
- [ ] No `blue-` classes found on the dashboard
- [ ] No `blue-` classes found on the expense list page
- [ ] All colors follow the Financial Confidence palette

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-066: SVG icons are accessible (aria-hidden or labeled)
**Priority:** Medium
**Feature:** Accessibility -- Icon Accessibility
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Inspect several SVG icons in the page (e.g., the hamburger icon, metric card icons, sync spinner).
   - **Expected:** Decorative SVG icons (icons next to text labels) have `aria-hidden="true"`. Standalone icons (without adjacent text) are contained in elements with `aria-label`.
3. Check the hamburger button's SVG specifically.
   - **Expected:** The SVG has `aria-hidden="true"` and the parent button has `aria-label="Abrir menu de navegacion"`.

### Pass Criteria
- [ ] Decorative SVGs have `aria-hidden="true"`
- [ ] Standalone icon buttons have `aria-label` on the button element
- [ ] Screen readers do not announce decorative icons

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario B-067: HTML lang attribute is set to Spanish
**Priority:** Medium
**Feature:** Accessibility -- Language Declaration
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses/dashboard`
   - **Expected:** Page loads.
2. Inspect the `<html>` element.
   - **Expected:** The `<html>` tag has `lang="es"` attribute, correctly declaring the page language as Spanish for screen readers.

### Pass Criteria
- [ ] `<html lang="es">` is present in the document
- [ ] Language declaration matches the UI language (Spanish)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# APPENDIX

## Viewport Cheat Sheet

| Breakpoint | Width | Layout Behavior |
|---|---|---|
| Mobile | 375px | Cards visible, table hidden, hamburger menu, filters collapsed |
| Tablet | 768px | Table visible, cards hidden, desktop nav, filters expanded (`md:` breakpoint) |
| Small Desktop | 1024px | Two-column chart grid (`lg:` breakpoint) |
| Full Desktop | 1280px | Maximum container width, all features visible |

## Key Element IDs and Selectors

| Element | Selector | Purpose |
|---|---|---|
| Primary metric card | `#primary-metric-card` | Year total, navigates to yearly expenses |
| Month metric card | `#month-metric-card` | Monthly total, navigates to monthly expenses |
| Week metric card | `#week-metric-card` | Weekly total, navigates to weekly expenses |
| Day metric card | `#day-metric-card` | Today's total, navigates to daily expenses |
| Recent expenses widget | `#dashboard-expenses-widget` | Container for dashboard expense list |
| Mobile card container | `#expense_cards` | Visible below 768px on expense index |
| Desktop table container | `#expense_list` | Visible at 768px and above on expense index |
| Main navigation | `#main-navigation` | Top nav bar |
| Mobile menu | `#mobile-menu` | Hidden dropdown nav for mobile |
| Main content | `#main-content` | Skip-link target |
| Accessibility status | `#accessibility-status` | Live region for polite announcements |
| Accessibility alerts | `#accessibility-alerts` | Live region for assertive announcements |

## Stimulus Controllers Referenced

| Controller | File | Purpose |
|---|---|---|
| `mobile-card` | `mobile_card_controller.js` | Card tap/expand, long-press selection, action buttons |
| `collapsible-filter` | `collapsible_filter_controller.js` | Toggle filter/summary visibility |
| `view-toggle` | `view_toggle_controller.js` | Compact/expanded view toggle on expense list |
| `mobile-nav` | `mobile_nav_controller.js` | Hamburger menu open/close |
| `dashboard-expenses` | `dashboard_expenses_controller.js` | Dashboard expense widget, batch selection, view mode |
| `dashboard-filter-chips` | `dashboard_filter_chips_controller.js` | Category/status/period filter chips |
| `dashboard-card-navigation` | `dashboard_card_navigation_controller.js` | Metric card click-to-navigate |

## Total Scenario Count

| Section | Scenarios | Range |
|---|---|---|
| Dashboard | 20 | B-001 to B-020 |
| Mobile Card Layout (PER-133) | 20 | B-021 to B-040 |
| Navigation & Layout | 15 | B-041 to B-055 |
| Accessibility | 12 | B-056 to B-067 |
| **Total** | **67** | B-001 to B-067 |
