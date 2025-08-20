# Migration Strategy: Dashboard Simplification

## Executive Summary

This document outlines the migration strategy for safely transitioning from the current complex dashboard to the simplified version. The approach prioritizes zero-downtime deployment, gradual user migration, and maintaining the integrity of the recently fixed sync functionality.

## Migration Phases

### Phase 0: Pre-Migration Preparation (Week 0)

#### 0.1 Baseline Metrics Collection
```ruby
# lib/tasks/dashboard_baseline.rake
namespace :dashboard do
  desc "Collect baseline metrics before simplification"
  task collect_baseline: :environment do
    puts "Collecting baseline metrics..."
    
    metrics = {
      timestamp: Time.current,
      performance: collect_performance_metrics,
      usage: collect_usage_patterns,
      errors: collect_error_rates,
      user_satisfaction: collect_satisfaction_scores
    }
    
    # Store baseline for comparison
    Redis.new(url: ENV['REDIS_URL']).set(
      'dashboard:baseline:metrics',
      metrics.to_json,
      ex: 90.days.to_i
    )
    
    # Upload to monitoring service
    Services::Infrastructure::MonitoringService.record_baseline(metrics)
    
    puts "Baseline collected: #{metrics.to_json}"
  end
  
  private
  
  def collect_performance_metrics
    {
      avg_render_time: calculate_avg_render_time,
      p95_render_time: calculate_p95_render_time,
      queries_per_load: count_average_queries,
      dom_elements: count_dom_elements,
      javascript_size: measure_js_bundle_size
    }
  end
end
```

#### 0.2 Feature Flag Setup
```ruby
# db/migrate/20240117_create_feature_flags_table.rb
class CreateFeatureFlagsTable < ActiveRecord::Migration[8.0]
  def change
    create_table :flipper_features do |t|
      t.string :key, null: false
      t.timestamps
    end
    
    create_table :flipper_gates do |t|
      t.string :feature_key, null: false
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    
    add_index :flipper_features, :key, unique: true
    add_index :flipper_gates, [:feature_key, :key], unique: true
    
    # Create dashboard simplification flags
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO flipper_features (key, created_at, updated_at)
          VALUES 
            ('dashboard.remove_duplicate_sync', NOW(), NOW()),
            ('dashboard.simplify_metrics', NOW(), NOW()),
            ('dashboard.consolidate_merchants', NOW(), NOW()),
            ('dashboard.remove_bank_breakdown', NOW(), NOW()),
            ('dashboard.reduce_chart_complexity', NOW(), NOW());
        SQL
      end
    end
  end
end
```

### Phase 1: Component Preparation (Days 1-3)

#### 1.1 Parallel Component Development
```ruby
# app/components/dashboard/sync_widget_component.rb
class Dashboard::SyncWidgetComponent < ViewComponent::Base
  def initialize(mode: :legacy, sync_data: {}, user: nil)
    @mode = mode
    @sync_data = sync_data
    @user = user
  end
  
  def render?
    return true if @mode == :simplified
    return true if @mode == :legacy && !simplified_enabled?
    false
  end
  
  private
  
  def simplified_enabled?
    Feature.enabled?(:remove_duplicate_sync, user: @user)
  end
  
  def call
    if @mode == :simplified
      render_simplified_widget
    else
      render_legacy_widget
    end
  end
  
  def render_simplified_widget
    content_tag :div, id: 'unified-sync-widget',
                class: 'bg-white rounded-xl shadow-sm p-6',
                data: stimulus_attributes do
      safe_join([
        render_header,
        render_progress_bar,
        render_account_controls,
        render_queue_stats
      ])
    end
  end
  
  def stimulus_attributes
    {
      controller: 'unified-sync',
      unified_sync_session_id_value: @sync_data[:session_id],
      unified_sync_active_value: @sync_data[:active],
      unified_sync_simplified_value: true
    }
  end
end
```

