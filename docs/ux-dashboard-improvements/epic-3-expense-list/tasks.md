# Epic 3: Tasks and Tickets

## Task Summary

This epic contains 9 main tasks focused on optimizing the expense list with batch operations, filtering, and performance improvements.

| Task ID | Task Name | Priority | Hours | Status |
|---------|-----------|----------|-------|--------|
| EXP-3.1 | Database Optimization for Filtering | Critical | 8 | Not Started |
| EXP-3.2 | Compact View Mode Toggle | High | 6 | Not Started |
| EXP-3.3 | Inline Quick Actions | High | 10 | Not Started |
| EXP-3.4 | Batch Selection System | High | 12 | Not Started |
| EXP-3.5 | Bulk Categorization Modal | Medium | 8 | Not Started |
| EXP-3.6 | Inline Filter Chips | Medium | 8 | Not Started |
| EXP-3.7 | Virtual Scrolling Implementation | Low | 10 | Not Started |
| EXP-3.8 | Filter State Persistence | Low | 6 | Not Started |
| EXP-3.9 | Accessibility for Inline Actions | High | 8 | Not Started |

**Total Estimated Hours:** 76 hours

---

## Task 3.1: Database Optimization for Filtering

**Task ID:** EXP-3.1  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 8  

### Description
Implement database indexes and query optimizations to support fast filtering and sorting of large expense datasets.

### Acceptance Criteria
- [ ] Composite index for common filter combinations
- [ ] Covering indexes to avoid table lookups
- [ ] Query performance < 50ms for 10k records
- [ ] EXPLAIN ANALYZE shows index usage
- [ ] No N+1 queries in expense list
- [ ] Database migrations reversible

### Technical Notes
- Create composite indexes for (user_id, date, category_id)
- Add covering index for expense list queries
- Use includes/joins to prevent N+1
- Consider materialized view for aggregations
- Monitor slow query log

---

## Task 3.2: Compact View Mode Toggle

**Task ID:** EXP-3.2  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 6  

### Description
Implement a toggle to switch between standard and compact view modes for the expense list with preference persistence.

### Acceptance Criteria
- [ ] Toggle button in expense list header
- [ ] Compact mode reduces row height by 50%
- [ ] Single-line layout in compact mode
- [ ] View preference saved to localStorage
- [ ] Smooth transition animation between modes
- [ ] Mobile automatically uses compact mode

### Designs
```
Standard View:
┌─────────────────────────────────────┐
│ □ Walmart                           │
│   ₡ 45,000 - Comida                │
│   Jan 15, 2024 - BAC San José      │
└─────────────────────────────────────┘

Compact View:
┌─────────────────────────────────────┐
│ □ Walmart | ₡45,000 | Comida | 1/15│
└─────────────────────────────────────┘
```

---

## Task 3.3: Inline Quick Actions

**Task ID:** EXP-3.3  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 10  

### Description
Add hover-activated inline actions for quick editing of categories and notes without leaving the expense list.

### Acceptance Criteria
- [ ] Action buttons appear on row hover
- [ ] Edit category with dropdown
- [ ] Add/edit note with popover
- [ ] Delete with confirmation
- [ ] Keyboard shortcuts (E=edit, D=delete, N=note)
- [ ] Optimistic updates with rollback on error
- [ ] Touch: long-press shows actions

---

## Task 3.4: Batch Selection System

**Task ID:** EXP-3.4  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 12  

### Description
Implement checkbox-based selection system for performing bulk operations on multiple expenses simultaneously.

### Acceptance Criteria
- [ ] Checkbox for each expense row
- [ ] Select all checkbox in header
- [ ] Shift-click for range selection
- [ ] Selected count display
- [ ] Floating action bar appears with selection
- [ ] Persist selection during pagination
- [ ] Clear selection button

### Designs
```
┌─────────────────────────────────────┐
│ ☑ Select All  (3 selected)         │
├─────────────────────────────────────┤
│ ☑ Expense 1                         │
│ ☑ Expense 2                         │
│ ☑ Expense 3                         │
│ ☐ Expense 4                         │
└─────────────────────────────────────┘
│                                     │
│ [Categorize] [Delete] [Export]      │
└─────────────────────────────────────┘
```

---

## Task 3.5: Bulk Categorization Modal

**Task ID:** EXP-3.5  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Create modal interface for applying categories to multiple selected expenses with conflict resolution options.

