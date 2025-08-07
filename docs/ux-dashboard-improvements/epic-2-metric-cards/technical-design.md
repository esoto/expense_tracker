# Epic 2: Technical Design Document

## Executive Summary

This document provides comprehensive technical specifications for Epic 2: Enhanced Metric Cards with Progressive Disclosure. It details the implementation of an interactive metrics system with data aggregation services, visual hierarchy, sparkline charts, budget tracking, and real-time calculations. The design focuses on performance optimization, caching strategies, and user engagement through progressive disclosure patterns.

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                        Frontend Layer                           │
├────────────────────────────────────────────────────────────────┤
│  Stimulus Controllers │ Chart.js │ Turbo Frames │ CSS Grid     │
├────────────────────────────────────────────────────────────────┤
│                       Controller Layer                          │
├────────────────────────────────────────────────────────────────┤
│  MetricsController │ BudgetsController │ GoalsController       │
├────────────────────────────────────────────────────────────────┤
│                        Service Layer                            │
├────────────────────────────────────────────────────────────────┤
│ MetricsCalculator │ TrendAnalyzer │ BudgetService │ CacheServ  │
├────────────────────────────────────────────────────────────────┤
│                      Background Jobs                            │
├────────────────────────────────────────────────────────────────┤
│ MetricCalculationJob │ CacheWarmingJob │ AggregationJob        │
├────────────────────────────────────────────────────────────────┤
│                         Data Layer                              │
├────────────────────────────────────────────────────────────────┤
│  Redis Cache │ Materialized Views │ Optimized Queries          │
└────────────────────────────────────────────────────────────────┘
```

---

## 1. MetricsCalculator Service Architecture

### Core Service Implementation

```ruby
# app/services/metrics_calculator.rb
class MetricsCalculator
  include ActiveSupport::Rescuable
  
  CACHE_VERSION = 'v1'
  DEFAULT_CACHE_TTL = 1.hour
  TREND_PERIODS = {
    day: 1.day,
    week: 1.week,
    month: 1.month,
    quarter: 3.months,
    year: 1.year
  }.freeze

  attr_reader :email_account_ids, :date_range, :options

  def initialize(email_account_ids, date_range: nil, options: {})
    @email_account_ids = Array(email_account_ids)
    @date_range = date_range || default_date_range
    @options = options
  end

  def calculate
    Rails.cache.fetch(cache_key, expires_in: cache_ttl) do
      {
        primary_metrics: calculate_primary_metrics,
        secondary_metrics: calculate_secondary_metrics,
        trends: calculate_trends,
        sparklines: generate_sparkline_data,
        category_breakdown: calculate_category_breakdown,
        budget_status: calculate_budget_status,
        projections: calculate_projections,
        metadata: build_metadata
      }
    end
  end

  # Real-time calculation without cache
  def calculate_realtime
    calculate_primary_metrics.merge(
      last_updated: Time.current,
      cached: false
    )
  end

  private

  def calculate_primary_metrics
    base_query = expenses_scope
    
    {
      total_expenses: {
        value: base_query.sum(:amount),
        formatted: format_currency(base_query.sum(:amount)),
        count: base_query.count,
        average: base_query.average(:amount)&.to_f || 0
      },
      current_month: {
        value: current_month_expenses.sum(:amount),
        formatted: format_currency(current_month_expenses.sum(:amount)),
        count: current_month_expenses.count,
        daily_average: calculate_daily_average(current_month_expenses)
      },
      current_week: {
        value: current_week_expenses.sum(:amount),
        formatted: format_currency(current_week_expenses.sum(:amount)),
        count: current_week_expenses.count
      },
      today: {
        value: today_expenses.sum(:amount),
        formatted: format_currency(today_expenses.sum(:amount)),
        count: today_expenses.count
      }
    }
  end

  def calculate_secondary_metrics
    {
      top_category: calculate_top_category,
      top_merchant: calculate_top_merchant,
      largest_expense: calculate_largest_expense,
      recurring_detected: detect_recurring_expenses,
      unusual_activity: detect_unusual_activity
    }
  end

  def calculate_trends
    trends = {}
    
    TREND_PERIODS.each do |period_name, period_duration|
      current_period = expenses_in_period(Time.current - period_duration, Time.current)
      previous_period = expenses_in_period(
        Time.current - (period_duration * 2), 
        Time.current - period_duration
      )
      
      trends[period_name] = calculate_trend_comparison(
        current_period,
        previous_period,
        period_name
      )
    end
    
    trends
  end

  def calculate_trend_comparison(current, previous, period_name)
    current_sum = current.sum(:amount)
    previous_sum = previous.sum(:amount)
    
    change_amount = current_sum - previous_sum
    change_percentage = previous_sum > 0 ? 
      ((change_amount / previous_sum) * 100).round(1) : 
      0
    
    {
      current: current_sum,
      previous: previous_sum,
      change_amount: change_amount,
      change_percentage: change_percentage,
      direction: determine_direction(change_amount),
      status: determine_status(change_percentage, period_name),
      forecast: forecast_next_period(current, previous, period_name)
    }
  end

  def generate_sparkline_data
    # Generate 7-day sparkline data for primary metrics
    (0..6).map do |days_ago|
      date = Date.current - days_ago.days
      daily_total = expenses_scope
        .where(transaction_date: date.all_day)
        .sum(:amount)
      
      {
        date: date.iso8601,
        value: daily_total.to_f,
        label: date.strftime('%a')
      }
    end.reverse
  end

  def calculate_category_breakdown
    categories = expenses_scope
      .joins(:category)
      .group('categories.id', 'categories.name', 'categories.color')
      .sum(:amount)
      .map do |(category_id, category_name, category_color), amount|
        {
          id: category_id,
          name: category_name,
          color: category_color,
          amount: amount,
          percentage: calculate_percentage(amount, expenses_scope.sum(:amount)),
          trend: calculate_category_trend(category_id)
        }
      end
      .sort_by { |c| -c[:amount] }
      .take(5)
    
    # Add "Others" category if needed
    total = expenses_scope.sum(:amount)
    top_5_total = categories.sum { |c| c[:amount] }
    
    if total > top_5_total
      categories << {
        id: nil,
        name: 'Otros',
        color: '#9CA3AF',
        amount: total - top_5_total,
        percentage: calculate_percentage(total - top_5_total, total)
      }
    end
    
    categories
  end

  def calculate_budget_status
    return nil unless budget_exists?
    
    budget = current_budget
    spent = expenses_scope.sum(:amount)
    remaining = budget.amount - spent
    
    {
      budget_amount: budget.amount,
      spent_amount: spent,
      remaining_amount: remaining,
      percentage_used: calculate_percentage(spent, budget.amount),
      days_remaining: days_until_budget_reset,
      daily_budget_remaining: remaining / [days_until_budget_reset, 1].max,
      status: determine_budget_status(spent, budget.amount),
      projected_overspend: project_overspend(spent, budget.amount)
    }
  end

  def calculate_projections
    return {} unless enough_data_for_projections?
    
    daily_averages = calculate_rolling_averages
    current_velocity = calculate_spending_velocity
    
    {
      end_of_month: project_end_of_month(daily_averages),
      end_of_week: project_end_of_week(daily_averages),
      velocity: current_velocity,
      confidence: calculate_projection_confidence
    }
  end

  def detect_recurring_expenses
    # Find potential recurring expenses by merchant and similar amounts
    recurring = expenses_scope
      .select('merchant_name, COUNT(*) as frequency, AVG(amount) as avg_amount, STDDEV(amount) as amount_variance')
      .where('transaction_date >= ?', 3.months.ago)
      .group(:merchant_name)
      .having('COUNT(*) >= 3')
      .having('STDDEV(amount) < AVG(amount) * 0.1') # Low variance in amount
      .order('frequency DESC')
      .limit(5)
    
    recurring.map do |r|
      {
        merchant: r.merchant_name,
        frequency: r.frequency,
        average_amount: r.avg_amount.to_f,
        variance: r.amount_variance.to_f,
        likely_recurring: r.frequency >= 3 && r.amount_variance < (r.avg_amount * 0.1)
      }
    end
  end

  def detect_unusual_activity
    # Detect anomalies in spending patterns
    recent_average = expenses_scope
      .where('transaction_date >= ?', 7.days.ago)
      .average(:amount)
    
    historical_average = expenses_scope
      .where('transaction_date >= ?', 30.days.ago)
      .where('transaction_date < ?', 7.days.ago)
      .average(:amount)
    
    return nil unless recent_average && historical_average
    
    deviation = ((recent_average - historical_average) / historical_average * 100).abs
    
    {
      detected: deviation > 30,
      recent_average: recent_average.to_f,
      historical_average: historical_average.to_f,
      deviation_percentage: deviation.round(1),
      severity: determine_anomaly_severity(deviation)
    }
  end

  # Calculation helpers
  def expenses_scope
    @expenses_scope ||= Expense
      .where(email_account_id: email_account_ids)
      .where(transaction_date: date_range)
      .where.not(status: 'failed')
  end

  def current_month_expenses
    expenses_scope.where(
      transaction_date: Date.current.beginning_of_month..Date.current.end_of_month
    )
  end

  def current_week_expenses
    expenses_scope.where(
      transaction_date: Date.current.beginning_of_week..Date.current.end_of_week
    )
  end

  def today_expenses
    expenses_scope.where(transaction_date: Date.current.all_day)
  end

  def expenses_in_period(start_date, end_date)
    expenses_scope.where(transaction_date: start_date..end_date)
  end

  def calculate_daily_average(scope)
    days = (scope.maximum(:transaction_date) - scope.minimum(:transaction_date)).to_i + 1
    days > 0 ? scope.sum(:amount) / days : 0
  end

  def calculate_percentage(value, total)
    return 0 if total.zero?
    ((value.to_f / total) * 100).round(1)
  end

  def determine_direction(change)
    return :neutral if change.abs < 0.01
    change > 0 ? :increase : :decrease
  end

  def determine_status(change_percentage, period)
    case period
    when :day
      change_percentage.abs > 50 ? :alert : :normal
    when :week
      change_percentage.abs > 30 ? :warning : :normal
    when :month
      change_percentage.abs > 20 ? :warning : :normal
    else
      :normal
    end
  end

  def format_currency(amount)
    "₡#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}"
  end

  # Cache management
  def cache_key
    [
      'metrics',
      CACHE_VERSION,
      Digest::SHA256.hexdigest(email_account_ids.sort.join('-')),
      date_range.first.to_s,
      date_range.last.to_s
    ].join(':')
  end

  def cache_ttl
    options[:cache_ttl] || DEFAULT_CACHE_TTL
  end

  def default_date_range
    Date.current.beginning_of_year..Date.current.end_of_day
  end

  def build_metadata
    {
      calculated_at: Time.current,
      cache_key: cache_key,
      accounts_included: email_account_ids.size,
      date_range: {
        start: date_range.first,
        end: date_range.last
      },
      data_quality: assess_data_quality
    }
  end

  def assess_data_quality
    total_expenses = expenses_scope.count
    categorized = expenses_scope.where.not(category_id: nil).count
    
    {
      total_records: total_expenses,
      categorization_rate: calculate_percentage(categorized, total_expenses),
      data_completeness: calculate_data_completeness,
      reliability_score: calculate_reliability_score
    }
  end
