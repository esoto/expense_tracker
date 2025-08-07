# Epic 2: Tasks and Tickets

## Task Summary

This epic contains 6 main tasks and 3 subtasks focused on enhancing metric cards with interactive features and visual hierarchy.

| Task ID | Task Name | Priority | Hours | Status |
|---------|-----------|----------|-------|--------|
| EXP-2.1 | Data Aggregation Service Layer | High | 10 | Not Started |
| EXP-2.2 | Primary Metric Visual Enhancement | High | 6 | Not Started |
| EXP-2.3 | Interactive Tooltips with Sparklines | Medium | 12 | Not Started |
| EXP-2.3.1 | Chart Library Integration | High | 4 | Not Started |
| EXP-2.3.2 | Sparkline Component Development | Medium | 4 | Not Started |
| EXP-2.3.3 | Tooltip Interaction Handler | Medium | 4 | Not Started |
| EXP-2.4 | Budget and Goal Indicators | Medium | 10 | Not Started |
| EXP-2.5 | Clickable Card Navigation | Low | 6 | Not Started |
| EXP-2.6 | Metric Calculation Background Jobs | Medium | 8 | Not Started |

**Total Estimated Hours:** 52 hours

---

## Task 2.1: Data Aggregation Service Layer

**Task ID:** EXP-2.1  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 10  

### Description
Create a service layer for efficient calculation and caching of metric data, including trends, comparisons, and projections.

### Acceptance Criteria
- [ ] MetricsCalculator service class implemented
- [ ] Calculations cached with 1-hour expiration
- [ ] Support for multiple time periods (day, week, month, year)
- [ ] Trend calculation (% change vs previous period)
- [ ] Category-wise breakdowns calculated
- [ ] Performance: Calculations complete in < 100ms

### Technical Notes

See original document for complete implementation including:
- MetricsCalculator service with caching
- Background job for pre-calculations
- Database optimization with indexes
- Redis caching strategy
- Performance monitoring
- Comprehensive testing

---

## Task 2.2: Primary Metric Visual Enhancement

**Task ID:** EXP-2.2  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 6  

### Description
Implement 1.5x sizing for the primary "Total de Gastos" metric card with enhanced visual design to establish clear hierarchy.

### Acceptance Criteria
- [ ] Primary card 1.5x size of secondary cards
- [ ] Responsive grid layout maintains proportions
- [ ] Typography scaled appropriately (larger font)
- [ ] Visual weight through color/shadow enhanced
- [ ] Animation on value changes
- [ ] Mobile responsive design maintained

### Designs
```
┌─────────────────────────────────────────┐
│         TOTAL DE GASTOS                 │
│         ₡ 1,250,000                     │
│         ↑ 12% vs mes anterior           │
│         ▂▃▅▇█▇▅ (mini sparkline)       │
└─────────────────────────────────────────┘

┌──────────────┬──────────────┬──────────┐
│ Este Mes     │ Semana       │ Hoy      │
│ ₡ 425,000    │ ₡ 98,000     │ ₡ 12,500 │
└──────────────┴──────────────┴──────────┘
```

---

## Task 2.3: Interactive Tooltips with Sparklines

**Task ID:** EXP-2.3  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 12  

### Description
Implement hover tooltips displaying 7-day trend sparklines and additional context for each metric card.

### Acceptance Criteria
- [ ] Tooltip appears on hover after 200ms delay
- [ ] Sparkline shows 7-day trend
- [ ] Min/max values indicated on sparkline
- [ ] Average line displayed
- [ ] Smooth fade in/out animation
- [ ] Touch-friendly alternative for mobile
- [ ] Chart renders in < 50ms

---

## Subtask 2.3.1: Chart Library Integration

**Task ID:** EXP-2.3.1  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 4  

### Description
Integrate Chart.js or similar lightweight charting library for rendering sparklines and other data visualizations.

### Acceptance Criteria
- [ ] Chart library added to project dependencies
- [ ] Bundle size increase < 50KB
- [ ] Library loaded asynchronously
- [ ] Fallback for chart loading failure
- [ ] Configuration for consistent styling
- [ ] Documentation for chart usage

