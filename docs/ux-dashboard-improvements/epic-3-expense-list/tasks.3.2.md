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