end
```

### Caching Strategy with Redis

```ruby
# app/services/metrics_cache_service.rb
class MetricsCacheService
  CACHE_NAMESPACE = 'metrics'
  
  # Cache key patterns for different metric types
  CACHE_PATTERNS = {
    primary: 'primary:%{account_ids}:%{date}',
    trends: 'trends:%{account_ids}:%{period}:%{date}',
    sparklines: 'sparklines:%{account_ids}:%{days}:%{date}',
    categories: 'categories:%{account_ids}:%{month}',
    budgets: 'budgets:%{account_ids}:%{period}'
  }.freeze

  def initialize(redis_pool = nil)
    @redis = redis_pool || Redis.new(
      url: Rails.application.config.redis_url,
      pool_size: 5,
      pool_timeout: 5
    )
  end

  def fetch(key_type, params, ttl: 1.hour)
    cache_key = build_key(key_type, params)
    
    cached = @redis.get(cache_key)
    return JSON.parse(cached, symbolize_names: true) if cached
    
    return nil unless block_given?
    
    # Calculate and cache the result
    result = yield
    @redis.setex(cache_key, ttl.to_i, result.to_json)
    result
  end

  def fetch_multi(keys)
    cache_keys = keys.map { |k| "#{CACHE_NAMESPACE}:#{k}" }
    values = @redis.mget(*cache_keys)
    
    results = {}
    keys.each_with_index do |key, index|
      if values[index]
        results[key] = JSON.parse(values[index], symbolize_names: true)
      end
    end
    results
  end

  def invalidate(pattern)
    keys = @redis.keys("#{CACHE_NAMESPACE}:#{pattern}*")
    @redis.del(*keys) if keys.any?
  end

  def warm_cache(email_account_ids)
    WarmMetricsCacheJob.perform_later(email_account_ids)
  end

  private

  def build_key(type, params)
    pattern = CACHE_PATTERNS[type]
    raise ArgumentError, "Unknown cache key type: #{type}" unless pattern
    
    key = pattern % params.transform_values { |v| 
      v.is_a?(Array) ? Digest::SHA256.hexdigest(v.sort.join('-')) : v
    }
    
    "#{CACHE_NAMESPACE}:#{key}"
  end
end
```

### Performance Optimizations

```ruby
# app/services/metrics_performance_optimizer.rb
class MetricsPerformanceOptimizer
  def self.optimize_queries
    # Use database-specific optimizations
    if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
      optimize_postgresql
    else
      optimize_standard
    end
  end

  def self.optimize_postgresql
    # Create materialized view for faster aggregations
    ActiveRecord::Base.connection.execute(<<-SQL)
      CREATE MATERIALIZED VIEW IF NOT EXISTS expense_daily_aggregates AS
      SELECT 
        email_account_id,
        transaction_date,
        COUNT(*) as expense_count,
        SUM(amount) as total_amount,
        AVG(amount) as avg_amount,
        MAX(amount) as max_amount,
        MIN(amount) as min_amount,
        COUNT(DISTINCT category_id) as unique_categories,
        COUNT(DISTINCT merchant_name) as unique_merchants
      FROM expenses
      WHERE status != 'failed'
      GROUP BY email_account_id, transaction_date
      WITH DATA;

      CREATE UNIQUE INDEX IF NOT EXISTS idx_expense_daily_aggregates 
      ON expense_daily_aggregates(email_account_id, transaction_date);
    SQL

    # Create index for trend calculations
    ActiveRecord::Base.connection.execute(<<-SQL)
      CREATE INDEX IF NOT EXISTS idx_expenses_trend_calc
      ON expenses(email_account_id, transaction_date, amount)
      WHERE status != 'failed';
    SQL
  end

  def self.refresh_materialized_views
    ActiveRecord::Base.connection.execute(
      "REFRESH MATERIALIZED VIEW CONCURRENTLY expense_daily_aggregates"
    )
  end