---

## Subtask 2.3.2: Sparkline Component Development

**Task ID:** EXP-2.3.2  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 4  

### Description
Create reusable Stimulus controller for rendering sparkline charts within tooltips with configurable options.

### Acceptance Criteria
- [ ] Stimulus controller accepts data array
- [ ] Configurable colors and styling
- [ ] Responsive sizing
- [ ] Smooth line interpolation
- [ ] Points for min/max values
- [ ] Error handling for invalid data

---

## Subtask 2.3.3: Tooltip Interaction Handler

**Task ID:** EXP-2.3.3  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 4  

### Description
Implement tooltip display logic with proper positioning, timing, and interaction handling for both desktop and mobile.

### Acceptance Criteria
- [ ] Tooltip positioned to avoid viewport edges
- [ ] 200ms hover delay before showing
- [ ] Immediate hide on mouse leave
- [ ] Touch: tap to show, tap elsewhere to hide
- [ ] Keyboard accessible (focus shows tooltip)
- [ ] Z-index properly managed

---

## Task 2.4: Budget and Goal Indicators

**Task ID:** EXP-2.4  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 10  

### Description
Add budget tracking indicators and goal progress visualization to metric cards, showing spending against defined limits.

### Acceptance Criteria
- [ ] Budget progress bar below amount
- [ ] Percentage of budget used displayed
- [ ] Color coding: green (< 70%), yellow (70-90%), red (> 90%)
- [ ] "Set Budget" action if not defined
- [ ] Monthly/weekly/daily budget options
- [ ] Historical budget adherence indicator

### Designs
```
┌─────────────────────────────────────┐
│ Total de Gastos                     │
│ ₡ 1,250,000                        │
│ ████████░░ 78% of ₡1,600,000       │
│ ✓ On track for monthly goal         │
└─────────────────────────────────────┘
```

---

## Task 2.5: Clickable Card Navigation

**Task ID:** EXP-2.5  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 6  

### Description
Make metric cards clickable to navigate to filtered expense views showing relevant transactions for each metric.

### Acceptance Criteria
- [ ] Cards have hover state indicating clickability
- [ ] Click navigates to expense list with appropriate filters
- [ ] Filter state reflected in URL parameters
- [ ] Smooth scroll to expense list section
- [ ] Back button returns to dashboard
- [ ] Loading state during navigation

---

## Task 2.6: Metric Calculation Background Jobs

**Task ID:** EXP-2.6  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Implement background jobs for calculating complex metrics and maintaining materialized views for performance.

### Acceptance Criteria
- [ ] Hourly job recalculates all metrics
- [ ] Triggered recalculation on expense changes
- [ ] Materialized view for aggregations
- [ ] Job monitoring and error recovery
- [ ] Performance: Job completes in < 30 seconds
- [ ] Prevents concurrent calculation jobs

---

## Dependencies and Sequencing

### Dependency Graph
```
2.1 (Service Layer) → 2.2 (Visual) → 2.3 (Tooltips)
                   ↘                ↗
                    2.6 (Background Jobs)
                           ↓
                    2.4 (Budget) → 2.5 (Navigation)
```

### Critical Path
1. Start with 2.1 (Service Layer) - foundation for all metrics
2. Then 2.2 (Visual Enhancement) and 2.6 (Background Jobs) in parallel
3. 2.3 (Tooltips) after chart library selected
4. 2.4 (Budget) after data model established
5. 2.5 (Navigation) can be done anytime after 2.1

## Testing Strategy

### Unit Tests
- MetricsCalculator service logic
- Sparkline data transformation
- Budget calculation algorithms
- Cache invalidation logic

### Integration Tests
- End-to-end metric calculation flow
- Tooltip interaction scenarios
- Navigation with filter persistence
- Background job execution

### Performance Tests
- Metric calculation under load
- Chart rendering performance
- Cache effectiveness
- Database query optimization

### Visual Tests
- Card hierarchy rendering
- Tooltip positioning
- Responsive design breakpoints
- Animation smoothness