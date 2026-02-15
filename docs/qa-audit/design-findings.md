# Design/UX Audit Findings - Expense Tracker

**Audit Date:** 2026-02-14
**Auditor:** Design/UX Reviewer
**Application:** Rails 8.1 Expense Tracker
**Design System:** Financial Confidence Color Palette

---

## Executive Summary

This audit reviewed the entire expense tracker application for design consistency, color palette compliance, responsive design, Spanish localization, interaction patterns, and accessibility. The application has a solid foundation with good palette compliance in the core production views (dashboard, expense list, sync sessions). However, significant issues exist in the admin/categorization sections which are almost entirely in English, violating the Spanish localization requirement. Additionally, several mockup files contain forbidden blue classes that should be cleaned up or removed.

### Summary Statistics

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 3 | Forbidden blue color usage in mockup files, full English pages, navigation not responsive |
| HIGH | 14 | Hardcoded English text in production views, off-palette colors, missing i18n |
| MEDIUM | 8 | Inconsistent component patterns, minor color deviations, English in JS controllers |
| LOW | 5 | Development-only English strings, minor text issues, non-blocking improvements |
| **TOTAL** | **30** | |

---

## Category 1: Color Palette Violations

### CRITICAL-1: Forbidden `blue-` Classes in Mockup Files

**Severity:** CRITICAL
**Epic Affected:** All (Mockup/Reference files)
**Files:**
- `/app/views/expenses/sync_status_mockup.html.erb` (12 occurrences)
- `/app/views/expenses/mobile_expense_card_mockup.html.erb` (13 occurrences)
- `/app/views/expenses/inline_category_mockup.html.erb` (25 occurrences)
- `/app/views/expenses/color_palette_mockup.html.erb` (8 occurrences)
- `/app/views/ux_mockups/index.html.erb` (3 occurrences)

**Description:** Over 60 instances of forbidden `blue-` classes exist across mockup files. These include `bg-blue-600`, `text-blue-700`, `bg-blue-100`, `border-blue-500`, `hover:text-blue-900`, etc. While these are mockup files, they serve as reference implementations and could mislead developers.

**Visual Impact:** Mockup files display blue-themed UI elements instead of the mandated teal-based Financial Confidence palette. A developer referencing these mockups would implement incorrect colors.

**Recommended Fix:**
- Option A: Delete all mockup files as they are no longer needed (production views exist)
- Option B: Replace all `blue-` references with the palette equivalent:
  - `blue-600` / `blue-700` -> `teal-700`
  - `blue-100` -> `teal-100`
  - `blue-50` -> `teal-50`
  - `blue-500` -> `teal-500`
  - `blue-900` -> `teal-900` / `slate-900`

---

### HIGH-1: `red-` Classes Used Instead of `rose-` in Mockup

**Severity:** HIGH
**Epic Affected:** Epic 1 (Sync Status)
**File:** `/app/views/expenses/sync_status_mockup.html.erb`, lines 168-182
**Description:** Error states use `red-` classes (`bg-red-50`, `text-red-600`, `bg-red-100`, `border-red-200`, `bg-red-600`) instead of the mandated `rose-` equivalents.

**Recommended Fix:** Replace:
- `red-50` -> `rose-50`
- `red-100` -> `rose-100`
- `red-200` -> `rose-200`
- `red-600` -> `rose-600`
- `red-700` -> `rose-700`
- `red-900` -> `rose-900`

---

### HIGH-2: `green-` Classes Used Instead of `emerald-` in Mockups

**Severity:** HIGH
**Epic Affected:** Epic 1 (Sync Status), Categorization
**Files:**
- `/app/views/expenses/sync_status_mockup.html.erb` (15 occurrences)
- `/app/views/expenses/inline_category_mockup.html.erb` (10 occurrences)
- `/app/views/ux_mockups/index.html.erb` (10 occurrences)

**Description:** Success states use `green-` classes (`bg-green-100`, `text-green-600`, `bg-green-400`, `bg-green-50`) instead of the mandated `emerald-` equivalents.