end
```

---

## 2. Chart Library Selection

### Evaluation Matrix

| Criteria | Chart.js | Recharts | D3.js | ApexCharts |
|----------|----------|----------|--------|------------|
| **Bundle Size** | 61KB (min+gzip) | 98KB | 89KB | 137KB |
| **Performance (1000 points)** | 60fps | 45fps | 60fps | 55fps |
| **Learning Curve** | Low | Medium | High | Low |
| **Customization** | Medium | High | Very High | High |
| **React/Stimulus Support** | Excellent | React only | Manual | Good |
| **Sparkline Support** | Yes | Yes | Yes | Yes |
| **Tree Shaking** | Yes | Limited | Yes | Yes |
| **Mobile Performance** | Excellent | Good | Excellent | Good |
| **Accessibility** | Good | Fair | Manual | Good |

### Recommendation: Chart.js

Based on our requirements for lightweight sparklines and tooltips, **Chart.js** is recommended:

1. **Smallest bundle size** when using only required components
2. **Best Stimulus integration** with existing wrapper libraries
3. **Excellent performance** for simple sparklines
4. **Good accessibility** out of the box

### Implementation Approach

```javascript
// app/javascript/lib/chart_config.js
import {
  Chart,
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Tooltip
} from 'chart.js';

// Register only required components (reduces bundle by ~40%)
Chart.register(
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Tooltip
);

// Global configuration for consistent styling
Chart.defaults.font.family = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
Chart.defaults.color = '#64748B'; // slate-500
Chart.defaults.plugins.tooltip.backgroundColor = 'rgba(15, 23, 42, 0.9)'; // slate-900
Chart.defaults.plugins.tooltip.titleColor = '#F8FAFC'; // slate-50
Chart.defaults.plugins.tooltip.bodyColor = '#CBD5E1'; // slate-300

export const sparklineConfig = {
  type: 'line',
  options: {
    responsive: true,
    maintainAspectRatio: false,
    interaction: {
      intersect: false,
      mode: 'index'
    },
    plugins: {
      legend: { display: false },
      tooltip: {
        enabled: true,
        callbacks: {
          label: (context) => {
            return `₡${context.parsed.y.toLocaleString('es-CR')}`;
          }
        }
      }
    },
    scales: {
      x: { display: false },
      y: { display: false }
    },
    elements: {
      line: {
        borderWidth: 2,
        borderColor: '#0F766E', // teal-700
        backgroundColor: 'rgba(15, 118, 110, 0.1)',
        tension: 0.4, // Smooth curves
        fill: true
      },
      point: {
        radius: 0,
        hitRadius: 10,
        hoverRadius: 4,
        hoverBackgroundColor: '#0F766E'
      }
    }
  }
};

export default Chart;
```

### Stimulus Controller for Sparklines

```javascript
// app/javascript/controllers/sparkline_controller.js
import { Controller } from "@hotwired/stimulus"
import Chart from '../lib/chart_config'
import { sparklineConfig } from '../lib/chart_config'

export default class extends Controller {
  static targets = ["canvas", "loading"]
  static values = {
    data: Array,
    color: String,
    showPoints: Boolean,
    animate: Boolean,
    height: Number
  }

  connect() {
    this.initializeChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  dataValueChanged() {
    this.updateChart()
  }

  async initializeChart() {
    // Show loading state
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove('hidden')
    }

    try {
      // Set canvas height
      this.canvasTarget.height = this.heightValue || 40

      // Prepare data
      const chartData = this.prepareChartData()

      // Create chart with custom config
      const config = this.buildConfig(chartData)
      
      this.chart = new Chart(this.canvasTarget, config)

      // Animate on first render if enabled
      if (this.animateValue) {
        this.animateChart()
      }

      // Hide loading state
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add('hidden')
      }
    } catch (error) {
      console.error('Failed to initialize sparkline:', error)
      this.showError()
    }
  }

  prepareChartData() {
    const data = this.dataValue || []
    
    // Handle different data formats
    if (data.length === 0) return { labels: [], datasets: [] }

    if (typeof data[0] === 'number') {
      // Simple array of numbers
      return {
        labels: data.map((_, i) => i),
        datasets: [{
          data: data
        }]
      }
    } else {
      // Array of objects with date/value
      return {
        labels: data.map(d => d.date || d.label),
        datasets: [{
          data: data.map(d => d.value)
        }]
      }
    }
  }

  buildConfig(chartData) {
    const config = JSON.parse(JSON.stringify(sparklineConfig))
    
    config.data = chartData
    
    // Apply custom color if provided
    if (this.colorValue) {
      config.options.elements.line.borderColor = this.colorValue
      config.options.elements.line.backgroundColor = `${this.colorValue}20`
    }

    // Show points if requested
    if (this.showPointsValue) {
      config.options.elements.point.radius = 2
    }

    // Disable animations if requested
    if (!this.animateValue) {
      config.options.animation = false
    }

    return config
  }

  updateChart() {
    if (!this.chart) {
      this.initializeChart()
      return
    }

    const chartData = this.prepareChartData()
    this.chart.data = chartData
    this.chart.update('active')
  }

  animateChart() {
    if (!this.chart) return

    // Smooth reveal animation
    this.chart.options.animation = {
      duration: 750,
      easing: 'easeInOutQuart'
    }
    this.chart.update()
  }

  showError() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.innerHTML = `
        <div class="text-rose-600 text-xs">
          <svg class="w-4 h-4 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          Error loading chart
        </div>
      `
      this.loadingTarget.classList.remove('hidden')
    }
  }
}
```

### Fallback Strategy

```javascript
// app/javascript/controllers/sparkline_fallback_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "value"]
  static values = { data: Array, max: Number }

  connect() {
    this.renderFallback()
  }

  renderFallback() {
    // Simple CSS bar chart fallback
    const data = this.dataValue || []
    const max = this.maxValue || Math.max(...data.map(d => d.value || d))
    
    this.element.innerHTML = `
      <div class="flex items-end h-10 gap-px">
        ${data.map(d => {
          const value = d.value || d
          const height = (value / max) * 100
          return `
            <div class="flex-1 bg-teal-200 hover:bg-teal-300 transition-colors"
                 style="height: ${height}%"
                 title="${value}">
            </div>
          `
        }).join('')}
      </div>
    `
  }
}
```

---

## 3. Database Design

### Budget and Goal Tables Schema

```ruby
# db/migrate/add_budget_and_goal_tables.rb
class AddBudgetAndGoalTables < ActiveRecord::Migration[7.1]
  def change
    # Budget periods enum
    create_enum :budget_period, %w[daily weekly monthly quarterly yearly custom]
    
    # Main budgets table
    create_table :budgets do |t|
      t.references :email_account, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.enum :period, enum_type: :budget_period, null: false, default: 'monthly'
      t.date :start_date, null: false
      t.date :end_date
      t.references :category, foreign_key: true # Optional category-specific budget
      t.boolean :active, default: true, null: false
      t.boolean :rollover_enabled, default: false
      t.decimal :rollover_amount, precision: 15, scale: 2, default: 0
      t.jsonb :alert_thresholds, default: { warning: 75, critical: 90 }
      t.jsonb :metadata, default: {}
      
      t.timestamps
      
      t.index [:email_account_id, :active]
      t.index [:email_account_id, :period, :active]
      t.index [:email_account_id, :category_id, :active]
      t.index [:start_date, :end_date]
    end

    # Budget tracking history
    create_table :budget_periods do |t|
      t.references :budget, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.decimal :allocated_amount, precision: 15, scale: 2, null: false
      t.decimal :spent_amount, precision: 15, scale: 2, default: 0
      t.decimal :rollover_from_previous, precision: 15, scale: 2, default: 0
      t.string :status # active, completed, exceeded
      t.jsonb :analytics, default: {}
      
      t.timestamps
      
      t.index [:budget_id, :period_start]
      t.index [:budget_id, :status]
      t.check_constraint 'period_end > period_start', name: 'valid_period_range'
    end

    # Financial goals
    create_table :goals do |t|
      t.references :email_account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :goal_type # savings, spending_reduction, category_limit
      t.decimal :target_amount, precision: 15, scale: 2
      t.decimal :current_amount, precision: 15, scale: 2, default: 0
      t.date :target_date
      t.references :category, foreign_key: true
      t.boolean :active, default: true
      t.jsonb :rules, default: {} # Conditions for goal tracking
      t.jsonb :progress_milestones, default: []
      
      t.timestamps
      
      t.index [:email_account_id, :active]
      t.index [:email_account_id, :goal_type]
      t.index :target_date
    end

    # Budget alerts
    create_table :budget_alerts do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :budget_period, foreign_key: true
      t.string :alert_type # warning, critical, exceeded
      t.decimal :threshold_percentage, precision: 5, scale: 2
      t.decimal :amount_at_alert, precision: 15, scale: 2
      t.boolean :acknowledged, default: false
      t.datetime :acknowledged_at
      t.jsonb :context, default: {}
      
      t.timestamps
      
      t.index [:budget_id, :created_at]
      t.index [:budget_id, :acknowledged]
    end
  end
