# Bug Report: Task 3.1 Database Optimization

**Bug ID:** EPIC3-001  
**Severity:** Medium (Non-blocking for production)  
**Priority:** High  
**Found By:** QA Test Strategist  
**Date:** 2025-08-14  

## Summary
Merchant search functionality test failure in ExpenseFilterService when searching for expenses by merchant name.

## Environment
- **Branch:** epic-3-expense-list-optimization
- **Database:** expense_tracker_epic_3_expense_list_optimization_development
- **Rails Version:** 8.0.2
- **Test Suite:** RSpec

## Bug Details

### Issue Description
The merchant search feature in ExpenseFilterService fails when attempting to search for expenses by merchant name. The test indicates that the trigram search index is not functioning as expected.

### Expected Behavior
When searching for merchant "Walmart", the service should return expenses with merchant names that match or are similar to "Walmart" using trigram fuzzy matching.

### Actual Behavior
The merchant search query returns no results even when matching expenses exist in the database.

### Error Location
- **File:** `spec/services/expense_filter_service_spec.rb`
- **Test:** Merchant search functionality
- **Status:** 11/12 tests passing, 1 failing

### Root Cause Analysis
1. **Missing Data Population:** Test expenses may not have `merchant_normalized` field populated
2. **Index Configuration:** Trigram index `idx_expenses_merchant_search` may not be properly configured
3. **Query Logic:** Search query in ExpenseFilterService may have incorrect WHERE clause

### Technical Details

**Affected Components:**
- `app/services/expense_filter_service.rb` - Merchant search logic
- `app/models/concerns/expense_query_optimizer.rb` - Merchant search scopes
- Database index: `idx_expenses_merchant_search`

**Related Index:**
```sql
idx_expenses_merchant_search - gin(merchant_normalized gin_trgm_ops)
WHERE merchant_normalized IS NOT NULL AND deleted_at IS NULL
```

**Query Pattern:**
```ruby
scope :search_merchant, ->(term) {
  where("merchant_normalized ILIKE ?", "%#{term}%")
}
```

## Impact Assessment

### Functional Impact
- **User Impact:** ~~Medium - Users cannot search expenses by merchant name~~ **RESOLVED** - Merchant search now functional
- **System Impact:** Low - Other filtering functionality works correctly
- **Performance Impact:** None - Does not affect query performance

### Business Impact
- **User Experience:** ~~Reduced - Key search functionality unavailable~~ **RESTORED** - Full search functionality available
- **Data Accessibility:** ~~Medium - Users must use other filters to find expenses~~ **RESOLVED** - All search options functional
- **Production Readiness:** ~~Non-blocking - Core functionality remains intact~~ **PRODUCTION READY** - All functionality tested and working

## Reproduction Steps

1. Create test expenses with merchant names
2. Ensure `merchant_normalized` field is populated
3. Use ExpenseFilterService to search by merchant name
4. Observe empty results despite matching data

## Proposed Solution

### Immediate Fix
1. **Data Population:** Ensure test data includes populated `merchant_normalized` field
2. **Query Fix:** Verify trigram search query syntax
3. **Index Verification:** Confirm trigram extension and index are active

### Implementation Steps
1. Fix test data setup to populate `merchant_normalized`
2. Verify trigram search query in ExpenseQueryOptimizer
3. Run database analysis to confirm index usage
4. Update test assertions to match expected behavior

### Code Changes Required
- Update test factories/fixtures
- Fix merchant search query logic if needed
- Ensure proper data normalization in Expense model

## Testing Requirements

### Before Fix
- [ ] Reproduce bug consistently
- [ ] Verify trigram extension is installed
- [ ] Check index existence and usage

### After Fix
- [x] All ExpenseFilterService tests pass (12/12)
- [x] Merchant search returns expected results
- [x] Performance remains within targets
- [x] Integration tests pass

## Timeline
- **Discovery:** 2025-08-14
- **Target Fix:** Immediate (same day)
- **Verification:** Before next commit
- **Deployment:** With Task 3.1 completion

## Related Issues
- None currently identified

## Notes
- This is the only failing test in the ExpenseFilterService suite
- Does not block production deployment of core optimization features
- QA Strategist rated overall implementation 8.5/10 despite this issue
- Tech Lead Architect rated 9/10 - this bug was not identified in architectural review

## Dependencies
- PostgreSQL pg_trgm extension
- Trigram search index on merchant_normalized field
- Proper data normalization in Expense model

## Communication
- **Stakeholders Notified:** Development Team
- **Status:** Under Investigation
- **Next Update:** After fix implementation

---

**Reporter:** QA Test Strategist  
**Assigned To:** Rails Senior Architect  
**Status:** ✅ RESOLVED - Fixed merchant normalization callback  
**Resolution:** Added `before_save :normalize_merchant_name` callback to Expense model  
**Labels:** bug, search, merchant, medium-priority, resolved

## Resolution Details

**Root Cause:** The `merchant_normalized` field was not being populated when Expense records were created or updated.

**Fix Applied:** Added a `before_save` callback in the Expense model that automatically normalizes merchant names:

```ruby
# In app/models/expense.rb
before_save :normalize_merchant_name

private

def normalize_merchant_name
  if merchant_name.present? && merchant_normalized != normalized_merchant_value
    self.merchant_normalized = normalized_merchant_value
  end
end

def normalized_merchant_value
  return nil if merchant_name.blank?
  merchant_name.downcase.gsub(/[^\w\s]/, ' ').squeeze(' ').strip
end
```

**Verification:** All ExpenseFilterService tests now pass (12/12), merchant search functionality works correctly with trigram matching.