#### 1.2 Database Migration for Tracking
```ruby
# db/migrate/20240117_add_dashboard_preferences.rb
class AddDashboardPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboard_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :simplified_mode, default: false
      t.jsonb :feature_flags, default: {}
      t.datetime :migration_started_at
      t.datetime :migration_completed_at
      t.string :migration_status, default: 'pending'
      t.jsonb :performance_metrics, default: {}
      t.timestamps
    end
    
    add_index :dashboard_preferences, :migration_status
    add_index :dashboard_preferences, :simplified_mode
  end
end
```

### Phase 2: Gradual Rollout (Days 4-10)

#### 2.1 A/B Testing Configuration
```ruby
# app/services/dashboard_ab_test_service.rb
class DashboardAbTestService
  ROLLOUT_STAGES = [
    { percentage: 5, duration: 1.day, name: 'canary' },
    { percentage: 25, duration: 2.days, name: 'early_adopters' },
    { percentage: 50, duration: 3.days, name: 'half_rollout' },
    { percentage: 75, duration: 2.days, name: 'majority' },
    { percentage: 100, duration: nil, name: 'full_rollout' }
  ].freeze
  
  def self.assign_user_to_test(user)
    return if user.dashboard_preference&.migration_completed?
    
    current_stage = determine_current_stage
    
    if should_include_user?(user, current_stage)
      enable_simplified_dashboard(user, current_stage)
    end
  end
  
  private
  
  def self.determine_current_stage
    start_time = Rails.application.credentials.dashboard_rollout_start
    return ROLLOUT_STAGES.first unless start_time
    
    elapsed = Time.current - start_time
    
    ROLLOUT_STAGES.find do |stage|
      next unless stage[:duration]
      elapsed <= stage[:duration]
    end || ROLLOUT_STAGES.last
  end
  
  def self.should_include_user?(user, stage)
    # Use consistent hashing for user assignment
    hash = Digest::MD5.hexdigest("#{user.id}-dashboard-rollout")
    hash_value = hash.to_i(16) % 100
    
    hash_value < stage[:percentage]
  end
  
  def self.enable_simplified_dashboard(user, stage)
    ActiveRecord::Base.transaction do
      preference = user.dashboard_preference || user.create_dashboard_preference
      
      preference.update!(
        simplified_mode: true,
        migration_started_at: Time.current,
        migration_status: stage[:name],
        feature_flags: {
          remove_duplicate_sync: true,
          simplify_metrics: true,
          consolidate_merchants: true,
          remove_bank_breakdown: true,
          reduce_chart_complexity: true
        }
      )
      
      # Enable feature flags for this user
      Feature::DASHBOARD_SIMPLIFICATION.each_key do |feature|
        Flipper.enable(Feature::DASHBOARD_SIMPLIFICATION[feature], user)
      end
      
      # Track migration
      track_migration_event(user, stage)
    end
  end
  
  def self.track_migration_event(user, stage)
    Rails.logger.info "[Dashboard Migration] User #{user.id} moved to #{stage[:name]}"
    
    Services::Infrastructure::MonitoringService.track_event(
      'dashboard.migration.user_assigned',
      user_id: user.id,
      stage: stage[:name],
      percentage: stage[:percentage]
    )
  end
end
```

#### 2.2 Rollout Controller
```ruby
# app/controllers/concerns/dashboard_rollout.rb
module DashboardRollout
  extend ActiveSupport::Concern
  
  included do
    before_action :check_dashboard_assignment, if: :user_signed_in?
  end
  
  private
  
  def check_dashboard_assignment
    return if current_user.dashboard_preference&.migration_completed?
    
    DashboardAbTestService.assign_user_to_test(current_user)
    
    # Set instance variables for view
    @dashboard_mode = determine_dashboard_mode
    @show_migration_notice = should_show_migration_notice?
  end
  
  def determine_dashboard_mode
    if current_user.dashboard_preference&.simplified_mode?
      :simplified
    else
      :legacy
    end
  end
  
  def should_show_migration_notice?
    return false unless current_user.dashboard_preference
    
    preference = current_user.dashboard_preference
    preference.simplified_mode? && 
      preference.migration_started_at > 7.days.ago &&
      !preference.dismissed_notice?
  end
end
```

### Phase 3: Migration Execution (Days 11-14)