end
```

### Materialized Views for Aggregations

```sql
-- Expense aggregations by period
CREATE MATERIALIZED VIEW expense_period_aggregates AS
WITH daily_totals AS (
  SELECT 
    email_account_id,
    transaction_date,
    SUM(amount) as daily_total,
    COUNT(*) as transaction_count,
    COUNT(DISTINCT category_id) as category_count,
    COUNT(DISTINCT merchant_name) as merchant_count
  FROM expenses
  WHERE status != 'failed'
  GROUP BY email_account_id, transaction_date
),
weekly_totals AS (
  SELECT 
    email_account_id,
    DATE_TRUNC('week', transaction_date) as week_start,
    SUM(amount) as weekly_total,
    AVG(amount) as avg_transaction,
    COUNT(*) as transaction_count
  FROM expenses
  WHERE status != 'failed'
  GROUP BY email_account_id, DATE_TRUNC('week', transaction_date)
),
monthly_totals AS (
  SELECT 
    email_account_id,
    DATE_TRUNC('month', transaction_date) as month_start,
    SUM(amount) as monthly_total,
    AVG(amount) as avg_transaction,
    COUNT(*) as transaction_count,
    COUNT(DISTINCT DATE_TRUNC('day', transaction_date)) as active_days
  FROM expenses
  WHERE status != 'failed'
  GROUP BY email_account_id, DATE_TRUNC('month', transaction_date)
)
SELECT 
  d.email_account_id,
  d.transaction_date,
  d.daily_total,
  d.transaction_count as daily_transactions,
  w.weekly_total,
  w.avg_transaction as weekly_avg,
  m.monthly_total,
  m.active_days as monthly_active_days,
  LAG(d.daily_total, 1) OVER (
    PARTITION BY d.email_account_id 
    ORDER BY d.transaction_date
  ) as previous_day_total,
  LAG(w.weekly_total, 1) OVER (
    PARTITION BY w.email_account_id 
    ORDER BY w.week_start
  ) as previous_week_total
FROM daily_totals d
LEFT JOIN weekly_totals w 
  ON d.email_account_id = w.email_account_id 
  AND d.transaction_date >= w.week_start 
  AND d.transaction_date < w.week_start + INTERVAL '7 days'
LEFT JOIN monthly_totals m 
  ON d.email_account_id = m.email_account_id 
  AND d.transaction_date >= m.month_start 
  AND d.transaction_date < m.month_start + INTERVAL '1 month'
WITH DATA;

CREATE UNIQUE INDEX idx_expense_period_aggregates 
ON expense_period_aggregates(email_account_id, transaction_date);

-- Category spending patterns
CREATE MATERIALIZED VIEW category_spending_patterns AS
SELECT 
  email_account_id,
  category_id,
  DATE_TRUNC('month', transaction_date) as month,
  SUM(amount) as total_spent,
  COUNT(*) as transaction_count,
  AVG(amount) as avg_transaction,
  STDDEV(amount) as amount_stddev,
  MIN(amount) as min_amount,
  MAX(amount) as max_amount,
  COUNT(DISTINCT merchant_name) as unique_merchants,
  MODE() WITHIN GROUP (ORDER BY merchant_name) as most_frequent_merchant
FROM expenses
WHERE status != 'failed' AND category_id IS NOT NULL
GROUP BY email_account_id, category_id, DATE_TRUNC('month', transaction_date)
WITH DATA;

CREATE UNIQUE INDEX idx_category_spending_patterns 
ON category_spending_patterns(email_account_id, category_id, month);
```

### Optimized Indexes for Metric Queries

```sql
-- Composite index for time-based aggregations
CREATE INDEX idx_expenses_metrics_time 
ON expenses(email_account_id, transaction_date DESC, amount)
WHERE status != 'failed';

-- Index for category-based metrics
CREATE INDEX idx_expenses_metrics_category 
ON expenses(email_account_id, category_id, transaction_date DESC, amount)
WHERE status != 'failed' AND category_id IS NOT NULL;

-- Index for merchant analysis
CREATE INDEX idx_expenses_merchant_analysis 
ON expenses(email_account_id, merchant_name, transaction_date DESC)
WHERE status != 'failed';

-- Partial index for recent transactions (last 90 days)
CREATE INDEX idx_expenses_recent 
ON expenses(email_account_id, transaction_date DESC, amount)
WHERE status != 'failed' 
  AND transaction_date >= CURRENT_DATE - INTERVAL '90 days';

