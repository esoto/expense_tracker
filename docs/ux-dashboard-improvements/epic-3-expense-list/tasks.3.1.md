## Task 3.1: Database Optimization for Filtering

**Task ID:** EXP-3.1  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 8  
**Dependencies:** None  
**Blocks:** Tasks 3.2, 3.3, 3.4 (performance depends on indexes)

### Description
Implement comprehensive database indexes and query optimizations to support fast filtering and sorting of large expense datasets (10,000+ records). This task establishes the performance foundation for all other Epic 3 features.

### Acceptance Criteria
- [ ] All 7 required indexes created and verified
- [ ] Query performance < 50ms for 10k records with complex filters
- [ ] EXPLAIN ANALYZE confirms index usage for all query patterns
- [ ] No N+1 queries detected by Bullet gem
- [ ] Database migrations are reversible and safe for production
- [ ] Index bloat monitoring implemented
- [ ] Query performance metrics tracked in StatsD

### Technical Implementation

#### 1. Required Indexes

```ruby
# db/migrate/[timestamp]_add_expense_performance_indexes.rb
class AddExpensePerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!  # Allow concurrent index creation
  
  def up
    # Primary composite index for date/category filtering
    add_index :expenses, 
              [:email_account_id, :transaction_date, :category_id],
              name: 'idx_expenses_filter_primary',
              algorithm: :concurrently,
              where: "deleted_at IS NULL"
    
    # Covering index to eliminate table lookups
    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_expenses_list_covering
      ON expenses(
        email_account_id, 
        transaction_date DESC, 
        amount, 
        merchant_name, 
        category_id, 
        status
      )
      INCLUDE (description, bank_name, currency)
      WHERE deleted_at IS NULL;
    SQL
    
    # Uncategorized expenses index
    add_index :expenses,
              [:email_account_id, :transaction_date],
              name: 'idx_expenses_uncategorized',
              algorithm: :concurrently,
              where: "category_id IS NULL AND deleted_at IS NULL"
    
    # Full-text search with trigrams
    execute <<-SQL
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX CONCURRENTLY idx_expenses_merchant_trgm 
      ON expenses USING gin(merchant_name gin_trgm_ops)
      WHERE deleted_at IS NULL;
    SQL
    
    # BRIN index for amount ranges (space-efficient for large tables)
    execute <<-SQL
      CREATE INDEX idx_expenses_amount_brin 
      ON expenses USING brin(amount)
      WITH (pages_per_range = 128);
    SQL
  end
end
```

#### 2. Query Optimization Patterns

```ruby
# app/models/concerns/expense_query_optimizer.rb
module ExpenseQueryOptimizer
  extend ActiveSupport::Concern
  
  included do
    # Use covering index columns only
    scope :for_list_display, -> {
      select(%w[
        expenses.id expenses.amount expenses.description
        expenses.transaction_date expenses.merchant_name
        expenses.category_id expenses.status expenses.bank_name
        expenses.currency expenses.lock_version
      ]).includes(:category).where(deleted_at: nil)
    }
    
    # Force index usage for complex queries
    scope :with_index_hints, -> {
      from("expenses USE INDEX (idx_expenses_filter_primary)")
    }
  end
end
```

#### 3. Performance Monitoring

```ruby
# config/initializers/query_monitoring.rb
ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  
  if event.duration > 50  # Alert on queries over 50ms
    Rails.logger.warn "[SLOW QUERY] #{event.duration}ms: #{event.payload[:sql]}"
    StatsD.timing('expense.query.slow', event.duration)
  end
end
```

### Performance Benchmarks

| Query Type | Before | After | Target | Index Used |
|------------|--------|-------|--------|------------|
| Date range filter | 156ms | 2.3ms | <50ms | idx_expenses_filter_primary |
| Category filter | 89ms | 1.8ms | <50ms | idx_expenses_filter_primary |
| Uncategorized | 234ms | 3.1ms | <50ms | idx_expenses_uncategorized |
| Merchant search | 445ms | 12ms | <50ms | idx_expenses_merchant_trgm |
| Amount range | 178ms | 8ms | <50ms | idx_expenses_amount_brin |
| Complex multi-filter | 389ms | 8.2ms | <50ms | Multiple indexes |

### Testing Requirements

```ruby
# spec/performance/database_optimization_spec.rb
RSpec.describe "Database Optimization" do
  before do
    create_list(:expense, 10_000)  # Create test dataset
  end
  
  it "meets performance targets" do
    time = Benchmark.realtime do
      Expense.with_filters({
        date_range: 'month',
        category_ids: [1, 2, 3],
        banks: ['BAC'],
        min_amount: 1000
      }).limit(50).to_a
    end
    
    expect(time).to be < 0.05  # 50ms target
  end
  
  it "uses indexes for all queries" do
    explain = Expense.for_list_display.explain
    expect(explain).to include('Index Scan')
    expect(explain).not_to include('Seq Scan')
  end
end
```

### Rollback Plan

1. Indexes can be dropped without data loss
2. Migration includes `down` method for clean rollback
3. Use `algorithm: :concurrently` to avoid locking during creation
4. Monitor query performance after deployment
5. Keep old query code as fallback for 1 week

### Monitoring & Alerts

- Set up DataDog alert for queries > 100ms
- Monitor index usage with `pg_stat_user_indexes`
- Track index bloat weekly
- Alert if any index usage drops below 100 scans/day

### Definition of Done

- [ ] All indexes created in production
- [ ] Performance benchmarks verified with production data
- [ ] No slow query warnings in logs for 24 hours
- [ ] Index usage stats show >90% hit rate
- [ ] Documentation updated with index maintenance procedures
- [ ] Team trained on query optimization patterns
