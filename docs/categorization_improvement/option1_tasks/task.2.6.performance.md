## Performance Optimizations

### Database Indexes

#### Existing Indexes (Already Applied)
The following performance indexes have been successfully implemented:
- `idx_patterns_lookup` - Pattern lookups by type, active status, and success rate
- `idx_feedback_analytics` - Feedback analytics queries
- `idx_uncategorized_expenses` - Finding uncategorized expenses
- Multiple additional indexes for pattern matching and performance

#### Additional Recommended Indexes
```ruby
class AddRemainingPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Composite index for pattern matching with confidence
    add_index :categorization_patterns,
              [:active, :confidence_weight, :success_rate, :usage_count],
              name: 'idx_patterns_matching_performance',
              where: 'active = true'
    
    # Index for merchant-based pattern lookup
    add_index :categorization_patterns,
              [:pattern_type, :pattern_value],
              name: 'idx_patterns_type_value_lookup',
              where: "pattern_type IN ('merchant', 'keyword')"
    
    # Index for feedback trend analysis
    add_index :pattern_feedbacks,
              [:created_at, :feedback_type, :was_correct],
              name: 'idx_feedback_trends'
    
    # Index for expense categorization queue
    add_index :expenses,
              [:status, :category_id, :created_at],
              name: 'idx_expense_categorization_queue',
              where: "status = 'pending' AND category_id IS NULL"
  end
end
```

### Caching Strategy

#### Current Implementation
The application uses a sophisticated two-tier caching system:

1. **Categorization::PatternCache** - Main caching service
   - L1: In-memory cache (5-minute TTL)
   - L2: Redis cache (24-hour TTL) with Solid Cache fallback
   - Automatic cache invalidation
   - Performance metrics and monitoring

2. **Configuration** (`config/initializers/pattern_cache.rb`)
   - Configurable TTL values via environment variables
   - Automatic cache warming on startup
   - Thread-based warming to avoid blocking

#### Pattern Cache Warmer Job
Create a background job for periodic cache refresh:

```ruby
# app/jobs/pattern_cache_warmer_job.rb
class PatternCacheWarmerJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[PatternCacheWarmer] Starting cache warming..."
    
    stats = Categorization::PatternCache.instance.warm_cache
    
    if stats[:error]
      Rails.logger.error "[PatternCacheWarmer] Failed: #{stats[:error]}"
    else
      Rails.logger.info "[PatternCacheWarmer] Completed: #{stats.inspect}"
    end
    
    # Report metrics
    report_metrics(stats) if defined?(Services::Infrastructure::MonitoringService)
  end
  
  private
  
  def report_metrics(stats)
    Services::Infrastructure::MonitoringService.record_metric(
      'pattern_cache.warming',
      stats.except(:error),
      tags: { status: stats[:error] ? 'failed' : 'success' }
    )
  end
end
```

#### Scheduled Cache Warming
Add to Solid Queue recurring tasks:

```ruby
# config/recurring.yml (or in config/initializers/solid_queue.rb)
Rails.application.configure do
  config.solid_queue.recurring_tasks = [
    {
      key: "pattern_cache_warming",
      class_name: "PatternCacheWarmerJob",
      schedule: "every 6 hours",
      description: "Warm pattern cache with frequently used patterns"
    }
  ]
end
```

### Query Optimizations

#### 1. Bulk Categorization Queries
```ruby
# app/services/categorization/bulk_categorization_service.rb
class BulkCategorizationService
  def categorize_batch(expense_ids)
    # Preload all required data
    expenses = Expense.includes(:email_account)
                      .where(id: expense_ids)
    
    # Warm cache for batch
    Categorization::PatternCache.instance.preload_for_expenses(expenses)
    
    # Process with cached data
    expenses.map do |expense|
      categorize_with_cache(expense)
    end
  end
  
  private
  
  def categorize_with_cache(expense)
    # Use cached patterns for categorization
    service = Categorization::CachedCategorizationService.new
    service.categorize(expense)
  end
end
```

#### 2. Pattern Performance Monitoring
```ruby
# app/services/categorization/pattern_performance_monitor.rb
module Categorization
  class PatternPerformanceMonitor
    def self.check_and_optimize
      # Identify poorly performing patterns
      poor_patterns = CategorizationPattern
        .active
        .where('usage_count >= ? AND success_rate < ?', 20, 0.3)
      
      poor_patterns.find_each do |pattern|
        pattern.check_and_deactivate_if_poor_performance
      end
      
      # Log metrics
      Rails.logger.info "[PatternMonitor] Deactivated #{poor_patterns.count} poor patterns"
    end
  end
end
```

### Performance Benchmarks

#### Target Metrics
- Pattern lookup: < 1ms (achieved via PatternCache)
- Bulk categorization: < 100ms for 10 expenses
- Cache hit rate: > 90% for active patterns
- Database query time: < 10ms for indexed queries

#### Monitoring
```ruby
# config/initializers/performance_monitoring.rb
Rails.application.configure do
  # Log slow categorizations
  config.after_initialize do
    ActiveSupport::Notifications.subscribe('categorization.perform') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      
      if event.duration > 100 # ms
        Rails.logger.warn "[Performance] Slow categorization: #{event.duration}ms"
        Rails.logger.warn "  Expense: #{event.payload[:expense_id]}"
        Rails.logger.warn "  Patterns checked: #{event.payload[:patterns_checked]}"
      end
    end
  end
end
```

### Production Deployment Checklist

- [ ] Run migrations for any new indexes
- [ ] Verify Redis connection and configuration
- [ ] Deploy PatternCacheWarmerJob
- [ ] Configure recurring cache warming schedule
- [ ] Monitor cache hit rates and performance metrics
- [ ] Set up alerts for cache failures
- [ ] Test failover to Solid Cache when Redis is unavailable
- [ ] Verify memory usage stays within limits

---

## Implementation Status

### ✅ Completed
- Database indexes for pattern performance
- Two-tier caching system (PatternCache)
- Cache invalidation on model changes
- Cache warming on startup
- Performance metrics collection

### 🔄 In Progress
- PatternCacheWarmerJob implementation
- Recurring task configuration

### 📋 Next Steps
1. Create and test PatternCacheWarmerJob
2. Configure recurring cache warming
3. Set up performance monitoring dashboards
4. Run load tests to validate improvements
5. Document cache tuning parameters

## Performance Testing

### Load Test Scenarios
1. **Pattern Matching**: 1000 expenses categorized in < 10 seconds
2. **Cache Performance**: 95% hit rate under normal load
3. **Database Queries**: All indexed queries < 10ms
4. **Memory Usage**: Cache size stays under 50MB limit

### Monitoring Dashboard
Track these metrics in production:
- Cache hit/miss rates
- Pattern lookup latency (p50, p95, p99)
- Database query performance
- Memory usage trends
- Redis connection health