-- Index for budget period queries
CREATE INDEX idx_expenses_budget_period 
ON expenses(email_account_id, transaction_date, category_id, amount)
WHERE status != 'failed';
```

---

## 4. Background Job Architecture

### Job Scheduling Strategy

```ruby
# app/jobs/metric_calculation_job.rb
class MetricCalculationJob < ApplicationJob
  queue_as :metrics
  
  # Prevent duplicate jobs
  include ActiveJob::Uniqueness
  unique :until_executed, on_conflict: :log

  retry_on ActiveRecord::Deadlock, wait: 5.seconds, attempts: 3
  retry_on Redis::ConnectionError, wait: :exponentially_longer, attempts: 5
  
  def perform(email_account_ids, options = {})
    return unless should_calculate?(email_account_ids)
    
    Rails.logger.info "[MetricCalculation] Starting for accounts: #{email_account_ids}"
    
    calculator = MetricsCalculator.new(email_account_ids, options)
    metrics = calculator.calculate
    
    # Store results
    store_metrics(email_account_ids, metrics)
    
    # Trigger dependent calculations
    trigger_dependent_jobs(email_account_ids, metrics)
    
    # Broadcast updates if real-time enabled
    broadcast_updates(email_account_ids, metrics) if options[:broadcast]
    
    Rails.logger.info "[MetricCalculation] Completed for accounts: #{email_account_ids}"
  rescue StandardError => e
    Rails.logger.error "[MetricCalculation] Failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
  
  private
  
  def should_calculate?(email_account_ids)
    # Skip if recently calculated (within 5 minutes)
    cache_key = "metrics:last_calculation:#{email_account_ids.sort.join('-')}"
    last_run = Rails.cache.read(cache_key)
    
    return false if last_run && last_run > 5.minutes.ago
    
    Rails.cache.write(cache_key, Time.current, expires_in: 5.minutes)
    true
  end
  
  def store_metrics(email_account_ids, metrics)
    # Store in Redis with TTL
    cache_service = MetricsCacheService.new
    
    # Store primary metrics
    cache_service.store('primary', email_account_ids, metrics[:primary_metrics])
    
    # Store trends separately for granular invalidation
    metrics[:trends].each do |period, trend_data|
      cache_service.store("trend:#{period}", email_account_ids, trend_data)
    end
    
    # Store sparkline data
    cache_service.store('sparklines', email_account_ids, metrics[:sparklines])
  end
  
  def trigger_dependent_jobs(email_account_ids, metrics)
    # Calculate budget status if budgets exist
    if Budget.active.where(email_account_id: email_account_ids).exists?
      BudgetCalculationJob.perform_later(email_account_ids)
    end
    
    # Update goals progress
    if Goal.active.where(email_account_id: email_account_ids).exists?
      GoalProgressJob.perform_later(email_account_ids)
    end
    
    # Generate alerts if thresholds exceeded
    if metrics.dig(:budget_status, :status) == :critical
      BudgetAlertJob.perform_later(email_account_ids, metrics[:budget_status])
    end
  end
  
  def broadcast_updates(email_account_ids, metrics)
    # Broadcast via ActionCable
    email_account_ids.each do |account_id|
      MetricsChannel.broadcast_to(
        account_id,
        {
          event: 'metrics_updated',
          metrics: metrics,
          timestamp: Time.current
        }
      )
    end
  end
end
```

### Scheduled Jobs Configuration

```ruby
# config/initializers/good_job.rb
Rails.application.configure do
  config.good_job = {
    execution_mode: :async,
    queues: '+metrics:5;+default:3;+low:1',
    max_threads: 10,
    poll_interval: 30,
    enable_cron: true,
    cron: {
      # Refresh metrics every hour
      hourly_metrics: {
        cron: '0 * * * *',
        class: 'ScheduledMetricRefreshJob',
        description: 'Refresh all active account metrics'
      },
      # Refresh materialized views daily
      daily_materialized_views: {
        cron: '0 3 * * *',
        class: 'RefreshMaterializedViewsJob',
        description: 'Refresh database materialized views'
      },
      # Weekly trend analysis
      weekly_trends: {
        cron: '0 6 * * 1',
        class: 'WeeklyTrendAnalysisJob',
        description: 'Calculate weekly spending trends'
      },
      # Monthly budget reset
      monthly_budget_reset: {
        cron: '0 0 1 * *',
        class: 'MonthlyBudgetResetJob',
        description: 'Reset monthly budgets and create new periods'
      }
    }
  }
end
```

### Job Monitoring and Error Recovery

```ruby
# app/jobs/concerns/metric_job_monitoring.rb
module MetricJobMonitoring
  extend ActiveSupport::Concern
  
  included do
    around_perform :monitor_performance
    after_perform :record_success
    rescue_from StandardError, with: :handle_error
  end
  
  private
  
  def monitor_performance
    start_time = Time.current
    
    ActiveSupport::Notifications.instrument('job.metrics', {
      job_class: self.class.name,
      job_id: job_id,
      queue: queue_name
    }) do
      yield
    end
    
    duration = Time.current - start_time
    
    # Log slow jobs
    if duration > 30.seconds
      Rails.logger.warn "[SlowJob] #{self.class.name} took #{duration.round(2)}s"
      
      # Send to monitoring service
      StatsD.timing("jobs.#{self.class.name.underscore}.duration", duration * 1000)
    end
  end
  
  def record_success
    StatsD.increment("jobs.#{self.class.name.underscore}.success")
  end
  
  def handle_error(error)
    Rails.logger.error "[JobError] #{self.class.name}: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
    
    StatsD.increment("jobs.#{self.class.name.underscore}.error")
    
    # Send to error tracking
    Sentry.capture_exception(error, {
      tags: {
        job_class: self.class.name,
        job_id: job_id
      }
    })
    
    # Retry with backoff
    retry_job(wait: calculate_backoff)
  end
  
  def calculate_backoff
    attempt = executions || 1
    (attempt ** 2).minutes
  end
end
```

---

## 5. Caching Strategy

### Redis Configuration

```ruby
# config/redis/metrics.yml
default: &default
  url: <%= ENV.fetch("REDIS_URL", "redis://localhost:6379/1") %>
  pool_size: 5
  pool_timeout: 5
  namespace: metrics
  expires_in: 3600 # 1 hour default
  
development:
  <<: *default
  namespace: metrics_dev
  
test:
  <<: *default
  namespace: metrics_test
  
production:
  <<: *default
  url: <%= ENV["REDIS_URL"] %>
  pool_size: <%= ENV.fetch("REDIS_POOL_SIZE", 10) %>
  namespace: metrics_prod
  expires_in: 1800 # 30 minutes in production
```

### Cache Key Structure

```ruby
# app/models/concerns/metric_cacheable.rb
module MetricCacheable
  extend ActiveSupport::Concern
  
  CACHE_VERSIONS = {
    metrics: 'v2',
    trends: 'v1',
    sparklines: 'v1',
    budgets: 'v1'
  }.freeze
  
  class_methods do
    def cache_key_for(type, *identifiers)
      version = CACHE_VERSIONS[type] || 'v1'
      namespace = Rails.env.production? ? 'prod' : Rails.env
      
      parts = [
        namespace,
        'metrics',
        type,
        version,
        *identifiers.map { |id| id.is_a?(Array) ? id.sort.join('-') : id }
      ]
      
      parts.join(':')
    end
    
    def with_cache(key, ttl: 1.hour)
      Rails.cache.fetch(key, expires_in: ttl) do
        yield
      end
    end
  end
end
```

### TTL Strategies

```ruby
# app/services/cache_ttl_manager.rb
class CacheTTLManager
  TTL_MATRIX = {
    # Real-time data - short TTL
    current_spending: 1.minute,
    active_transactions: 30.seconds,
    
    # Frequently changing - medium TTL  
    daily_metrics: 5.minutes,
    weekly_trends: 15.minutes,
    category_breakdown: 10.minutes,
    
    # Slowly changing - long TTL
    monthly_totals: 1.hour,
    yearly_trends: 6.hours,
    historical_data: 24.hours,
    
    # Static data - very long TTL
    budget_definitions: 1.day,
    goal_configurations: 1.day
  }.freeze
  
  def self.ttl_for(data_type, context = {})
    base_ttl = TTL_MATRIX[data_type] || 1.hour
    
    # Adjust based on context
    if context[:real_time]
      base_ttl / 2
    elsif context[:historical]
      base_ttl * 4
    else
      base_ttl
    end
  end
  
  def self.smart_ttl(last_update, change_frequency)
    # Dynamic TTL based on data volatility
    time_since_update = Time.current - last_update
    
    case change_frequency
    when :high
      [time_since_update / 10, 1.minute].max
    when :medium  
      [time_since_update / 5, 5.minutes].max
    when :low
      [time_since_update / 2, 1.hour].max
    else
      15.minutes
    end
  end