### Acceptance Criteria
- [ ] Modal shows selected expense count
- [ ] Category dropdown with search
- [ ] Preview of changes before applying
- [ ] Option to skip already categorized
- [ ] Progress indicator for bulk update
- [ ] Undo capability after completion
- [ ] Success/error summary

---

## Task 3.6: Inline Filter Chips

**Task ID:** EXP-3.6  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Add interactive filter chips above the expense list for quick filtering by category, bank, and date ranges.

### Acceptance Criteria
- [ ] Chips for top 5 categories
- [ ] Chips for all active banks
- [ ] Date range quick filters (today, week, month)
- [ ] Active chip highlighting
- [ ] Multiple chip selection (AND logic)
- [ ] Clear all filters button
- [ ] Filter count badge

### Designs
```
┌─────────────────────────────────────┐
│ Filters:                            │
│ [All] [Comida] [Transporte] [Casa] │
│ [BAC] [Scotia] [This Month] [Clear]│
└─────────────────────────────────────┘
```

---

## Task 3.7: Virtual Scrolling Implementation

**Task ID:** EXP-3.7  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 10  

### Description
Implement virtual scrolling for efficiently displaying large expense lists (1000+ items) without performance degradation.

### Acceptance Criteria
- [ ] Smooth scrolling with 1000+ items
- [ ] Maintains 60fps scrolling performance
- [ ] Correct scroll position preservation
- [ ] Search/filter works with virtual list
- [ ] Selection state maintained
- [ ] Fallback for browsers without support

---

## Task 3.8: Filter State Persistence

**Task ID:** EXP-3.8  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 6  

### Description
Implement URL-based filter state persistence to maintain filters across navigation and enable sharing of filtered views.

### Acceptance Criteria
- [ ] Filters reflected in URL parameters
- [ ] Browser back/forward navigation works
- [ ] Bookmarkable filtered views
- [ ] Share button copies filtered URL
- [ ] Load filters from URL on page load
- [ ] Clear filters updates URL

---

## Task 3.9: Accessibility for Inline Actions

**Task ID:** EXP-3.9  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 8  

### Description
Ensure all inline actions and batch operations are fully accessible via keyboard and screen readers.

### Acceptance Criteria
- [ ] All actions keyboard accessible
- [ ] Proper ARIA labels and roles
- [ ] Screen reader announcements for state changes
- [ ] Focus management for modals
- [ ] Skip links for repetitive content
- [ ] High contrast mode support
- [ ] WCAG 2.1 AA compliance

---

## Dependencies and Sequencing

### Dependency Graph
```
3.1 (Database) → 3.2 (Compact View) → 3.3 (Quick Actions)
                        ↓
                 3.4 (Batch Selection) → 3.5 (Bulk Modal)
                        ↓
                 3.6 (Filter Chips) → 3.8 (State Persistence)
                        ↓
                 3.7 (Virtual Scrolling)
                        
3.9 (Accessibility) - Can be done in parallel with any task
```

### Critical Path
1. Start with 3.1 (Database Optimization) - foundation for performance
2. Then 3.2 (Compact View) for immediate density improvement
3. 3.4 (Batch Selection) enables bulk operations
4. 3.3 (Quick Actions) and 3.6 (Filters) can be parallel
5. 3.7 (Virtual Scrolling) only if performance issues
6. 3.9 (Accessibility) should be ongoing throughout

## Testing Strategy

### Unit Tests
- Filter service logic
- Batch operation transactions
- View mode toggle persistence
- Selection state management

### Integration Tests
- End-to-end batch categorization
- Filter combination scenarios
- Keyboard navigation flow
- State persistence across navigation

### Performance Tests
- Query performance with indexes
- Virtual scrolling with 10k items
- Batch operations on 100+ items
- Filter application speed

### Accessibility Tests
- Keyboard navigation coverage
- Screen reader compatibility
- WCAG compliance audit
- Focus management verification

## Implementation Notes

### Database Considerations
- Run EXPLAIN ANALYZE before and after indexes
- Monitor pg_stat_user_indexes for usage
- Consider partitioning for very large datasets
- Vacuum and analyze after index creation

### Frontend Performance
- Use CSS containment for list items
- Debounce filter changes (300ms)
- Virtualize only when > 100 items
- Lazy load action buttons

### State Management
- Use Stimulus values for UI state
- localStorage for user preferences
- URL params for shareable state
- Redux not needed - keep it simple

### Error Handling
- Optimistic updates with rollback
- Clear error messages in Spanish
- Retry logic for network failures
- Graceful degradation for features