# Epic 4: Dashboard Simplification - Task Breakdown

## Overview
This document provides a detailed task breakdown for the Dashboard Simplification epic, organized by story with effort estimates, dependencies, and implementation order.

## Task Summary

**Total Estimated Effort**: 15 story points (3 weeks)
**Team Size**: 1-2 developers
**Complexity**: Medium
**Risk Level**: Low-Medium

## Story 1: Remove Duplicate Sync Sections (3 points)

### 1.1 Backend Preparation (0.5 points)
- [ ] **Task 1.1.1**: Remove duplicate sync data queries from ExpensesController
  - Remove `@active_sync_session` duplicate loading
  - Remove `@last_sync_info` calculation
  - Consolidate into single service call
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 1.1.2**: Optimize database queries for unified widget
  - Add indexes for sync session queries
  - Implement query caching
  - **Estimate**: 2 hours
  - **Dependencies**: Task 1.1.1
  - **Risk**: Low

### 1.2 Frontend Removal (1 point)
- [ ] **Task 1.2.1**: Remove email sync section from dashboard.html.erb
  - Delete lines 13-177
  - Clean up related JavaScript
  - **Estimate**: 1 hour
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 1.2.2**: Remove queue visualization widget or integrate
  - Evaluate queue_visualization partial
  - Either remove or merge into unified widget
  - **Estimate**: 2 hours
  - **Dependencies**: Task 1.2.1
  - **Risk**: Medium

### 1.3 Widget Enhancement (1 point)
- [ ] **Task 1.3.1**: Enhance unified_widget partial
  - Add sync controls from removed section
  - Add individual account sync options
  - **Estimate**: 3 hours
  - **Dependencies**: Task 1.2.1
  - **Risk**: Medium

- [ ] **Task 1.3.2**: Update Stimulus controller
  - Consolidate sync functionality
  - Handle all sync triggers
  - **Estimate**: 2 hours
  - **Dependencies**: Task 1.3.1
  - **Risk**: Medium

### 1.4 Testing & Cleanup (0.5 points)
- [ ] **Task 1.4.1**: Update tests for removed sections
  - Fix failing tests
  - Add new integration tests
  - **Estimate**: 2 hours
  - **Dependencies**: All above
  - **Risk**: Low

## Story 2: Simplify Metric Cards (5 points)

### 2.1 Create Tooltip Infrastructure (1 point)
- [ ] **Task 2.1.1**: Build metric_tooltip_controller.js
  - Implement tooltip display logic
  - Add positioning algorithm
  - Handle mobile touch events
  - **Estimate**: 3 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 2.1.2**: Create tooltip templates
  - Design tooltip layouts
  - Add loading states
  - **Estimate**: 2 hours
  - **Dependencies**: Task 2.1.1
  - **Risk**: Low

### 2.2 Simplify Primary Metric Card (1.5 points)
- [ ] **Task 2.2.1**: Remove secondary statistics
  - Remove transaction counts
  - Remove average calculations
  - Remove category counts
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 2.2.2**: Redesign primary card layout
  - Implement new visual design
  - Add gradient background
  - Simplify trend indicator
  - **Estimate**: 3 hours
  - **Dependencies**: Task 2.2.1
  - **Risk**: Low

### 2.3 Simplify Secondary Cards (1.5 points)
- [ ] **Task 2.3.1**: Strip down period metrics
  - Remove transaction counts
  - Simplify trend display
  - Reduce visual weight
  - **Estimate**: 3 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 2.3.2**: Implement progressive disclosure
  - Add hover interactions
  - Connect to tooltip system
  - **Estimate**: 3 hours
  - **Dependencies**: Task 2.1.1, Task 2.3.1
  - **Risk**: Medium

### 2.4 Backend Optimization (1 point)
- [ ] **Task 2.4.1**: Create ExpenseMetricsService methods
  - Add `essential_metrics` method
  - Add `tooltip_data` method
  - Implement caching
  - **Estimate**: 4 hours
  - **Dependencies**: None
  - **Risk**: Low

## Story 3: Consolidate Merchant Information (2 points)

### 3.1 Backend Enhancement (0.5 points)
- [ ] **Task 3.1.1**: Add merchant stats to Expense model
  - Create `with_merchant_stats` scope
  - Add merchant ranking logic
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

### 3.2 Remove Merchant Section (0.5 points)
- [ ] **Task 3.2.1**: Delete standalone merchant section
  - Remove lines 477-493 from dashboard
  - Clean up related styles
  - **Estimate**: 1 hour
  - **Dependencies**: None
  - **Risk**: Low

### 3.3 Enhance Recent Expenses (1 point)
- [ ] **Task 3.3.1**: Add merchant badges to expenses
  - Implement ranking badges
  - Add frequency indicators
  - **Estimate**: 2 hours
  - **Dependencies**: Task 3.1.1
  - **Risk**: Low

- [ ] **Task 3.3.2**: Create merchant tooltips
  - Build merchant_tooltip_controller.js
  - Add merchant statistics display
  - **Estimate**: 2 hours
  - **Dependencies**: Task 3.3.1
  - **Risk**: Low

## Story 4: Remove Bank Breakdown (1 point)

### 4.1 Simple Removal (0.5 points)
- [ ] **Task 4.1.1**: Remove bank breakdown section
  - Delete lines 496-514
  - Remove controller logic
  - **Estimate**: 1 hour
  - **Dependencies**: None
  - **Risk**: Low

### 4.2 Layout Adjustment (0.5 points)
- [ ] **Task 4.2.1**: Rebalance dashboard grid
  - Adjust column layouts
  - Ensure proper spacing
  - **Estimate**: 1 hour
  - **Dependencies**: Task 4.1.1
  - **Risk**: Low