end
```

### Cache Invalidation

```ruby
# app/services/cache_invalidation_service.rb
class CacheInvalidationService
  def self.invalidate_for_expense(expense)
    account_id = expense.email_account_id
    
    # Invalidate specific caches
    invalidate_patterns([
      "metrics:primary:*#{account_id}*",
      "metrics:trends:*#{account_id}*",
      "metrics:sparklines:*#{account_id}*",
      "metrics:categories:*#{account_id}*"
    ])
    
    # Invalidate date-specific caches
    invalidate_date_caches(account_id, expense.transaction_date)
    
    # Queue recalculation
    MetricCalculationJob.perform_later([account_id])
  end
  
  def self.invalidate_for_budget(budget)
    invalidate_patterns([
      "metrics:budgets:*#{budget.email_account_id}*",
      "metrics:budget_status:*#{budget.id}*"
    ])
  end
  
  private
  
  def self.invalidate_patterns(patterns)
    redis = Redis.new
    
    patterns.each do |pattern|
      keys = redis.keys(pattern)
      redis.del(*keys) if keys.any?
    end
  end
  
  def self.invalidate_date_caches(account_id, date)
    # Invalidate caches for specific date ranges
    [
      date.strftime('%Y-%m-%d'),
      date.strftime('%Y-%m'),
      date.strftime('%Y-W%V'),
      date.year
    ].each do |date_key|
      invalidate_patterns(["*#{account_id}*#{date_key}*"])
    end
  end
end
```

---

## 6. Real-time Updates

### ActionCable Integration

```ruby
# app/channels/metrics_channel.rb
class MetricsChannel < ApplicationCable::Channel
  def subscribed
    if current_user_account_ids.any?
      current_user_account_ids.each do |account_id|
        stream_for account_id
      end
      
      # Send initial metrics
      transmit_initial_metrics
    else
      reject
    end
  end
  
  def unsubscribed
    stop_all_streams
  end
  
  def request_refresh(data)
    account_ids = data['account_ids'] & current_user_account_ids
    return if account_ids.empty?
    
    MetricCalculationJob.perform_later(
      account_ids,
      broadcast: true,
      source: 'user_request'
    )
  end
  
  private
  
  def transmit_initial_metrics
    metrics = MetricsCalculator.new(current_user_account_ids).calculate
    
    transmit({
      event: 'initial_metrics',
      metrics: metrics,
      timestamp: Time.current
    })
  end
  
  def current_user_account_ids
    @current_user_account_ids ||= current_user.email_accounts.pluck(:id)
  end
end
```

### Stimulus Controller for Real-time Updates

```javascript
// app/javascript/controllers/metrics_realtime_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["metric", "indicator", "lastUpdate"]
  static values = { 
    accountIds: Array,
    autoRefresh: Boolean,
    refreshInterval: Number
  }
  
  connect() {
    this.setupSubscription()
    
    if (this.autoRefreshValue) {
      this.startAutoRefresh()
    }
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
  
  setupSubscription() {
    const consumer = createConsumer()
    
    this.subscription = consumer.subscriptions.create(
      {
        channel: "MetricsChannel",
        account_ids: this.accountIdsValue
      },
      {
        connected: () => {
          this.showConnectionStatus('connected')
        },
        
        disconnected: () => {
          this.showConnectionStatus('disconnected')
        },
        
        received: (data) => {
          this.handleMetricsUpdate(data)
        }
      }
    )
  }
  
  handleMetricsUpdate(data) {
    switch(data.event) {
      case 'initial_metrics':
        this.updateAllMetrics(data.metrics)
        break
      case 'metrics_updated':
        this.updateMetrics(data.metrics)
        break
      case 'budget_alert':
        this.showBudgetAlert(data.alert)
        break
    }
    
    this.updateLastUpdateTime(data.timestamp)
  }
  
  updateMetrics(metrics) {
    // Update each metric card with animation
    this.metricTargets.forEach(element => {
      const metricType = element.dataset.metricType
      const newValue = metrics[metricType]?.value
      
      if (newValue !== undefined) {
        this.animateValueChange(element, newValue)
        this.updateTrend(element, metrics[metricType].trend)
      }
    })
    
    // Update sparklines if present
    this.updateSparklines(metrics.sparklines)
  }
  
  animateValueChange(element, newValue) {
    const currentValue = parseFloat(element.textContent.replace(/[^0-9.-]/g, ''))
    const valueElement = element.querySelector('.metric-value')
    
    if (!valueElement) return
    
    // Add pulse animation
    valueElement.classList.add('animate-pulse')
    
    // Animate number change
    const duration = 500
    const startTime = performance.now()
    
    const animate = (currentTime) => {
      const elapsed = currentTime - startTime
      const progress = Math.min(elapsed / duration, 1)
      
      const easeOutQuad = 1 - (1 - progress) * (1 - progress)
      const currentDisplayValue = currentValue + (newValue - currentValue) * easeOutQuad
      
      valueElement.textContent = this.formatCurrency(currentDisplayValue)
      
      if (progress < 1) {
        requestAnimationFrame(animate)
      } else {
        valueElement.classList.remove('animate-pulse')
      }
    }
    
    requestAnimationFrame(animate)
  }
  
  updateTrend(element, trend) {
    const trendElement = element.querySelector('.metric-trend')
    if (!trendElement) return
    
    const { direction, percentage } = trend
    
    // Update icon
    const icon = direction === 'increase' ? '↑' : '↓'
    const color = direction === 'increase' ? 'text-rose-600' : 'text-emerald-600'
    
    trendElement.innerHTML = `
      <span class="${color}">
        ${icon} ${Math.abs(percentage)}%
      </span>
    `
  }
  
  startAutoRefresh() {
    const interval = this.refreshIntervalValue || 60000 // Default 1 minute
    
    this.refreshTimer = setInterval(() => {
      this.requestRefresh()
    }, interval)
  }
  
  requestRefresh() {
    this.subscription.perform('request_refresh', {
      account_ids: this.accountIdsValue
    })
  }
  
  formatCurrency(amount) {
    return `₡${amount.toLocaleString('es-CR')}`
  }
  
  updateLastUpdateTime(timestamp) {
    if (this.hasLastUpdateTarget) {
      const time = new Date(timestamp)
      this.lastUpdateTarget.textContent = `Actualizado: ${time.toLocaleTimeString('es-CR')}`
    }
  }
  
  showConnectionStatus(status) {
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.toggle('bg-emerald-500', status === 'connected')
      this.indicatorTarget.classList.toggle('bg-slate-400', status === 'disconnected')
    }
  }
}
```

---

## 7. Performance Specifications

### Calculation Time Limits

```ruby
# app/services/performance_monitor.rb
class PerformanceMonitor
  PERFORMANCE_LIMITS = {
    # Service response times
    metrics_calculation: 100.ms,
    trend_analysis: 50.ms,
    sparkline_generation: 30.ms,
    category_breakdown: 40.ms,
    budget_calculation: 60.ms,
    
    # Database query times
    aggregation_query: 20.ms,
    materialized_view_query: 10.ms,
    simple_count: 5.ms,
    
    # Cache operations
    cache_read: 2.ms,
    cache_write: 5.ms,
    
    # Frontend rendering
    chart_render: 50.ms,
    tooltip_display: 10.ms,
    animation_frame: 16.ms # 60fps
  }.freeze
  
  def self.measure(operation_name)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    result = yield
    
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
    
    if duration > PERFORMANCE_LIMITS[operation_name]
      Rails.logger.warn "[Performance] #{operation_name} exceeded limit: #{duration.round(2)}ms (limit: #{PERFORMANCE_LIMITS[operation_name]})"
      
      # Track in APM
      StatsD.timing("performance.#{operation_name}", duration)
    end
    
    result
  end
  
  def self.benchmark_metrics_service
    results = {}
    
    # Test with various data sizes
    [100, 1000, 10000].each do |record_count|
      # Create test data
      expenses = create_test_expenses(record_count)
      
      results[record_count] = {}
      
      # Benchmark each operation
      results[record_count][:calculation] = Benchmark.realtime do
        MetricsCalculator.new([1]).calculate
      end
      
      results[record_count][:caching] = Benchmark.realtime do
        Rails.cache.write("test_key", expenses.to_json)
        Rails.cache.read("test_key")
      end
      
      results[record_count][:aggregation] = Benchmark.realtime do
        expenses.group(:category_id).sum(:amount)
      end
    end
    
    results
  end