**Recommended Fix:** Replace all `green-*` with `emerald-*` equivalents.

---

### HIGH-3: `gray-` Classes Used Instead of `slate-`

**Severity:** HIGH
**Epic Affected:** All (Mockup files)
**Files:**
- `/app/views/expenses/color_palette_mockup.html.erb` (30+ occurrences)
- `/app/views/expenses/sync_status_mockup.html.erb` (2 occurrences)
- `/app/views/ux_mockups/index.html.erb` (25+ occurrences)
- `/app/views/expenses/inline_category_mockup.html.erb` (5 occurrences)

**Description:** Neutral colors use `gray-` classes instead of the mandated `slate-` equivalents. `gray-900`, `gray-600`, `gray-400`, `gray-200`, `gray-300` should all be `slate-` variants.

**Recommended Fix:** Replace all `gray-*` with `slate-*` equivalents.

---

### HIGH-4: `indigo-` and `violet-` Classes in Color Palette Mockup

**Severity:** HIGH
**Epic Affected:** N/A (Mockup file)
**File:** `/app/views/expenses/color_palette_mockup.html.erb` (25+ occurrences)

**Description:** The color palette mockup contains indigo and violet color classes that were part of alternative palette proposals that were NOT adopted. These off-palette colors (`indigo-600`, `violet-500`, `violet-600`, etc.) are present alongside the chosen Financial Confidence palette.

**Recommended Fix:** Remove or clearly label the non-selected palette sections, or delete the mockup file entirely since the Financial Confidence palette has been chosen and implemented.

---

### HIGH-5: `purple-` Classes in Mockup Files

**Severity:** HIGH
**Epic Affected:** Categorization (Mockup)
**Files:**
- `/app/views/ux_mockups/index.html.erb`, lines 101-135
- `/app/views/expenses/inline_category_mockup.html.erb`, lines 70-249

**Description:** Purple color classes used for categorization-related elements. These should use teal or the palette's designated colors.

**Recommended Fix:** Replace `purple-*` with `teal-*` or appropriate palette equivalents.

---

### MEDIUM-1: BAC Bank Badge Uses `rose-100` / `rose-700`

**Severity:** MEDIUM
**Epic Affected:** Epic 3 (Expense List)
**File:** `/app/views/expenses/_expense_row.html.erb`, line 191

**Description:** The BAC bank badge uses `bg-rose-100 text-rose-700`, which visually associates BAC with error/critical styling. While technically on-palette, using rose for a bank identifier is semantically misleading since rose is reserved for errors and critical actions.

**Recommended Fix:** Use a neutral badge or bank-specific colors that don't conflict with semantic palette meanings:
```erb
<%= expense.bank_name == 'BAC' ? 'bg-teal-100 text-teal-700' : 'bg-slate-100 text-slate-700' %>
```

---

## Category 2: Spanish Localization Violations

### CRITICAL-2: Admin Patterns Section Entirely in English

**Severity:** CRITICAL
**Epic Affected:** Categorization System
**Files:**
- `/app/views/admin/patterns/index.html.erb` - Full page in English
- `/app/views/admin/patterns/show.html.erb` - Full page in English
- `/app/views/admin/patterns/_form.html.erb` - Full page in English
- `/app/views/admin/patterns/_pattern_row.html.erb`
- `/app/views/admin/patterns/test.html.erb`

**Hardcoded English Strings Found:**
| Line | File | English Text |
|------|------|-------------|
| 5 | index.html.erb | "Categorization Patterns" |
| 6 | index.html.erb | "Manage automatic expense categorization rules" |
| 13 | index.html.erb | "New Pattern" |
| 19 | index.html.erb | "Test Patterns" |
| 25 | index.html.erb | "Import" |
| 46 | index.html.erb | "Total Patterns" |
| 60 | index.html.erb | "Active Patterns" |
| 74 | index.html.erb | "Avg Success Rate" |
| 89 | index.html.erb | "Total Usage" |
| 104 | index.html.erb | "Search patterns or categories..." |
| 122 | index.html.erb | "All Categories" |
| 150-177 | index.html.erb | "Type", "Pattern", "Category", "Usage", "Success Rate", "Confidence", "Status", "Actions" |
| 198 | index.html.erb | "Pattern Performance Over Time" |
| 211 | index.html.erb | "Import Patterns from CSV" |
| 215 | index.html.erb | "Select CSV File" |
| 229 | index.html.erb | "Cancel" |