#### 3.1 Progressive Migration Jobs
```ruby
# app/jobs/dashboard_migration_job.rb
class DashboardMigrationJob < ApplicationJob
  queue_as :low_priority
  
  def perform(batch_size: 100)
    users_to_migrate = User.joins(:dashboard_preference)
                           .where(dashboard_preferences: { 
                             migration_status: 'pending' 
                           })
                           .limit(batch_size)
    
    users_to_migrate.find_each do |user|
      migrate_user_dashboard(user)
    rescue => e
      handle_migration_error(user, e)
    end
    
    # Schedule next batch if more users remain
    if User.joins(:dashboard_preference)
           .where(dashboard_preferences: { migration_status: 'pending' })
           .exists?
      self.class.perform_later(batch_size: batch_size)
    end
  end
  
  private
  
  def migrate_user_dashboard(user)
    ActiveRecord::Base.transaction do
      # Enable all simplification features
      enable_all_features(user)
      
      # Warm up caches with simplified data
      warm_simplified_caches(user)
      
      # Update preference
      user.dashboard_preference.update!(
        migration_status: 'completed',
        migration_completed_at: Time.current,
        performance_metrics: measure_performance(user)
      )
      
      # Send notification
      DashboardMailer.migration_complete(user).deliver_later
    end
  end
  
  def enable_all_features(user)
    Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature_key|
      Flipper.enable(feature_key, user)
    end
  end
  
  def warm_simplified_caches(user)
    DashboardOptimizer.new(user, 
      simplified_metrics: true,
      consolidated_merchants: true
    ).optimized_data
  end
  
  def measure_performance(user)
    {
      render_time: measure_render_time(user),
      query_count: count_queries(user),
      cache_hit_rate: calculate_cache_hit_rate(user)
    }
  end
  
  def handle_migration_error(user, error)
    Rails.logger.error "[Migration Error] User #{user.id}: #{error.message}"
    
    user.dashboard_preference.update!(
      migration_status: 'failed',
      performance_metrics: { error: error.message }
    )
    
    Sentry.capture_exception(error, user: { id: user.id })
  end
end
```

#### 3.2 Asset Pipeline Updates
```javascript
// app/javascript/dashboard/migration_manager.js
export class MigrationManager {
  constructor() {
    this.mode = document.querySelector('meta[name="dashboard-mode"]')?.content || 'legacy'
    this.features = this.parseFeatures()
  }
  
  parseFeatures() {
    const featuresJson = document.querySelector('meta[name="dashboard-features"]')?.content
    return featuresJson ? JSON.parse(featuresJson) : {}
  }
  
  async loadComponents() {
    if (this.mode === 'simplified') {
      await this.loadSimplifiedComponents()
    } else {
      await this.loadLegacyComponents()
    }
  }
  
  async loadSimplifiedComponents() {
    // Lazy load only simplified components
    const modules = [
      import('../controllers/unified_sync_controller'),
      import('../controllers/simplified_metrics_controller'),
      import('../controllers/consolidated_expenses_controller')
    ]
    
    await Promise.all(modules)
    
    // Remove legacy event listeners
    this.cleanupLegacyHandlers()
  }
  
  async loadLegacyComponents() {
    // Load full component set for legacy mode
    const modules = [
      import('../controllers/sync_widget_controller'),
      import('../controllers/animated_metric_controller'),
      import('../controllers/chart_controller'),
      import('../controllers/queue_monitor_controller')
    ]
    
    await Promise.all(modules)
  }
  
  cleanupLegacyHandlers() {
    // Remove legacy WebSocket subscriptions
    const legacySubscriptions = window.cable?.subscriptions?.subscriptions || []
    legacySubscriptions.forEach(sub => {
      if (sub.identifier.includes('LegacyChannel')) {
        sub.unsubscribe()
      }
    })
    
    // Clear legacy intervals
    ['syncInterval', 'metricsInterval', 'queueInterval'].forEach(intervalName => {
      if (window[intervalName]) {
        clearInterval(window[intervalName])
        delete window[intervalName]
      }
    })
  }
  
  trackPerformance() {
    // Send performance metrics
    const metrics = {
      mode: this.mode,
      domReady: performance.timing.domContentLoadedEventEnd - performance.timing.navigationStart,
      resourceCount: performance.getEntriesByType('resource').length,
      renderTime: performance.timing.loadEventEnd - performance.timing.navigationStart
    }
    
    fetch('/api/dashboard/metrics', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify(metrics)
    })
  }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
  const migrationManager = new MigrationManager()
  migrationManager.loadComponents()
  migrationManager.trackPerformance()
})
```