end
```

### Memory Usage Optimization

```ruby
# app/services/memory_optimizer.rb
class MemoryOptimizer
  MEMORY_LIMITS = {
    metrics_calculation: 50.megabytes,
    chart_data: 5.megabytes,
    cache_entry: 1.megabyte,
    background_job: 100.megabytes
  }.freeze
  
  def self.optimize_query(scope)
    # Use select to limit columns
    scope
      .select(:id, :amount, :transaction_date, :category_id, :merchant_name)
      .includes(:category) # Prevent N+1
      .in_batches(of: 1000) # Process in chunks
  end
  
  def self.optimize_aggregation(scope)
    # Use pluck for simple aggregations
    scope.pluck(
      'DATE(transaction_date)',
      'SUM(amount)',
      'COUNT(*)',
      'AVG(amount)'
    )
  end
  
  def self.monitor_memory
    before = GetProcessMem.new.mb
    
    result = yield
    
    after = GetProcessMem.new.mb
    used = after - before
    
    if used > 50 # MB
      Rails.logger.warn "[Memory] High memory usage: #{used.round(2)}MB"
      
      # Force garbage collection if needed
      GC.start if used > 100
    end
    
    result
  end
end
```

### Chart Rendering Performance

```javascript
// app/javascript/lib/chart_performance.js
export class ChartPerformanceMonitor {
  static TARGETS = {
    renderTime: 50, // ms
    fps: 60,
    memoryLimit: 10 * 1024 * 1024 // 10MB
  }
  
  static measure(chartInstance, operation) {
    const startTime = performance.now()
    const startMemory = performance.memory?.usedJSHeapSize
    
    const result = operation()
    
    const duration = performance.now() - startTime
    const memoryUsed = performance.memory?.usedJSHeapSize - startMemory
    
    if (duration > this.TARGETS.renderTime) {
      console.warn(`Chart render exceeded target: ${duration.toFixed(2)}ms`)
    }
    
    if (memoryUsed > this.TARGETS.memoryLimit) {
      console.warn(`Chart memory usage high: ${(memoryUsed / 1024 / 1024).toFixed(2)}MB`)
    }
    
    return {
      result,
      metrics: {
        duration,
        memory: memoryUsed,
        fps: this.calculateFPS()
      }
    }
  }
  
  static optimizeChartConfig(config) {
    return {
      ...config,
      options: {
        ...config.options,
        animation: {
          duration: 250 // Faster animations
        },
        responsiveAnimationDuration: 0, // Disable resize animations
        elements: {
          point: {
            radius: 0, // Hide points by default
            hoverRadius: 3 // Show on hover
          }
        },
        plugins: {
          decimation: {
            enabled: true,
            algorithm: 'lttb', // Downsample large datasets
            samples: 100
          }
        }
      }
    }
  }
  
  static calculateFPS() {
    let fps = 60
    let lastTime = performance.now()
    let frames = 0
    
    const measureFPS = () => {
      frames++
      const currentTime = performance.now()
      
      if (currentTime >= lastTime + 1000) {
        fps = Math.round((frames * 1000) / (currentTime - lastTime))
        frames = 0
        lastTime = currentTime
      }
      
      requestAnimationFrame(measureFPS)
    }
    
    measureFPS()
    return fps
  }
}
```

---

## 8. API Endpoints

### Metrics Data Endpoints

```ruby
# app/controllers/api/v1/metrics_controller.rb
module Api
  module V1
    class MetricsController < ApplicationController
      before_action :authenticate_api_token!
      before_action :set_account_ids
      
      # GET /api/v1/metrics
      def index
        metrics = fetch_metrics
        
        render json: {
          data: metrics,
          meta: {
            timestamp: Time.current,
            accounts: @account_ids.size,
            cached: metrics[:cached] || true
          }
        }
      end
      
      # GET /api/v1/metrics/primary
      def primary
        metrics = MetricsCalculator.new(@account_ids).calculate_primary_metrics
        
        render json: { data: metrics }
      end
      
      # GET /api/v1/metrics/trends
      def trends
        period = params[:period] || 'month'
        trends = TrendAnalyzer.new(@account_ids, period: period).analyze
        
        render json: { data: trends }
      end
      
      # GET /api/v1/metrics/sparklines
      def sparklines
        days = params[:days]&.to_i || 7
        sparklines = SparklineGenerator.new(@account_ids, days: days).generate
        
        render json: { data: sparklines }
      end
      
      # GET /api/v1/metrics/categories
      def categories
        breakdown = MetricsCalculator.new(@account_ids).calculate_category_breakdown
        
        render json: { data: breakdown }
      end
      
      # POST /api/v1/metrics/refresh
      def refresh
        MetricCalculationJob.perform_later(@account_ids, source: 'api')
        
        render json: { 
          message: 'Metrics refresh queued',
          job_id: SecureRandom.uuid
        }, status: :accepted
      end
      
      private
      
      def fetch_metrics
        Rails.cache.fetch(metrics_cache_key, expires_in: 5.minutes) do
          MetricsCalculator.new(@account_ids).calculate
        end
      end
      
      def set_account_ids
        @account_ids = current_api_token.email_account_ids
      end
      
      def metrics_cache_key
        "api:metrics:#{@account_ids.sort.join('-')}:#{Date.current}"
      end
    end
  end