**Recommended Fix:** Replace all English strings with Spanish translations. Either hardcode Spanish or use I18n keys from `config/locales/es.yml`.

---

### CRITICAL-3: Analytics Pattern Dashboard Entirely in English

**Severity:** CRITICAL  (combined into one as it's part of the same domain)
**Epic Affected:** Categorization System
**Files:**
- `/app/views/analytics/pattern_dashboard/index.html.erb`
- `/app/views/analytics/pattern_dashboard/_overall_metrics.html.erb`
- `/app/views/analytics/pattern_dashboard/_category_performance.html.erb`
- `/app/views/analytics/pattern_dashboard/_pattern_type_analysis.html.erb`
- `/app/views/analytics/pattern_dashboard/_recent_activity.html.erb`

**Hardcoded English Strings Found (sampling):**
| Location | English Text |
|----------|-------------|
| index.html.erb:6 | "Pattern Analytics Dashboard" |
| index.html.erb:7 | "Monitor and optimize categorization pattern performance" |
| index.html.erb:16-20 | "Last 7 Days", "Last 30 Days", "Last 3 Months", "Last Year", "Today" |
| index.html.erb:27 | "All Categories" |
| index.html.erb:40 | "All Types" |
| index.html.erb:56 | "Export" |
| index.html.erb:95 | "Performance Trends" |
| index.html.erb:100-111 | "Daily", "Weekly", "Monthly" |
| index.html.erb:126 | "Top Performing Patterns" |
| index.html.erb:160 | "Patterns Needing Improvement" |
| index.html.erb:195 | "Pattern Usage Heatmap" |
| index.html.erb:208 | "Learning Progress" |
| _overall_metrics.html.erb:6 | "Total Patterns" |
| _overall_metrics.html.erb:24 | "Overall Accuracy" |
| _overall_metrics.html.erb:44 | "Total Usage" |
| _overall_metrics.html.erb:62 | "Avg Confidence" |
| _recent_activity.html.erb:1 | "Recent Activity" |
| _recent_activity.html.erb:7 | "ago" (should be Spanish time formatting) |
| _recent_activity.html.erb:14 | "No description" |
| _recent_activity.html.erb:35 | "No recent activity to display" |

**Recommended Fix:** Translate all strings to Spanish. These are user-facing production views.

---

### HIGH-6: Bulk Categorization Pages in English

**Severity:** HIGH
**Epic Affected:** Categorization System
**Files:**
- `/app/views/bulk_categorizations/index.html.erb`
- `/app/views/bulk_categorizations/_statistics.html.erb`
- `/app/views/bulk_categorizations/_expense_groups.html.erb`
- `/app/views/bulk_categorizations/show.html.erb`

**English Strings Found:**
| Location | English Text |
|----------|-------------|
| index.html.erb:7 | "Bulk Categorization" |
| index.html.erb:8 | "Review and categorize multiple similar expenses at once" |
| index.html.erb:16 | "Export Report" |
| index.html.erb:24 | "Auto-Categorize High Confidence" |
| index.html.erb:45 | "Processing..." |
| index.html.erb:63 | "All Caught Up!" |
| index.html.erb:64 | "No uncategorized expenses to review." |
| _statistics.html.erb:11-51 | "Total Groups", "Total Expenses", "High Confidence", "Total Amount" |
| _expense_groups.html.erb:22 | "confidence" |
| _expense_groups.html.erb:33 | "expense/expenses" (English pluralization) |
| _expense_groups.html.erb:51 | "Suggested:" |
| _expense_groups.html.erb:64 | "Apply Suggestion" |
| _expense_groups.html.erb:78 | "Select a category..." |
| _expense_groups.html.erb:94 | "Apply to All" |
| _expense_groups.html.erb:107 | "Preview" |
| _expense_groups.html.erb:158 | "Use group category" |
| show.html.erb:2 | "Bulk Operation Details" |
| show.html.erb:5 | "Operation Summary" |
| show.html.erb:10 | "Affected Expenses" |

**Recommended Fix:** Translate all strings to Spanish.

---

### HIGH-7: Admin Login Page in English

**Severity:** HIGH
**Epic Affected:** Infrastructure
**Files:**
- `/app/views/admin/sessions/new.html.erb`
- `/app/views/layouts/admin_login.html.erb`

**English Strings Found:**
- "Remember me" (line 24)
- "Need help? Contact IT" (line 30)
- "Sign In" (line 35)
- "This admin area is secured and monitored. Unauthorized access is prohibited." (line 46)
- "Secure admin access" (admin_login.html.erb:44)

**Recommended Fix:** Translate all user-facing strings to Spanish.

---

### HIGH-8: Queue Visualization Widget in English

**Severity:** HIGH
**Epic Affected:** Epic 1 (Sync Status)
**File:** `/app/views/sync_sessions/_queue_visualization.html.erb`

**English Strings Found:**
| Line | English Text |
|------|-------------|
| 11 | "Background Job Queue" |
| 15 | "Checking..." |
| 24 | "Refresh now" (title attribute) |
| 38 | "Pause All" |
| 49 | "Pending" |
| 55 | "Waiting to process" |
| 61 | "Processing" |
| 68 | "Currently running" |
| 74 | "Completed" |
| 80 | "Last 24 hours" |
| 86 | "Failed" |
| 97 | "Retry all" |
| 98 | "No failures" |
| 107 | "Queue Depth" |
| 133 | "Queue Distribution" |
| 146 | "Currently Processing" |
| 162 | "Failed Jobs" |
| 166 | "Clear All" |
| 183 | "Workers:" |
| 187 | "Utilization:" |
| 197 | "Never" (last update) |

**Recommended Fix:** Translate all strings to Spanish.

---

### HIGH-9: English "ago" in Time Displays

**Severity:** HIGH
**Epic Affected:** Multiple
**Files:**
- `/app/views/expenses/show.html.erb`, lines 133, 141: `"ago"` after `time_ago_in_words`
- `/app/views/analytics/pattern_dashboard/_recent_activity.html.erb`, line 7: `"ago"`
- `/app/views/admin/patterns/show.html.erb`, line 203: `"ago"`

**Description:** The word "ago" appears in English alongside `time_ago_in_words()`. When the Rails locale is set to Spanish, `time_ago_in_words` should output in Spanish, but the hardcoded "ago" suffix remains in English.

**Recommended Fix:** Replace `"ago"` with the Spanish equivalent or use i18n:
```erb
<%= time_ago_in_words(@expense.created_at) %> atr<C3><A1>s
```
Note: Some views (like `sync_sessions/index.html.erb` line 103) already correctly use "atras" - follow that pattern.

---

### HIGH-10: "Expense Tracker" Brand Name Not Localized in Titles

**Severity:** MEDIUM
**Epic Affected:** All
**Files:**
- `/app/views/layouts/application.html.erb`, lines 4, 61, 63
- `/app/views/expenses/index.html.erb`, line 1
- `/app/views/expenses/dashboard.html.erb`, line 1
- `/app/views/expenses/show.html.erb`, line 1
- `/app/views/expenses/new.html.erb`, line 1
- `/app/views/expenses/edit.html.erb`, line 1

**Description:** The application brand name "Expense Tracker" appears in English throughout. While brand names are sometimes kept in English by design, this should be a deliberate decision. If the app is targeting Costa Rican users, a Spanish brand name or "Rastreador de Gastos" could be considered.

**Note:** This may be intentional as a brand name. Marking as MEDIUM since it's a design decision rather than an oversight.

---

### HIGH-11: "Unknown Merchant" in English

**Severity:** HIGH
**Epic Affected:** Epic 2 (Dashboard)
**File:** `/app/views/expenses/dashboard.html.erb`, line 422

**Description:** `"Unknown Merchant"` is hardcoded in English as a fallback when merchant name is nil.

**Recommended Fix:**
```erb
<%= merchant&.truncate(30) || "Comercio desconocido" %>
```

---

### HIGH-12: Shared Errors Partial in English

**Severity:** HIGH
**Epic Affected:** All
**File:** `/app/views/shared/_errors.html.erb`, line 2

**Description:** `"Please fix the following errors:"` is hardcoded in English.

**Recommended Fix:**
```erb
<h3 class="font-semibold mb-2">Por favor corrige los siguientes errores:</h3>
```

---

### HIGH-13: Pattern Form All in English

**Severity:** HIGH
**Epic Affected:** Categorization System
**File:** `/app/views/admin/patterns/_form.html.erb`

**English Strings:** "Please fix the following errors:", "Select pattern type...", "Choose how this pattern will match expenses", "Enter pattern value...", all help text for pattern types, "Category", "Select category...", "The category to assign when this pattern matches", "Higher weight = higher priority...", "Active", "Inactive patterns won't be used...", "Test Pattern", "Enter test text...", "Test Match", "Cancel", "Save and Continue Editing", "Create Pattern", "Update Pattern"

**Recommended Fix:** Translate all strings to Spanish.

---

### MEDIUM-2: Queue Monitor Controller English Strings in JS

**Severity:** MEDIUM
**Epic Affected:** Epic 1 (Sync Status)
**File:** `/app/views/../javascript/controllers/queue_monitor_controller.js`

**English Strings in Dynamic Content:**
- Line 204: `"${rate.toFixed(1)} jobs/min"` -> Should be `"trabajos/min"`
- Line 210: `"~${minutes} min remaining"` -> `"~${minutes} min restante"`
- Line 214: `"~${hours}h ${mins}m remaining"` -> `"~${hours}h ${mins}m restante"`
- Line 217: `"No backlog"` -> `"Sin pendientes"`
- Line 227: `"Resume All"` -> `"Reanudar todo"`
- Line 234: `"Pause All"` -> `"Pausar todo"`
- Line 254: `"Just started"` -> `"Recien iniciado"`
- Line 372: `"Operation failed"` -> `"Operacion fallida"`
- Line 485: `"Updated ${timeStr}"` -> `"Actualizado ${timeStr}"`
- Line 499-507: `"Unknown error"` -> `"Error desconocido"`

**Recommended Fix:** Either use I18n-js library or hardcode Spanish equivalents in the controller.

---

### MEDIUM-3: Development Performance Strings in English

**Severity:** LOW
**Epic Affected:** Epic 3
**File:** `/app/views/expenses/dashboard.html.erb`, lines 541-553

**Description:** Performance metrics section visible in development environment shows English: "Performance:", "query time", "queries", "rows", "Index used", "No index". These are dev-only but should still follow language conventions.

**Recommended Fix:** While dev-only, translate for consistency or gate behind a specific dev tool.

---

## Category 3: Responsive Design Issues

### CRITICAL-4: Navigation Bar Not Responsive

**Severity:** CRITICAL
**Epic Affected:** All
**File:** `/app/views/layouts/application.html.erb`, lines 49-93

**Description:** The main navigation bar displays all links horizontally with no hamburger menu, mobile drawer, or responsive collapsing behavior. On mobile screens (< 768px), the 7 navigation links ("Dashboard", "Gastos", "Categorizar", "Analytics", "Cuentas", "Sincronizacion", "Patrones") plus the "Nuevo Gasto" button will overflow horizontally, creating a broken layout.

**Visual Impact:** On mobile, navigation links wrap awkwardly or extend beyond the viewport, making the app unusable on phones.

**Recommended Fix:** Implement a responsive navigation with:
```erb
<!-- Mobile hamburger button (visible on small screens) -->
<button class="md:hidden" data-action="click->navbar#toggle">
  <svg><!-- hamburger icon --></svg>
</button>

<!-- Desktop navigation (hidden on mobile) -->
<div class="hidden md:flex items-center space-x-4">
  <!-- existing links -->
</div>

<!-- Mobile menu (hidden by default, toggled by hamburger) -->
<div class="md:hidden hidden" data-navbar-target="mobileMenu">
  <!-- vertical stack of links -->
</div>
```

---

### HIGH-14: Dashboard Metric Cards Grid on Small Screens

**Severity:** MEDIUM
**Epic Affected:** Epic 2 (Enhanced Metrics)
**File:** `/app/views/expenses/dashboard.html.erb`, lines 275-288

**Description:** The "Additional Stats" grid inside the primary metric card uses `grid-cols-3` without responsive breakpoints. On very narrow screens, the three columns ("Transacciones", "Promedio", "Categorias") could become too cramped with large numbers.

**Recommended Fix:**
```erb
<div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-6 pt-6 border-t border-white/20">
```

---

### MEDIUM-4: Expense Table Not Fully Mobile-Optimized

**Severity:** MEDIUM
**Epic Affected:** Epic 3 (Expense List)
**File:** `/app/views/expenses/index.html.erb`, lines 165-192

**Description:** While the table has `overflow-x-auto` for horizontal scrolling, there is no mobile card layout alternative. Users on mobile must scroll horizontally through a 7-column table, which is not ideal UX.

**Recommended Fix:** Consider implementing a card-based layout for mobile using responsive classes:
```erb
<!-- Desktop: Table, Mobile: Cards -->
<div class="hidden md:block overflow-x-auto">
  <table><!-- existing table --></table>
</div>
<div class="md:hidden space-y-3">
  <!-- Card-based layout for each expense -->
</div>
```

---

### MEDIUM-5: Filter Form Stacking on Mobile

**Severity:** MEDIUM
**Epic Affected:** Epic 3
**File:** `/app/views/expenses/index.html.erb`, lines 54-79

**Description:** The filter form uses `md:flex md:gap-4` which properly stacks on mobile. However, the date fields on mobile are displayed side-by-side with `flex gap-2` which may make them too narrow on small screens.

**Recommended Fix:**
```erb
<div class="flex flex-col sm:flex-row gap-2">
```

---

## Category 4: Component Consistency

### MEDIUM-6: Inconsistent Card Border Radius

**Severity:** LOW
**Epic Affected:** Multiple
**Description:** Most cards consistently use `rounded-xl` but some use `rounded-lg`:
- `/app/views/expenses/index.html.erb` line 38: summary stat boxes use `rounded-lg` instead of `rounded-xl`
- `/app/views/sync_sessions/show.html.erb` line 211: account detail cards use `rounded-lg`

**Recommended Fix:** Standardize all cards to `rounded-xl` per the design system.

---

### MEDIUM-7: Edit Button Uses `amber-600` Instead of `teal-700` for Primary Action

**Severity:** MEDIUM
**Epic Affected:** Categorization
**File:** `/app/views/admin/patterns/show.html.erb`, line 10

**Description:** The Edit button on the pattern detail page uses `bg-amber-600 hover:bg-amber-700` which is the warning/secondary color. Edit is a primary action and should use teal.

**Recommended Fix:**
```erb
class: "bg-teal-700 hover:bg-teal-800 text-white px-4 py-2 rounded-lg text-sm font-medium"
```

---

### MEDIUM-8: Currency Symbol Inconsistency

**Severity:** MEDIUM
**Epic Affected:** Categorization
**File:** `/app/views/analytics/pattern_dashboard/_recent_activity.html.erb`, line 22

**Description:** Uses `$` as currency prefix instead of the Costa Rican colon symbol used everywhere else in the app.

**Recommended Fix:**
```erb
<%= number_to_currency(activity[:expense_amount], unit: "&#8353;", precision: 0) %>
```
Or simply use the consistent format from other views.

---

## Category 5: Interaction Patterns

### LOW-1: Missing Loading States in Dashboard Cards

**Severity:** LOW
**Epic Affected:** Epic 2 (Enhanced Metrics)
**File:** `/app/views/expenses/dashboard.html.erb`

**Description:** Dashboard metric cards have animated number counters (via `animated-metric` controller) but no skeleton/loading placeholder visible before JavaScript initializes. On slow connections, users see static numbers that then "animate" after JS loads.

**Recommended Fix:** Add skeleton loading states:
```erb
<div class="animate-pulse bg-slate-200 h-8 w-32 rounded" data-animated-metric-target="skeleton"></div>
```

---

### LOW-2: Empty State Text Not Actionable in Bulk Categorization

**Severity:** LOW
**Epic Affected:** Categorization
**File:** `/app/views/bulk_categorizations/index.html.erb`, lines 62-65

**Description:** Empty state says "All Caught Up! No uncategorized expenses to review." (in English) but provides no action button to navigate elsewhere or sync more expenses.

**Recommended Fix:** Add a CTA button:
```erb
<%= link_to "Volver al Dashboard", dashboard_expenses_path,
    class: "mt-4 inline-flex items-center px-4 py-2 bg-teal-700 text-white rounded-lg..." %>
```

---

## Category 6: Accessibility

### MEDIUM-9: Focus Indicators Not Visible on Some Interactive Elements

**Severity:** MEDIUM
**Epic Affected:** Multiple
**Description:** While the application has good ARIA labels and keyboard navigation support in Epic 3 components, some interactive elements in the admin/categorization sections lack explicit focus ring styling. The default browser focus indicator may be insufficient for WCAG 2.1 AA compliance.

**Files Affected:**
- `/app/views/admin/patterns/index.html.erb` - sort links lack focus styles
- `/app/views/analytics/pattern_dashboard/index.html.erb` - filter buttons lack `focus:ring-*`

**Recommended Fix:** Add `focus:outline-none focus:ring-2 focus:ring-offset-1 focus:ring-teal-500` to all interactive elements.

---

### LOW-3: Navigation "Analytics" Link in English

**Severity:** LOW
**Epic Affected:** All
**File:** `/app/views/layouts/application.html.erb`, line 75

**Description:** The navigation link text "Analytics" is in English while all other nav items are in Spanish.

**Recommended Fix:** Change to "Analiticas" or "Estadisticas".

---

### LOW-4: Date Format Not Consistent with Costa Rican Locale

**Severity:** LOW
**Epic Affected:** Categorization
**File:** `/app/views/bulk_categorizations/_expense_groups.html.erb`, line 143

**Description:** Date format uses `"%b %d, %Y"` which outputs English month abbreviations (e.g., "Jan 15, 2026"). Costa Rican locale should use `"%d/%m/%Y"` or localized month names.

**Recommended Fix:**
```erb
<%= expense.transaction_date.strftime("%d/%m/%Y") %>
```
Or use `l(expense.transaction_date, format: :short)` with proper locale.

---

### LOW-5: Performance Metrics Label in English on Dashboard

**Severity:** LOW
**Epic Affected:** Epic 3
**File:** `/app/views/expenses/dashboard.html.erb`, line 548

**Description:** `"Index used"` and `"No index"` messages are in English (development-only visibility).

---

## Category 7: Information Architecture

### General Observations

**Navigation Hierarchy:** The navigation bar contains 7 top-level items plus the "Nuevo Gasto" CTA. This is a reasonable number for desktop but problematic on mobile (see CRITICAL-4). The grouping of items is logical: Dashboard -> Gastos -> Categorizar -> Analytics -> Cuentas -> Sincronizacion -> Patrones.

**Visual Weight Distribution:** The primary metric card (teal gradient, 1.5x larger) correctly draws the most attention on the dashboard. Secondary metric cards have appropriate hover effects (`hover:shadow-lg hover:-translate-y-1 hover:border-teal-300`) that create clear interactive affordances.

**Progressive Disclosure:** The expense table uses view toggle (compact/expanded) and collapsible filter chips well. The category dropdown in inline actions uses proper progressive disclosure. Sync session details use accordion-like expandable sections appropriately.

---

## Recommendations Summary (Prioritized)

### Immediate Action Required (Sprint 1)

1. **Fix Navigation Responsiveness** (CRITICAL-4) - Add mobile hamburger menu
2. **Translate Admin Patterns pages** (CRITICAL-2) - All views in English
3. **Translate Analytics Dashboard** (CRITICAL-3) - All views in English
4. **Translate Bulk Categorization** (HIGH-6) - Most views in English
5. **Clean up or delete mockup files** (CRITICAL-1) - Remove blue/forbidden colors

### Short-Term (Sprint 2)

6. **Translate Queue Visualization** (HIGH-8) - User-facing widget in English
7. **Translate Admin Login** (HIGH-7) - Login page in English
8. **Fix "ago" to "atras"** (HIGH-9) - Inconsistent time formatting
9. **Fix "Unknown Merchant"** (HIGH-11) - English fallback text
10. **Fix shared errors partial** (HIGH-12) - English error header
11. **Translate Pattern Form** (HIGH-13) - All form labels in English
12. **Fix Queue Monitor JS strings** (MEDIUM-2) - Dynamic English text

### Medium-Term (Sprint 3)

13. **Mobile table/card layout** (MEDIUM-4) - Better mobile expense browsing
14. **Fix edit button color** (MEDIUM-7) - Semantic color correction
15. **Fix currency symbol** (MEDIUM-8) - $ vs colon
16. **Add focus indicators** (MEDIUM-9) - Accessibility compliance
17. **Standardize border radius** (MEDIUM-6) - Component consistency

### Nice-to-Have

18. **Loading skeletons** (LOW-1) - Dashboard perceived performance
19. **Date format localization** (LOW-4) - Consistent date formatting
20. **"Analytics" nav label** (LOW-3) - Spanish consistency

---

## Appendix: Files with No Issues Found

The following production view files passed all audit checks:

- `/app/views/expenses/dashboard.html.erb` - Excellent palette compliance (minor English fallback)
- `/app/views/expenses/_expense_row.html.erb` - Good palette compliance
- `/app/views/expenses/_status_badge.html.erb` - Perfect Spanish + palette
- `/app/views/expenses/_category_with_confidence.html.erb` - Good Spanish + palette
- `/app/views/expenses/_form.html.erb` - Good Spanish + palette
- `/app/views/expenses/show.html.erb` - Good palette (minor "ago" issue)
- `/app/views/sync_sessions/index.html.erb` - Excellent Spanish + palette
- `/app/views/sync_sessions/show.html.erb` - Good Spanish + palette
- `/app/views/sync_sessions/_unified_widget.html.erb` - Good Spanish + palette
- `/app/views/sync_sessions/_status_widget.html.erb` - Good Spanish + palette
- `/app/views/sync_conflicts/index.html.erb` - Good Spanish + palette
- `/app/views/sync_conflicts/_conflict_row.html.erb` - Good Spanish + palette
- `/app/views/email_accounts/index.html.erb` - Good Spanish + palette
- `/app/views/budgets/index.html.erb` - Good Spanish + palette
- `/app/views/shared/_flash.html.erb` - Perfect palette compliance
- `/app/views/shared/_toast.html.erb` - Perfect palette compliance
- `/app/views/shared/_budget_progress.html.erb` - Perfect Spanish + palette
- `/app/views/expenses/_bulk_operations_modal.html.erb` - Good Spanish + palette