### Phase 4: Validation & Monitoring (Days 15-17)

#### 4.1 Health Check System
```ruby
# app/services/dashboard_health_checker.rb
class DashboardHealthChecker
  THRESHOLDS = {
    error_rate: 0.01,      # 1% error rate threshold
    render_time: 1500,     # 1.5 seconds
    cache_hit_rate: 0.7,   # 70% cache hits
    user_satisfaction: 0.8  # 80% satisfaction
  }.freeze
  
  def self.check_health(mode: :all)
    results = {
      timestamp: Time.current,
      checks: {}
    }
    
    if mode == :all || mode == :simplified
      results[:checks][:simplified] = check_simplified_dashboard
    end
    
    if mode == :all || mode == :legacy
      results[:checks][:legacy] = check_legacy_dashboard
    end
    
    results[:healthy] = all_checks_passing?(results[:checks])
    results
  end
  
  private
  
  def self.check_simplified_dashboard
    users_with_simplified = User.joins(:dashboard_preference)
                                .where(dashboard_preferences: { 
                                  simplified_mode: true 
                                })
    
    {
      user_count: users_with_simplified.count,
      error_rate: calculate_error_rate(:simplified),
      avg_render_time: calculate_avg_render_time(:simplified),
      cache_hit_rate: calculate_cache_hit_rate(:simplified),
      satisfaction_score: calculate_satisfaction(:simplified),
      passed: simplified_checks_pass?
    }
  end
  
  def self.simplified_checks_pass?
    metrics = {
      error_rate: calculate_error_rate(:simplified),
      render_time: calculate_avg_render_time(:simplified),
      cache_hit_rate: calculate_cache_hit_rate(:simplified)
    }
    
    metrics[:error_rate] < THRESHOLDS[:error_rate] &&
      metrics[:render_time] < THRESHOLDS[:render_time] &&
      metrics[:cache_hit_rate] > THRESHOLDS[:cache_hit_rate]
  end
  
  def self.calculate_error_rate(mode)
    Redis.new(url: ENV['REDIS_URL']).get("dashboard:#{mode}:error_rate").to_f
  end
  
  def self.calculate_avg_render_time(mode)
    Redis.new(url: ENV['REDIS_URL']).get("dashboard:#{mode}:avg_render_time").to_f
  end
  
  def self.calculate_cache_hit_rate(mode)
    Redis.new(url: ENV['REDIS_URL']).get("dashboard:#{mode}:cache_hit_rate").to_f
  end
end
```

#### 4.2 Automated Rollback Triggers
```ruby
# app/services/auto_rollback_service.rb
class AutoRollbackService
  ROLLBACK_TRIGGERS = {
    error_spike: { threshold: 0.05, window: 5.minutes },
    performance_degradation: { threshold: 2.0, window: 10.minutes },
    user_complaints: { threshold: 10, window: 1.hour }
  }.freeze
  
  def self.monitor_and_rollback
    return unless should_monitor?
    
    ROLLBACK_TRIGGERS.each do |trigger, config|
      if trigger_exceeded?(trigger, config)
        execute_rollback(trigger)
        break
      end
    end
  end
  
  private
  
  def self.should_monitor?
    # Only monitor during active rollout
    rollout_active = Redis.new(url: ENV['REDIS_URL']).get('dashboard:rollout:active')
    rollout_active == 'true'
  end
  
  def self.trigger_exceeded?(trigger, config)
    case trigger
    when :error_spike
      check_error_spike(config)
    when :performance_degradation
      check_performance_degradation(config)
    when :user_complaints
      check_user_complaints(config)
    end
  end
  
  def self.execute_rollback(trigger)
    Rails.logger.error "[AUTO ROLLBACK] Triggered by: #{trigger}"
    
    ActiveRecord::Base.transaction do
      # Disable all features immediately
      Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature|
        Flipper.disable(feature)
      end
      
      # Reset all user preferences
      DashboardPreference.update_all(
        simplified_mode: false,
        migration_status: 'rolled_back'
      )
      
      # Clear all caches
      Rails.cache.clear
      
      # Notify team
      notify_rollback(trigger)
    end
  end
  
  def self.notify_rollback(trigger)
    DashboardMailer.emergency_rollback(
      trigger: trigger,
      timestamp: Time.current,
      affected_users: DashboardPreference.where(simplified_mode: true).count
    ).deliver_now
    
    # Send to monitoring service
    Services::Infrastructure::MonitoringService.alert(
      severity: 'critical',
      message: "Dashboard auto-rollback triggered by #{trigger}"
    )
  end
end
```

