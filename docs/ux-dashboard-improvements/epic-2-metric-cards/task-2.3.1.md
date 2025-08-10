---

## Subtask 2.3.1: Chart Library Integration

**Task ID:** EXP-2.3.1  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 4  

### Description
Integrate Chart.js or similar lightweight charting library for rendering sparklines and other data visualizations.

### Acceptance Criteria
- [ ] Chart library added to project dependencies
- [ ] Bundle size increase < 50KB
- [ ] Library loaded asynchronously
- [ ] Fallback for chart loading failure
- [ ] Configuration for consistent styling
- [ ] Documentation for chart usage

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
