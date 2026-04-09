# Expenses Page UX Improvements — Implementation Plan

**Goal:** Fix critical bugs and improve usability of the expenses index page

**UX Source:** UI/UX Pro Max skill — Data-Dense Dashboard + Financial Dashboard + Personal Finance Tracker patterns

## Design Principles (from UX/UI Pro Max)

- **Data-Dense Dashboard**: Row hover highlighting, 36px row height, sticky headers, sortable columns, 12-14px data font, 8px grid gaps
- **Financial Dashboard**: Currency formatting, sticky headers, status via color + text, audit trail pattern
- **Minimalism + Accessible**: WCAG AA minimum, color not the only indicator, visible focus states

## Tickets

### BUG FIXES (Critical)

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 1 | Fix bulk actions toolbar visibility | Toolbar renders at bottom but clips/fades — likely z-index stacking context issue. The toolbar is `fixed z-40` but a parent with `overflow-hidden` clips it. Debug and fix CSS. | Easy |
| 2 | Fix clear filters button | Clear button doesn't reset applied filters. Debug `filter-persistence-controller` — likely sessionStorage not being cleared, or form reset not triggering submission. | Easy |

### UX IMPROVEMENTS (High Priority)

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 3 | Add date filter quick presets | Add segmented quick-select above date pickers: `[ This Month | Last Month | This Quarter | Year to Date | Custom ]`. Selecting a preset auto-populates dates and submits. "Custom" reveals the date pickers. Follows same pattern as dashboard period selector. | Easy |
| 4 | Replace inline row actions with kebab menu | Move categorize/status/duplicate/delete actions behind a three-dot (kebab) menu per row. On click, show a small dropdown. This prevents action buttons from overlapping expense data in both compact and expanded views. UX Pro Max recommends: actions on hover/click, not always visible. | Medium |
| 5 | Improve table density and spacing | Apply Data-Dense Dashboard pattern: 36px row height (currently ~60px), 12-14px data text, 8px gaps, sticky column headers. Compact mode is default. Expanded mode adds bank + status columns but keeps kebab menu — never shows inline buttons. | Medium |

### POLISH (Medium Priority)

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 6 | Add row hover highlighting | Subtle `hover:bg-slate-50` on table rows for visual tracking. Currently no row hover. Data-Dense Dashboard pattern requires this. | Easy |
| 7 | Add column sorting | Sortable columns for date, merchant, amount, category. Click header to toggle asc/desc. Arrow indicator on active sort. Financial Dashboard pattern recommends this. | Medium |
| 8 | Improve mobile card actions | Mobile action drawer buttons are small. Increase touch targets to 44px minimum. Simplify to 4 primary actions: Categorize, Status, Edit, Delete. | Easy |