## Story 5: Reduce Chart Complexity (3 points)

### 5.1 Simplify Data Processing (1 point)
- [ ] **Task 5.1.1**: Implement chart data simplification
  - Limit to 6 months of data
  - Create category grouping logic
  - Add trend calculations
  - **Estimate**: 3 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 5.1.2**: Generate insights
  - Create insight generation logic
  - Add contextual messages
  - **Estimate**: 2 hours
  - **Dependencies**: Task 5.1.1
  - **Risk**: Low

### 5.2 Update Chart Components (1.5 points)
- [ ] **Task 5.2.1**: Simplify line chart
  - Reduce to 6 data points
  - Add curve smoothing
  - Remove point markers
  - **Estimate**: 2 hours
  - **Dependencies**: Task 5.1.1
  - **Risk**: Low

- [ ] **Task 5.2.2**: Simplify pie chart
  - Convert to donut chart
  - Group small categories
  - Add center metric
  - **Estimate**: 3 hours
  - **Dependencies**: Task 5.1.1
  - **Risk**: Low

### 5.3 Add Interactivity (0.5 points)
- [ ] **Task 5.3.1**: Create chart_toggle_controller.js
  - Implement expand/collapse
  - Add smooth transitions
  - **Estimate**: 2 hours
  - **Dependencies**: Task 5.2.1, Task 5.2.2
  - **Risk**: Low

## Story 6: Clean Visual Hierarchy (3 points)

### 6.1 Establish Design System (1 point)
- [ ] **Task 6.1.1**: Define spacing system
  - Create CSS variables
  - Document spacing scale
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

- [ ] **Task 6.1.2**: Define typography scale
  - Create text classes
  - Set font hierarchies
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

### 6.2 Apply Visual Hierarchy (1.5 points)
- [ ] **Task 6.2.1**: Redesign primary metric
  - Apply hero treatment
  - Maximize visual prominence
  - **Estimate**: 2 hours
  - **Dependencies**: Task 6.1.1, Task 6.1.2
  - **Risk**: Low

- [ ] **Task 6.2.2**: Standardize secondary elements
  - Apply consistent sizing
  - Uniform spacing
  - **Estimate**: 3 hours
  - **Dependencies**: Task 6.1.1, Task 6.1.2
  - **Risk**: Low

### 6.3 Remove Visual Clutter (0.5 points)
- [ ] **Task 6.3.1**: Eliminate unnecessary borders
  - Remove 50% of dividers
  - Simplify card designs
  - **Estimate**: 2 hours
  - **Dependencies**: None
  - **Risk**: Low

## Implementation Schedule

### Week 1: Foundation (5 points)
**Day 1-2**: Story 1 - Remove Duplicate Sync Sections
**Day 3-5**: Story 4 - Remove Bank Breakdown + Story 6 - Visual Hierarchy Foundation

### Week 2: Core Simplification (7 points)
**Day 1-3**: Story 2 - Simplify Metric Cards
**Day 4-5**: Story 5 - Reduce Chart Complexity

### Week 3: Polish & Integration (3 points)
**Day 1-2**: Story 3 - Consolidate Merchants
**Day 3**: Story 6 - Complete Visual Hierarchy
**Day 4-5**: Testing, bug fixes, and deployment preparation

## Critical Path

1. **Story 1** → Must complete first (removes redundancy)
2. **Story 6.1** → Design system needed for other stories
3. **Story 2** → Tooltip infrastructure used by Story 3
4. **Story 4** → Can be done anytime (independent)
5. **Story 5** → Can be done in parallel with others
6. **Story 3** → Depends on tooltip system from Story 2

## Risk Mitigation

### High-Risk Tasks
1. **Widget Consolidation** (Task 1.3.1)
   - Mitigation: Extensive testing, feature flag

2. **Tooltip System** (Task 2.1.1)
   - Mitigation: Use proven library if custom fails

3. **Chart Simplification** (Task 5.2.2)
   - Mitigation: A/B test with users

### Rollback Plan
- Implement feature flags for each story
- Maintain old code in separate branch
- Document all removed code
- Have quick revert process ready

## Success Metrics

### Technical Metrics
- [ ] Page load time < 1.5s
- [ ] 50% reduction in DOM elements
- [ ] 35% reduction in code lines
- [ ] All tests passing (> 95% coverage)

### User Metrics
- [ ] 60% reduction in cognitive load score
- [ ] 50% improvement in task completion time
- [ ] 80% positive user feedback
- [ ] < 5% increase in support tickets

## Testing Checklist

### Unit Tests
- [ ] All removed code has tests removed
- [ ] New components have full coverage
- [ ] Edge cases tested

### Integration Tests
- [ ] User workflows still function
- [ ] Data accuracy maintained
- [ ] Real-time updates work

### Visual Tests
- [ ] No visual regressions
- [ ] Mobile responsive
- [ ] Cross-browser compatible

### Performance Tests
- [ ] Load time improved
- [ ] Memory usage reduced
- [ ] Smooth animations

### User Acceptance Tests
- [ ] Key workflows validated
- [ ] Accessibility standards met
- [ ] User feedback incorporated

## Documentation Requirements

### Code Documentation
- [ ] Inline comments for complex logic
- [ ] README updates for new components
- [ ] API documentation for services

### User Documentation
- [ ] Update user guide
- [ ] Create migration guide
- [ ] Record training videos

### Technical Documentation
- [ ] Architecture decisions recorded
- [ ] Performance benchmarks documented
- [ ] Deployment process updated