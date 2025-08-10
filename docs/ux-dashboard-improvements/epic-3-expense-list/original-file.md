---

## Epic 3: Optimized Expense List with Batch Operations

**Epic ID:** EXP-EPIC-003  
**Priority:** High  
**Status:** Not Started  
**Estimated Duration:** 3 weeks  
**Epic Owner:** TBD  

### Epic Description
Transform the expense list to display more information efficiently with compact view, inline actions, batch operations, and smart filtering for improved productivity.

### Business Value
- Doubles information density for better overview
- Reduces interaction cost by 70% for common tasks
- Enables efficient bulk categorization
- Improves pattern recognition in spending

### Success Metrics
- 10 expenses visible without scrolling
- Batch operation usage > 30% of users
- Filter interaction rate > 50%
- Task completion time reduced by 70%

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

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

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

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```