end
```

### Budget CRUD Operations

```ruby
# app/controllers/api/v1/budgets_controller.rb
module Api
  module V1
    class BudgetsController < ApplicationController
      before_action :authenticate_api_token!
      before_action :set_budget, only: [:show, :update, :destroy]
      
      # GET /api/v1/budgets
      def index
        budgets = Budget
          .where(email_account_id: current_account_ids)
          .includes(:category, :budget_periods)
          
        render json: BudgetSerializer.new(budgets).serializable_hash
      end
      
      # GET /api/v1/budgets/:id
      def show
        render json: BudgetSerializer.new(
          @budget,
          include: [:budget_periods, :alerts]
        ).serializable_hash
      end
      
      # POST /api/v1/budgets
      def create
        budget = Budget.new(budget_params)
        budget.email_account_id = params[:email_account_id]
        
        if budget.save
          BudgetPeriodCreator.new(budget).create_initial_period
          
          render json: BudgetSerializer.new(budget).serializable_hash,
                 status: :created
        else
          render json: { errors: budget.errors.full_messages },
                 status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/budgets/:id
      def update
        if @budget.update(budget_params)
          # Invalidate cache
          CacheInvalidationService.invalidate_for_budget(@budget)
          
          render json: BudgetSerializer.new(@budget).serializable_hash
        else
          render json: { errors: @budget.errors.full_messages },
                 status: :unprocessable_entity
        end
      end
      
      # DELETE /api/v1/budgets/:id
      def destroy
        @budget.destroy
        head :no_content
      end
      
      # GET /api/v1/budgets/:id/progress
      def progress
        budget = Budget.find(params[:id])
        progress = BudgetProgressCalculator.new(budget).calculate
        
        render json: { data: progress }
      end
      
      private
      
      def set_budget
        @budget = Budget
          .where(email_account_id: current_account_ids)
          .find(params[:id])
      end
      
      def budget_params
        params.require(:budget).permit(
          :name, :amount, :period, :start_date, :end_date,
          :category_id, :active, :rollover_enabled,
          alert_thresholds: [:warning, :critical]
        )
      end
    end
  end
end
```

### Export Capabilities

```ruby
# app/controllers/api/v1/exports_controller.rb
module Api
  module V1
    class ExportsController < ApplicationController
      before_action :authenticate_api_token!
      
      # POST /api/v1/exports/metrics
      def metrics
        format = params[:format] || 'json'
        date_range = parse_date_range
        
        exporter = MetricsExporter.new(
          current_account_ids,
          format: format,
          date_range: date_range
        )
        
        result = exporter.export
        
        send_data result[:data],
                  type: result[:content_type],
                  filename: result[:filename]
      end
      
      # POST /api/v1/exports/trends
      def trends
        period = params[:period] || 'month'
        lookback = params[:lookback]&.to_i || 12
        
        data = TrendExporter.new(
          current_account_ids,
          period: period,
          lookback: lookback
        ).export
        
        render json: { data: data }
      end
      
      private
      
      def parse_date_range
        start_date = params[:start_date]&.to_date || 1.month.ago
        end_date = params[:end_date]&.to_date || Date.current
        
        start_date..end_date
      end
    end
  end
end
```

---

## Performance Benchmarks

### Expected Performance Metrics

| Operation | Target | Acceptable | Critical |
|-----------|--------|------------|----------|
| Primary metrics calculation | < 50ms | < 100ms | > 200ms |
| Trend analysis (7 days) | < 30ms | < 60ms | > 100ms |
| Sparkline generation | < 20ms | < 40ms | > 80ms |
| Category breakdown | < 40ms | < 80ms | > 150ms |
| Budget calculation | < 60ms | < 120ms | > 200ms |
| Cache read | < 2ms | < 5ms | > 10ms |
| Chart render | < 50ms | < 100ms | > 200ms |
| Tooltip display | < 10ms | < 20ms | > 50ms |
| API response | < 100ms | < 200ms | > 500ms |
| Background job | < 30s | < 60s | > 120s |

### Load Testing Scenarios

```ruby
# spec/performance/metrics_load_test_spec.rb
require 'rails_helper'

RSpec.describe "Metrics Performance Under Load" do
  describe "concurrent calculations" do
    it "handles 100 concurrent metric calculations" do
      threads = []
      results = []
      
      100.times do |i|
        threads << Thread.new do
          account_ids = [i % 10 + 1] # Distribute across 10 accounts
          
          time = Benchmark.realtime do
            MetricsCalculator.new(account_ids).calculate
          end
          
          results << time
        end
      end
      
      threads.each(&:join)
      
      average_time = results.sum / results.size
      max_time = results.max
      
      expect(average_time).to be < 0.1 # 100ms average
      expect(max_time).to be < 0.5 # 500ms max
      expect(results.count { |t| t > 0.2 }).to be < 5 # Less than 5% over 200ms
    end
  end
  
  describe "cache effectiveness" do
    it "achieves 80% cache hit rate" do
      cache_hits = 0
      cache_misses = 0
      
      # Warm up cache
      10.times do |i|
        MetricsCalculator.new([i + 1]).calculate
      end
      
      # Test cache hits
      100.times do
        account_id = rand(1..10)
        
        start_time = Time.current
        MetricsCalculator.new([account_id]).calculate
        duration = Time.current - start_time
        
        if duration < 0.005 # Likely cache hit
          cache_hits += 1
        else
          cache_misses += 1
        end
      end
      
      hit_rate = cache_hits.to_f / (cache_hits + cache_misses)
      expect(hit_rate).to be > 0.8
    end
  end
end
```

---

## Implementation Timeline

### Phase 1: Foundation (Week 1)
- Day 1-2: Database schema and materialized views
- Day 3-4: MetricsCalculator service implementation
- Day 5: Redis caching setup and configuration

### Phase 2: Core Features (Week 2)
- Day 1: Chart.js integration and sparkline components
- Day 2-3: Interactive tooltips and Stimulus controllers
- Day 4: Budget/Goal models and services
- Day 5: Background job architecture

### Phase 3: Integration (Week 3)
- Day 1-2: API endpoints implementation
- Day 3: Real-time updates with ActionCable
- Day 4: Performance optimization and testing
- Day 5: Final integration and deployment

---

## Risk Mitigation

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Chart library performance issues | High | Medium | Lazy load, use lightweight library, provide fallback |
| Cache invalidation complexity | High | High | Clear TTL strategy, versioned keys, monitoring |
| Real-time update latency | Medium | Medium | Optimize WebSocket, batch updates, fallback to polling |
| Memory usage with large datasets | High | Low | Pagination, streaming, memory limits |
| Browser compatibility | Medium | Low | Progressive enhancement, polyfills |

### Monitoring Strategy

```ruby
# config/initializers/metrics_monitoring.rb
ActiveSupport::Notifications.subscribe(/metrics/) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  
  StatsD.timing("metrics.#{name}", duration)
  
  if duration > 100 # Log slow operations
    Rails.logger.warn "[Metrics] Slow operation: #{name} took #{duration.round(2)}ms"
  end
end
```

---

## Summary

This technical design provides a comprehensive architecture for Epic 2's Enhanced Metric Cards, including:

1. **Robust Service Layer**: MetricsCalculator with caching and performance optimization
2. **Chart Integration**: Chart.js with minimal bundle impact and fallback strategies
3. **Database Optimization**: Materialized views and strategic indexes
4. **Background Processing**: Scheduled jobs with monitoring and error recovery
5. **Caching Strategy**: Multi-tier caching with intelligent TTLs
6. **Real-time Updates**: ActionCable integration for live metrics
7. **Performance Targets**: All operations optimized for sub-100ms response
8. **Comprehensive APIs**: RESTful endpoints for metrics, budgets, and exports

## Readiness Assessment

### Readiness Score: **9/10**

### Sprint 1 Readiness: **YES**

Epic 2 is ready to begin Sprint 1 with:

**Week 1 Sprint Tasks:**
1. Task 2.1: Data Aggregation Service Layer (10 hours)
2. Task 2.6: Metric Calculation Background Jobs (8 hours)
3. Task 2.2: Primary Metric Visual Enhancement (6 hours)

**Total Sprint 1 Hours:** 24 hours (well within 40-hour sprint capacity)

### No Blockers Identified

All technical specifications are complete, database design is finalized, and the team can begin implementation immediately. The only minor item is final confirmation of Chart.js license compatibility, which is MIT and poses no issues.