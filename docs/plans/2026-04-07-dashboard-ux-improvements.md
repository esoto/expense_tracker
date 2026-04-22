# Dashboard UX Improvements — Implementation Plan

**Goal:** Improve dashboard information hierarchy, reduce clutter, and improve accessibility

## Tickets (create in Linear when available)

### HIGH PRIORITY

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 1 | Restructure dashboard visual hierarchy | Move metrics above sync section so users see financial data first. Sync is operational, not primary. | Medium |
| 2 | Remove duplicate sync section from dashboard body | The inline sync form + account list is redundant with the unified_widget partial. Remove ~100 lines of duplicate sync UI. | Easy |
| 3 | Extract metric cards into reusable partial | Each metric card has 15+ data attributes on a single div (~800 char lines). Extract to `_metric_card.html.erb` partial. | Medium |

### MEDIUM PRIORITY

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 4 | Add empty states for charts and tables | New users see blank charts. Add empty states with CTAs. | Easy |
| 5 | Add ARIA progressbar attributes to budget bars | Budget progress bars lack screen reader support. | Easy |
| 6 | Replace color-only sync status dots with labeled indicators | Colored dots without text violate color-not-only guideline. | Easy |
| 7 | Fix accessibility_manager.js Spanish-only selector | `[aria-label*="cerrar" i]` breaks when aria-labels are translated. Use data attribute instead. | Easy |

### LOW PRIORITY

| # | Title | Description | Complexity |
|---|-------|-------------|------------|
| 8 | Add skeleton loading states for charts | Show shimmer placeholders while data loads. | Medium |
| 9 | Change chart grid breakpoint from lg to md | Tablets waste space with single-column chart layout. | Easy |
| 10 | Define accessible chart color palette | Explicit palette with pattern fallbacks for colorblind users. | Medium |