### Phase 5: Cleanup & Optimization (Days 18-21)

#### 5.1 Legacy Code Removal
```ruby
# lib/tasks/dashboard_cleanup.rake
namespace :dashboard do
  desc "Remove legacy dashboard code after successful migration"
  task cleanup_legacy: :environment do
    abort "Migration not complete" unless migration_complete?
    
    puts "Starting legacy code cleanup..."
    
    # Remove legacy view partials
    legacy_partials = [
      'app/views/expenses/_legacy_sync_section.html.erb',
      'app/views/sync_sessions/_queue_visualization.html.erb',
      'app/views/expenses/_bank_breakdown.html.erb',
      'app/views/expenses/_top_merchants.html.erb'
    ]
    
    legacy_partials.each do |file|
      if File.exist?(Rails.root.join(file))
        FileUtils.rm(Rails.root.join(file))
        puts "Removed: #{file}"
      end
    end
    
    # Remove legacy Stimulus controllers
    legacy_controllers = [
      'app/javascript/controllers/sync_widget_controller.js',
      'app/javascript/controllers/queue_monitor_controller.js',
      'app/javascript/controllers/bank_breakdown_controller.js'
    ]
    
    legacy_controllers.each do |file|
      if File.exist?(Rails.root.join(file))
        FileUtils.rm(Rails.root.join(file))
        puts "Removed: #{file}"
      end
    end
    
    # Archive legacy service methods
    archive_legacy_services
    
    puts "Legacy cleanup complete!"
  end
  
  private
  
  def migration_complete?
    # Check if 95% of active users are migrated
    total_users = User.active.count
    migrated_users = User.joins(:dashboard_preference)
                         .where(dashboard_preferences: { 
                           migration_status: 'completed' 
                         })
                         .count
    
    (migrated_users.to_f / total_users) > 0.95
  end
  
  def archive_legacy_services
    # Move legacy code to archive directory
    FileUtils.mkdir_p(Rails.root.join('archive/dashboard_legacy'))
    
    # Archive service methods
    legacy_services = Dir.glob(Rails.root.join('app/services/**/*_legacy.rb'))
    legacy_services.each do |file|
      FileUtils.mv(file, Rails.root.join('archive/dashboard_legacy'))
    end
  end
end
```

#### 5.2 Performance Optimization
```ruby
# app/jobs/dashboard_optimization_job.rb
class DashboardOptimizationJob < ApplicationJob
  queue_as :low_priority
  
  def perform
    optimize_database_indexes
    optimize_cache_configuration
    optimize_asset_delivery
    generate_optimization_report
  end
  
  private
  
  def optimize_database_indexes
    # Analyze query patterns and add missing indexes
    ActiveRecord::Base.connection.execute(<<-SQL)
      -- Add partial indexes for common queries
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_dashboard_simplified
      ON expenses(user_id, date, amount)
      WHERE deleted_at IS NULL;
      
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sync_sessions_recent
      ON sync_sessions(user_id, created_at)
      WHERE created_at > NOW() - INTERVAL '7 days';
    SQL
  end
  
  def optimize_cache_configuration
    # Update cache TTLs based on usage patterns
    cache_config = {
      'dashboard:metrics' => 5.minutes,
      'dashboard:expenses' => 1.minute,
      'dashboard:sync_status' => 30.seconds
    }
    
    cache_config.each do |key_pattern, ttl|
      Rails.cache.write("config:cache_ttl:#{key_pattern}", ttl)
    end
  end
  
  def optimize_asset_delivery
    # Precompile simplified dashboard assets
    Rails.application.assets.precompile += %w[
      dashboard/simplified.js
      dashboard/simplified.css
    ]
    
    # Enable HTTP/2 push for critical assets
    Rails.application.config.action_dispatch.early_hints = true
  end
  
  def generate_optimization_report
    report = {
      timestamp: Time.current,
      optimizations: {
        indexes_added: 2,
        cache_configs_updated: 3,
        assets_optimized: true,
        bundle_size_reduction: '35%'
      },
      performance_impact: measure_performance_impact
    }
    
    Rails.logger.info "[Optimization Complete] #{report.to_json}"
  end
end
```

