# Rails Testing Best Practices: ActiveRecord Query Chains

## Executive Summary

From a Rails senior architect perspective, the test failure you encountered highlights a fundamental principle: **Don't mock what you don't own**. ActiveRecord is framework code, and mocking it leads to brittle tests that break when implementation details change.

## The Problem

The error message:
```
Failure/Error: categorized = Expense.where.not(category_id: nil).count
#<Double (anonymous)> received unexpected message :not with ({category_id: nil})
```

This occurs because ActiveRecord's query interface uses a complex chain of objects (ActiveRecord::Relation) that are difficult to mock correctly.

## Rails Best Practices - Ranked by Preference

### 1. **Use Real Database Queries (RECOMMENDED)**

```ruby
# ✅ BEST: Use real records with transactional fixtures
describe ".categorization_metrics" do
  let!(:categorized) { create_list(:expense, 3, category: category) }
  let!(:uncategorized) { create_list(:expense, 2, category: nil) }
  
  it "calculates metrics" do
    result = described_class.categorization_metrics
    expect(result[:categorized]).to eq(3)
    expect(result[:uncategorized]).to eq(2)
  end
end
```

**Why this is best:**
- Tests actual database behavior
- Fast with transactional fixtures
- No maintenance burden when Rails internals change
- Tests are more reliable and catch real bugs

### 2. **Extract Complex Queries to Query Objects**

```ruby
# app/queries/category_metrics_query.rb
class CategoryMetricsQuery
  def categorized_count
    Expense.where.not(category_id: nil).count
  end
end

# In your service
def categorization_metrics(query: CategoryMetricsQuery.new)
  { categorized: query.categorized_count }
end

# In tests - now you can easily mock the query object
let(:mock_query) { instance_double(CategoryMetricsQuery, categorized_count: 100) }
```

**Benefits:**
- Separates business logic from ActiveRecord
- Makes testing easier without mocking AR
- Improves code organization
- Follows Single Responsibility Principle

### 3. **Use receive_message_chain (LAST RESORT)**

```ruby
# ⚠️ AVOID: But if you must mock AR, use receive_message_chain
allow(Expense).to receive_message_chain(:where, :not, :count).and_return(100)

# For more complex chains
allow(Expense).to receive(:where).with(updated_at: time_range).and_return(
  double.tap do |scope|
    allow(scope).to receive(:count).and_return(30)
    allow(scope).to receive_message_chain(:where, :not, :count).and_return(20)
  end
)
```

**Why avoid this:**
- Couples tests to ActiveRecord implementation
- Brittle - breaks when Rails changes internals
- Doesn't test actual database behavior
- Can hide real bugs

## Testing Concurrent Access

For concurrent database access, **always use real database connections**:

```ruby
context "with concurrent access" do
  it "handles simultaneous queries" do
    # Create real data
    create_list(:expense, 5)
    
    results = []
    threads = 5.times.map do
      Thread.new { results << described_class.categorization_metrics }
    end
    threads.each(&:join)
    
    # All threads should see consistent data
    expect(results.uniq.size).to eq(1)
  end
end
```

## Refactoring for Testability

### Before (Hard to Test)
```ruby
def categorization_metrics
  total = Expense.count
  categorized = Expense.where.not(category_id: nil).count
  # ... complex logic mixed with queries
end
```

### After (Testable)
```ruby
def categorization_metrics
  metrics = category_metrics_service.calculate
  format_metrics(metrics)
end

private

def category_metrics_service
  @category_metrics_service ||= CategoryMetricsService.new
end

def format_metrics(raw_metrics)
  # Pure transformation logic - easy to test
end
```

## Key Principles

1. **Database queries are fast in tests** - Rails uses transactions that are rolled back
2. **Test behavior, not implementation** - Focus on what the method returns, not how
3. **Use factories or fixtures** - Create real data for integration tests
4. **Mock at service boundaries** - Mock external services, not framework code
5. **Keep query logic simple** - Complex queries belong in query objects or scopes

## Performance Considerations

If test performance becomes an issue:

1. Use `let!` sparingly - only create data you need
2. Consider using `before(:all)` for read-only data
3. Use database cleaner's truncation strategy only when necessary
4. Profile tests with `--profile` flag to find slow tests

## Migration Path

To migrate existing tests:

1. Identify all ActiveRecord mocks
2. Replace with factories/fixtures where possible
3. Extract complex queries to query objects
4. Use receive_message_chain only as temporary solution
5. Add integration tests to catch issues mocks might miss

## Conclusion

The Rails way is to embrace the framework rather than fight it. Real database queries in tests are:
- More maintainable
- More reliable
- Faster than you think
- Better at catching real bugs

When you find yourself extensively mocking ActiveRecord, it's a code smell indicating the need for refactoring, not better mocks.