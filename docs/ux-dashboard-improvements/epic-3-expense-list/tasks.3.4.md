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