## Testing Strategy for Migration

### 1. Pre-Migration Testing

```ruby
# spec/services/dashboard_migration_spec.rb
require 'rails_helper'

RSpec.describe 'Dashboard Migration', type: :integration do
  describe 'pre-migration validation' do
    let(:users) { create_list(:user, 10) }
    
    before do
      users.each do |user|
        create_list(:expense, 50, user: user)
        create(:sync_session, user: user)
      end
    end
    
    it 'validates data integrity before migration' do
      validator = DashboardMigrationValidator.new
      
      expect(validator.validate_all).to be_truthy
      expect(validator.errors).to be_empty
    end
    
    it 'creates baseline metrics' do
      DashboardBaselineCollector.collect!
      
      baseline = Redis.new(url: ENV['REDIS_URL']).get('dashboard:baseline:metrics')
      expect(baseline).to be_present
      
      metrics = JSON.parse(baseline)
      expect(metrics).to include('performance', 'usage', 'errors')
    end
  end
  
  describe 'gradual rollout' do
    let(:users) { create_list(:user, 100) }
    
    it 'assigns users according to percentage' do
      # Set 25% rollout
      DashboardAbTestService.stub(:determine_current_stage).and_return(
        { percentage: 25, duration: 2.days, name: 'early_adopters' }
      )
      
      users.each { |user| DashboardAbTestService.assign_user_to_test(user) }
      
      migrated_count = DashboardPreference.where(simplified_mode: true).count
      expect(migrated_count).to be_between(20, 30) # Allow for some variance
    end
  end
end
```

### 2. Migration Testing

```ruby
# spec/jobs/dashboard_migration_job_spec.rb
require 'rails_helper'

RSpec.describe DashboardMigrationJob, type: :job do
  let(:users) { create_list(:user, 5) }
  
  before do
    users.each do |user|
      user.create_dashboard_preference(migration_status: 'pending')
    end
  end
  
  it 'migrates users in batches' do
    expect {
      described_class.perform_now(batch_size: 2)
    }.to change {
      DashboardPreference.where(migration_status: 'completed').count
    }.by(2)
  end
  
  it 'handles migration errors gracefully' do
    allow_any_instance_of(DashboardOptimizer).to receive(:optimized_data)
      .and_raise(StandardError, 'Test error')
    
    expect {
      described_class.perform_now(batch_size: 1)
    }.not_to raise_error
    
    failed = DashboardPreference.find_by(migration_status: 'failed')
    expect(failed).to be_present
    expect(failed.performance_metrics['error']).to include('Test error')
  end
  
  it 'warms up caches for migrated users' do
    expect(Rails.cache).to receive(:fetch).at_least(:once)
    
    described_class.perform_now(batch_size: 1)
  end
end
```

### 3. Rollback Testing

