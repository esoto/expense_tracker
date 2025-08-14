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
