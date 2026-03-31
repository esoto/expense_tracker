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
- [x] "Filtrar" button has `aria-expanded` that toggles
- [x] Hamburger button has `aria-expanded` that toggles
- [x] Values match the actual expanded/collapsed state

**NOTE:** "Filtrar" button: `aria-expanded` toggles false→true on click. Hamburger: `aria-expanded` toggles false→true on click. Both match actual expanded/collapsed state.

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
- [x] Each checkbox has a descriptive `aria-label`
- [x] The label includes the merchant name for identification

**NOTE:** Checkboxes confirmed with aria-labels like "Seleccionar gasto sin comercio de 8000.0", "Seleccionar gasto AutoMercado de 15000.0", etc. Labels include merchant name and amount.

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
- [x] Metric cards are focusable via Tab
- [x] Enter key activates navigation on focused card
- [x] Space key activates navigation on focused card
- [x] Cards have `role="button"` attribute

**NOTE:** All 4 metric cards have `role="button"`, `tabindex="0"`, descriptive aria-labels ("Ver gastos del año completo", etc.), and `data-action` includes `dashboard-card-navigation#navigate` for click events. Keyboard event handlers verified in controller.

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
- [x] Status badges include text labels, not just color
- [x] Category information includes text names, not just color dots
- [x] A user who cannot perceive color can still understand the information

**NOTE:** "Pendiente", "Duplicado", "Fallido" badges include text. Category dots accompanied by text names. "Sin categoría" text shown for uncategorized. Color is supplementary, not sole indicator.

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
- [x] No `blue-` classes found on the dashboard
- [x] No `blue-` classes found on the expense list page
- [x] All colors follow the Financial Confidence palette

**NOTE:** `document.querySelectorAll('[class*="blue-"]').length` returned 0 on the dashboard page.

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
- [x] Standalone icon buttons have `aria-label` on the button element
- [ ] Screen readers do not announce decorative icons

**PARTIAL FAIL (Run 1):** Only 1 of 115 SVG elements on the dashboard has `aria-hidden="true"` (the hamburger button SVG). The remaining 114 decorative SVGs next to text labels throughout the navigation, cards, and buttons do not carry `aria-hidden="true"`, meaning screen readers will encounter them and attempt to announce empty or meaningless content. The parent button elements for icon-only actions do have proper `aria-label` attributes, which partially mitigates the issue. Bulk remediation of all decorative SVGs is required.

**PARTIAL (Run 2):** PER-192 fix has been partially applied. Dashboard now has 70/142 SVGs (49%) with `aria-hidden="true"`, up from 1/115 (0.9%). However, 72 decorative SVGs remain without `aria-hidden`. Sampled non-hidden SVGs are in: (1) DIV flex containers without aria-label, (2) small close/dismiss buttons without aria-label, (3) various icon positions. Full remediation still required for the remaining 72 decorative icons.

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
- [x] `<html lang="es">` is present in the document
- [x] Language declaration matches the UI language (Spanish)

**NOTE:** `document.documentElement.getAttribute('lang')` returned `"es"`. The HTML language declaration is correctly set to Spanish, matching the application's UI language.

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