```ruby
# spec/services/auto_rollback_service_spec.rb
require 'rails_helper'

RSpec.describe AutoRollbackService do
  before do
    Redis.new(url: ENV['REDIS_URL']).set('dashboard:rollout:active', 'true')
  end
  
  describe 'automatic rollback triggers' do
    it 'rolls back on error spike' do
      # Simulate error spike
      Redis.new(url: ENV['REDIS_URL']).set('dashboard:simplified:error_rate', '0.06')
      
      expect {
        described_class.monitor_and_rollback
      }.to change {
        Flipper.enabled?('dashboard.remove_duplicate_sync')
      }.from(true).to(false)
    end
    
    it 'rolls back on performance degradation' do
      # Simulate slow performance
      Redis.new(url: ENV['REDIS_URL']).set('dashboard:simplified:avg_render_time', '3000')
      
      expect {
        described_class.monitor_and_rollback
      }.to change {
        DashboardPreference.where(simplified_mode: false).count
      }
    end
  end
  
  describe 'manual rollback' do
    it 'successfully rolls back all features' do
      # Enable features
      Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature|
        Flipper.enable(feature)
      end
      
      # Execute rollback
      DashboardRollbackService.perform(feature: :all)
      
      # Verify all features disabled
      Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature|
        expect(Flipper.enabled?(feature)).to be_falsey
      end
    end
  end
end
```

## Monitoring Dashboard

### Metrics to Track

```yaml
# config/dashboard_metrics.yml
metrics:
  performance:
    - name: render_time
      threshold: 1500ms
      alert: true
    - name: time_to_interactive
      threshold: 2000ms
      alert: true
    - name: queries_per_request
      threshold: 15
      alert: false
      
  reliability:
    - name: error_rate
      threshold: 0.01
      alert: true
    - name: availability
      threshold: 0.999
      alert: true
      
  user_experience:
    - name: bounce_rate
      threshold: 0.3
      alert: false
    - name: session_duration
      threshold: 120s
      alert: false
    - name: actions_per_session
      threshold: 5
      alert: false
      
  business:
    - name: sync_completion_rate
      threshold: 0.95
      alert: true
    - name: expense_creation_rate
      threshold: 10/day
      alert: false
```

### Monitoring Implementation

```ruby
# app/services/dashboard_metrics_collector.rb
class DashboardMetricsCollector
  def self.collect_and_report
    metrics = {
      performance: collect_performance_metrics,
      reliability: collect_reliability_metrics,
      user_experience: collect_ux_metrics,
      business: collect_business_metrics
    }
    
    # Store in time-series database
    store_metrics(metrics)
    
    # Check thresholds and alert if needed
    check_thresholds_and_alert(metrics)
    
    metrics
  end
  
  private
  
  def self.collect_performance_metrics
    {
      render_time: calculate_average_render_time,
      time_to_interactive: calculate_tti,
      queries_per_request: count_average_queries,
      cache_hit_rate: calculate_cache_hit_rate
    }
  end
  
  def self.check_thresholds_and_alert(metrics)
    config = YAML.load_file(Rails.root.join('config/dashboard_metrics.yml'))
    
    config['metrics'].each do |category, category_metrics|
      category_metrics.each do |metric_config|
        metric_value = metrics.dig(category.to_sym, metric_config['name'].to_sym)
        
        if metric_config['alert'] && exceeds_threshold?(metric_value, metric_config['threshold'])
          send_alert(category, metric_config['name'], metric_value, metric_config['threshold'])
        end
      end
    end
  end
  
  def self.send_alert(category, metric_name, value, threshold)
    Services::Infrastructure::MonitoringService.alert(
      severity: 'warning',
      category: category,
      metric: metric_name,
      value: value,
      threshold: threshold,
      message: "Dashboard metric #{metric_name} exceeded threshold: #{value} > #{threshold}"
    )
  end
end
```

## Success Criteria

### Migration Success Metrics

1. **Performance Improvements**
   - Page load time reduced by 40%
   - Database queries reduced by 50%
   - JavaScript bundle size reduced by 35%

2. **User Experience**
   - 60% reduction in cognitive load (measured via user testing)
   - 80% user satisfaction with simplified interface
   - Zero critical bugs during migration

3. **Technical Metrics**
   - 100% of active users successfully migrated
   - Zero data loss during migration
   - Rollback capability maintained throughout

4. **Business Metrics**
   - No decrease in sync usage
   - Maintained or improved expense tracking frequency
   - Reduced support tickets related to dashboard confusion

## Conclusion

This migration strategy ensures a safe, gradual transition to the simplified dashboard while maintaining system stability and the ability to rollback at any point. The phased approach with comprehensive testing and monitoring minimizes risk while maximizing the chances of successful adoption.