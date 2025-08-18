# Technical Design Document: Dashboard Simplification

## Executive Summary

This document outlines the technical architecture and implementation strategy for Epic 4: Dashboard Simplification. The primary goal is to reduce cognitive load by 60% through strategic removal of redundant components, consolidation of related information, and optimization of the rendering pipeline while maintaining all critical sync functionality recently fixed.

## Architecture Overview

### Current State Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Dashboard View                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │Email Sync    │  │Sync Widget   │  │Queue Visual  │     │
│  │Section       │  │(Partial)     │  │(Partial)     │     │
│  │(Lines 13-177)│  │(Line 181)    │  │(Line 186)    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │Primary       │  │Secondary     │  │Bank          │     │
│  │Metric Card   │  │Metric Cards  │  │Breakdown     │     │
│  │(7 data pts)  │  │(4-5 pts each)│  │Section       │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │Top Merchants │  │Recent        │  │Complex       │     │
│  │Section       │  │Expenses      │  │Charts        │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Target State Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Simplified Dashboard                        │
├─────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐     │
│  │         Unified Sync Widget (Enhanced)              │     │
│  │         - All sync controls                         │     │
│  │         - Real-time progress                        │     │
│  │         - Queue visualization integrated            │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────────────────────┐        │
│  │Primary       │  │Secondary Metrics (Simplified)  │        │
│  │Metric        │  │- Amount only                   │        │
│  │(2 data pts)  │  │- Trend icon                    │        │
│  └──────────────┘  └──────────────────────────────┘        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │     Consolidated Recent Expenses w/ Merchants       │     │
│  │     - Unified view with merchant data inline        │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │     Simplified Chart (Single, Responsive)           │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Design Patterns & Decisions

### 1. Component Consolidation Pattern

**Decision**: Use Rails ViewComponents for consolidated widgets to ensure reusability and testability.

```ruby
# app/components/sync_widget_component.rb
class SyncWidgetComponent < ViewComponent::Base
  include Turbo::StreamsHelper
  
  def initialize(sync_session: nil, email_accounts: [], show_queue: true)
    @sync_session = sync_session
    @email_accounts = email_accounts
    @show_queue = show_queue
  end
  
  private
  
  def sync_active?
    @sync_session&.active?
  end
  
  def queue_stats
    return {} unless @show_queue
    Services::Infrastructure::MonitoringService.queue_statistics
  end
end
```

### 2. Progressive Enhancement Pattern

**Decision**: Implement progressive disclosure using Stimulus controllers with lazy-loaded content.

```javascript
// app/javascript/controllers/progressive_disclosure_controller.js
export default class extends Controller {
  static targets = ["trigger", "content", "spinner"]
  static values = { 
    url: String, 
    loaded: Boolean,
    cacheTimeout: { type: Number, default: 30000 }
  }
  
  connect() {
    this.cache = new Map()
    this.setupIntersectionObserver()
  }
  
  async loadDetails(event) {
    if (this.loadedValue) return
    
    const cached = this.cache.get(this.urlValue)
    if (cached && Date.now() - cached.timestamp < this.cacheTimeoutValue) {
      this.renderContent(cached.data)
      return
    }
    
    this.showSpinner()
    
    try {
      const response = await fetch(this.urlValue, {
        headers: { 
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.text()
        this.cache.set(this.urlValue, { data, timestamp: Date.now() })
        this.renderContent(data)
        this.loadedValue = true
      }
    } catch (error) {
      console.error('Failed to load details:', error)
      this.showError()
    } finally {
      this.hideSpinner()
    }
  }
}
```

### 3. Feature Flag Architecture

**Decision**: Implement granular feature flags using Rails credentials and Flipper gem.

```ruby
# config/initializers/flipper.rb
Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end

# app/models/feature.rb
class Feature
  DASHBOARD_SIMPLIFICATION = {
    remove_duplicate_sync: 'dashboard.remove_duplicate_sync',
    simplify_metrics: 'dashboard.simplify_metrics',
    consolidate_merchants: 'dashboard.consolidate_merchants',
    remove_bank_breakdown: 'dashboard.remove_bank_breakdown',
    reduce_chart_complexity: 'dashboard.reduce_chart_complexity'
  }.freeze
  
  class << self
    def enabled?(feature_key, user: nil)
      return false unless DASHBOARD_SIMPLIFICATION.key?(feature_key)
      
      flipper_key = DASHBOARD_SIMPLIFICATION[feature_key]
      
      if user
        Flipper.enabled?(flipper_key, user)
      else
        Flipper.enabled?(flipper_key)
      end
    end
    
    def enable_percentage(feature_key, percentage)
      flipper_key = DASHBOARD_SIMPLIFICATION[feature_key]
      Flipper.enable_percentage_of_actors(flipper_key, percentage)
    end
  end
end
```

## Component Removal Strategies

### 1. Safe Removal with Fallback

```ruby
# app/controllers/concerns/dashboard_simplification.rb
module DashboardSimplification
  extend ActiveSupport::Concern
  
  included do
    before_action :set_simplification_flags
  end
  
  private
  
  def set_simplification_flags
    @simplification_enabled = {
      duplicate_sync: Feature.enabled?(:remove_duplicate_sync, user: current_user),
      simplified_metrics: Feature.enabled?(:simplify_metrics, user: current_user),
      consolidated_merchants: Feature.enabled?(:consolidate_merchants, user: current_user),
      removed_bank_breakdown: Feature.enabled?(:remove_bank_breakdown, user: current_user),
      simplified_charts: Feature.enabled?(:reduce_chart_complexity, user: current_user)
    }
  end
  
  def load_dashboard_data
    if @simplification_enabled[:duplicate_sync]
      load_unified_sync_data
    else
      load_legacy_sync_data
    end
    
    if @simplification_enabled[:simplified_metrics]
      load_simplified_metrics
    else
      load_full_metrics
    end
  end
  
  def load_unified_sync_data
    @sync_data = Services::Email::SyncService.unified_dashboard_data(
      include_queue: true,
      include_history: false # Lazy load on demand
    )
  end
  
  def load_simplified_metrics
    @metrics = Services::MetricsCalculator.simplified_metrics(
      user: current_user,
      fields: [:total_amount, :trend, :period_label]
    )
  end
end
```

### 2. Gradual DOM Cleanup

```erb
<!-- app/views/expenses/dashboard.html.erb -->
<% unless @simplification_enabled[:duplicate_sync] %>
  <!-- Legacy sync section - to be removed -->
  <%= turbo_frame_tag "sync_status_section" do %>
    <%= render 'expenses/legacy_sync_section' %>
  <% end %>
<% end %>

<!-- Unified widget - always shown but enhanced when simplification enabled -->
<div class="mb-6">
  <%= render SyncWidgetComponent.new(
    sync_session: @sync_data[:active_session],
    email_accounts: @sync_data[:accounts],
    show_queue: @simplification_enabled[:duplicate_sync]
  ) %>
</div>

<% unless @simplification_enabled[:duplicate_sync] %>
  <!-- Queue visualization - removed when unified -->
  <%= render 'sync_sessions/queue_visualization' %>
<% end %>
```

## Database & Performance Implications

### 1. Query Optimization Strategy

```ruby
# app/services/dashboard_optimizer.rb
class DashboardOptimizer
  include Rails.application.routes.url_helpers
  
  def initialize(user, simplification_flags = {})
    @user = user
    @simplification = simplification_flags
  end
  
  def optimized_data
    Rails.cache.fetch(cache_key, expires_in: 30.seconds) do
      {
        sync: load_sync_data,
        metrics: load_metrics,
        expenses: load_recent_expenses
      }
    end
  end
  
  private
  
  def load_sync_data
    return {} unless sync_needed?
    
    # Single optimized query instead of multiple
    SyncSession
      .includes(:sync_session_accounts => :email_account)
      .where(user: @user)
      .active_or_recent(1)
      .select(:id, :status, :progress_percentage, :processed_emails, 
              :total_emails, :detected_expenses, :created_at)
      .first
  end
  
  def load_metrics
    if @simplification[:simplified_metrics]
      # Reduced query - only essential fields
      Expense
        .where(user: @user)
        .group_by_period(:month, :date)
        .sum(:amount)
    else
      # Legacy full metrics query
      load_full_metrics_data
    end
  end
  
  def load_recent_expenses
    base_query = @user.expenses
      .includes(:category, :email_account)
      .order(date: :desc)
      .limit(10)
    
    if @simplification[:consolidated_merchants]
      # Include merchant aggregation in single query
      base_query
        .select('expenses.*, COUNT(*) OVER (PARTITION BY merchant) as merchant_frequency')
        .select('SUM(amount) OVER (PARTITION BY merchant) as merchant_total')
    else
      base_query
    end
  end
  
  def cache_key
    [
      'dashboard',
      @user.id,
      @user.expenses.maximum(:updated_at),
      @simplification.values.join('-')
    ].join('/')
  end
end
```

### 2. Database Indexes for Performance

```ruby
# db/migrate/20240117_add_dashboard_optimization_indexes.rb
class AddDashboardOptimizationIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def change
    # Composite index for metrics queries
    add_index :expenses, [:user_id, :date, :amount], 
              algorithm: :concurrently,
              name: 'idx_expenses_dashboard_metrics'
    
    # Index for merchant grouping
    add_index :expenses, [:user_id, :merchant, :date], 
              algorithm: :concurrently,
              where: "merchant IS NOT NULL",
              name: 'idx_expenses_merchant_analysis'
    
    # Partial index for active sync sessions
    add_index :sync_sessions, [:user_id, :status, :created_at],
              algorithm: :concurrently,
              where: "status IN ('pending', 'processing')",
              name: 'idx_sync_sessions_active'
    
    # Index for sync session accounts join
    add_index :sync_session_accounts, 
              [:sync_session_id, :email_account_id, :status],
              algorithm: :concurrently,
              name: 'idx_sync_session_accounts_status'
  end
end
```

## Caching & Optimization Strategies

### 1. Multi-Layer Caching

```ruby
# app/models/concerns/dashboard_cacheable.rb
module DashboardCacheable
  extend ActiveSupport::Concern
  
  included do
    # Redis for real-time data
    def redis_cache
      @redis_cache ||= Redis.new(url: ENV['REDIS_URL'])
    end
    
    # Rails cache for computed values
    def cached_metrics(period = :month)
      Rails.cache.fetch(metrics_cache_key(period), expires_in: 5.minutes) do
        calculate_metrics(period)
      end
    end
    
    # Fragment caching for views
    def fragment_cache_key
      [
        self.class.name.underscore,
        id,
        updated_at.to_i,
        Feature.enabled?(:simplify_metrics) ? 'simplified' : 'full'
      ].join('-')
    end
  end
  
  class_methods do
    def warm_cache_for_user(user_id)
      DashboardCacheWarmupJob.perform_later(user_id)
    end
  end
end
```

### 2. Solid Cache Integration

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store, {
  expires_in: 1.hour,
  size_threshold: 1.kilobyte,
  namespace: 'dashboard',
  error_handler: ->(method:, exception:, **) {
    Rails.logger.error "[SolidCache] #{method} failed: #{exception.message}"
    Sentry.capture_exception(exception)
  }
}

# app/services/infrastructure/cache_manager.rb
module Services
  module Infrastructure
    class CacheManager
      CACHE_STRATEGIES = {
        sync_widget: { expires_in: 30.seconds, race_condition_ttl: 10.seconds },
        metrics: { expires_in: 5.minutes, race_condition_ttl: 30.seconds },
        recent_expenses: { expires_in: 1.minute, race_condition_ttl: 15.seconds },
        charts: { expires_in: 10.minutes, race_condition_ttl: 1.minute }
      }.freeze
      
      def self.fetch(key, strategy: :default, &block)
        options = CACHE_STRATEGIES[strategy] || { expires_in: 5.minutes }
        
        Rails.cache.fetch(key, **options) do
          ActiveSupport::Notifications.instrument('cache.miss', key: key)
          yield
        end
      end
      
      def self.delete_pattern(pattern)
        Rails.cache.delete_matched(pattern)
      end
    end
  end
end
```

## Rails-Specific Implementation Approaches

### 1. Turbo Stream Updates for Simplified Components

```ruby
# app/controllers/sync_sessions_controller.rb
class SyncSessionsController < ApplicationController
  include DashboardSimplification
  
  def create
    @sync_session = Services::Email::SyncService.start_sync(
      user: current_user,
      email_accounts: params[:account_ids]
    )
    
    respond_to do |format|
      format.turbo_stream do
        if @simplification_enabled[:duplicate_sync]
          render turbo_stream: [
            turbo_stream.replace('unified-sync-widget',
              partial: 'sync_sessions/unified_widget',
              locals: { sync_session: @sync_session }
            ),
            turbo_stream.append('notifications',
              partial: 'shared/toast',
              locals: { message: 'Sync started', type: 'success' }
            )
          ]
        else
          # Legacy multi-stream update
          render_legacy_sync_streams
        end
      end
      
      format.html { redirect_to dashboard_path }
    end
  end
  
  private
  
  def broadcast_simplified_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard_sync_updates",
      target: "unified-sync-widget",
      partial: "sync_sessions/unified_widget",
      locals: { 
        sync_session: @sync_session,
        show_queue: true 
      }
    )
  end
end
```

### 2. Stimulus Controller Consolidation

```javascript
// app/javascript/controllers/unified_sync_controller.js
import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = [
    "progressBar", 
    "progressText", 
    "syncButton",
    "accountList",
    "queueStats"
  ]
  
  static values = {
    sessionId: Number,
    active: Boolean,
    simplified: Boolean,
    pollInterval: { type: Number, default: 2000 }
  }
  
  connect() {
    this.setupSubscription()
    this.setupPolling()
    this.initializeState()
  }
  
  setupSubscription() {
    if (!this.sessionIdValue) return
    
    this.subscription = cable.subscribeTo({
      channel: "SyncProgressChannel",
      session_id: this.sessionIdValue
    }, {
      received: (data) => this.handleProgress(data)
    })
  }
  
  handleProgress(data) {
    if (this.simplifiedValue) {
      // Simplified update - minimal DOM manipulation
      this.updateSimplifiedProgress(data)
    } else {
      // Legacy detailed update
      this.updateDetailedProgress(data)
    }
  }
  
  updateSimplifiedProgress(data) {
    // Single RAF for all DOM updates
    requestAnimationFrame(() => {
      if (this.hasProgressBarTarget) {
        this.progressBarTarget.style.width = `${data.percentage}%`
      }
      
      if (this.hasProgressTextTarget) {
        this.progressTextTarget.textContent = `${data.processed}/${data.total}`
      }
      
      if (data.status === 'completed') {
        this.handleCompletion()
      }
    })
  }
  
  async syncAll(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    button.disabled = true
    
    try {
      const response = await fetch('/sync_sessions', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: new FormData(button.closest('form'))
      })
      
      if (!response.ok) throw new Error('Sync failed')
      
      // Turbo will handle the stream response
      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      console.error('Sync error:', error)
      this.showError('Failed to start sync')
    } finally {
      button.disabled = false
    }
  }
}
```

### 3. ActiveJob Integration for Background Cleanup

```ruby
# app/jobs/dashboard_simplification_job.rb
class DashboardSimplificationJob < ApplicationJob
  queue_as :low_priority
  
  def perform(user_id, feature_key)
    user = User.find(user_id)
    
    case feature_key
    when :remove_duplicate_sync
      cleanup_duplicate_sync_data(user)
    when :simplify_metrics
      precompute_simplified_metrics(user)
    when :consolidate_merchants
      aggregate_merchant_data(user)
    end
    
    # Clear relevant caches
    Services::Infrastructure::CacheManager.delete_pattern("dashboard/#{user_id}/*")
    
    # Log the change
    Rails.logger.info "[Simplification] Applied #{feature_key} for user #{user_id}"
  end
  
  private
  
  def cleanup_duplicate_sync_data(user)
    # Archive old sync patterns
    user.sync_patterns.where(deprecated: true).destroy_all
    
    # Clean up orphaned sync records
    user.sync_sessions
        .where('created_at < ?', 30.days.ago)
        .where.not(status: 'completed')
        .destroy_all
  end
  
  def precompute_simplified_metrics(user)
    # Warm cache with simplified metrics
    [:day, :week, :month, :year].each do |period|
      Services::MetricsCalculator.simplified_metrics(
        user: user,
        period: period,
        cache: true
      )
    end
  end
end
```

## Security Considerations

### 1. Feature Flag Security

```ruby
# app/controllers/concerns/feature_authorization.rb
module FeatureAuthorization
  extend ActiveSupport::Concern
  
  included do
    before_action :authorize_feature_access
  end
  
  private
  
  def authorize_feature_access
    return unless params[:force_feature].present?
    
    # Only allow feature forcing in development/staging with admin role
    if Rails.env.production? || !current_user&.admin?
      Rails.logger.warn "[Security] Unauthorized feature flag attempt by #{current_user&.id}"
      head :forbidden
    end
  end
  
  def validate_simplification_params
    # Sanitize any user-provided parameters that affect simplification
    if params[:dashboard_config].present?
      params.require(:dashboard_config).permit(
        :show_simplified_metrics,
        :enable_progressive_disclosure,
        :consolidate_merchants
      )
    end
  end
end
```

### 2. CSRF Protection for AJAX Updates

```javascript
// app/javascript/utils/csrf_helper.js
export class CSRFHelper {
  static getToken() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) {
      throw new Error('CSRF token not found')
    }
    return token
  }
  
  static addToHeaders(headers = {}) {
    return {
      ...headers,
      'X-CSRF-Token': this.getToken(),
      'X-Requested-With': 'XMLHttpRequest'
    }
  }
  
  static addToFormData(formData) {
    formData.append('authenticity_token', this.getToken())
    return formData
  }
}
```

## Testing Strategies for Rails App

### 1. RSpec System Tests for Simplified Dashboard

```ruby
# spec/system/dashboard_simplification_spec.rb
require 'rails_helper'

RSpec.describe 'Dashboard Simplification', type: :system do
  let(:user) { create(:user) }
  
  before do
    login_as(user)
    create_list(:expense, 20, user: user)
    create(:sync_session, :active, user: user)
  end
  
  context 'with simplification enabled' do
    before do
      Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature|
        Flipper.enable(feature, user)
      end
    end
    
    it 'displays only unified sync widget' do
      visit dashboard_path
      
      expect(page).to have_css('#unified-sync-widget', count: 1)
      expect(page).not_to have_css('#legacy-sync-section')
      expect(page).not_to have_css('#queue-visualization')
    end
    
    it 'shows simplified metrics' do
      visit dashboard_path
      
      within '#primary-metric-card' do
        expect(page).to have_css('[data-metric="amount"]')
        expect(page).to have_css('[data-metric="trend"]')
        expect(page).not_to have_content('transactions')
        expect(page).not_to have_content('average')
      end
    end
    
    it 'consolidates merchant data in expenses' do
      visit dashboard_path
      
      within '#recent-expenses' do
        expect(page).to have_css('[data-merchant-info]')
      end
      
      expect(page).not_to have_css('#top-merchants-section')
    end
  end
  
  context 'performance improvements' do
    it 'loads dashboard within performance budget' do
      start_time = Time.current
      visit dashboard_path
      load_time = Time.current - start_time
      
      expect(load_time).to be < 1.5.seconds
      expect(page).to have_css('[data-dashboard-loaded="true"]')
    end
  end
end
```

### 2. Request Specs for Feature Flags

```ruby
# spec/requests/dashboard_feature_flags_spec.rb
require 'rails_helper'

RSpec.describe 'Dashboard Feature Flags', type: :request do
  let(:user) { create(:user) }
  
  before { sign_in user }
  
  describe 'GET /dashboard' do
    context 'with progressive feature rollout' do
      it 'respects user-specific feature flags' do
        Flipper.enable(:dashboard_remove_duplicate_sync, user)
        
        get dashboard_path
        
        expect(response.body).not_to include('id="sync_status_section"')
        expect(response.body).to include('id="unified-sync-widget"')
      end
      
      it 'falls back to legacy when features disabled' do
        Flipper.disable(:dashboard_remove_duplicate_sync)
        
        get dashboard_path
        
        expect(response.body).to include('id="sync_status_section"')
      end
    end
  end
  
  describe 'Turbo Stream updates' do
    let(:sync_session) { create(:sync_session, user: user) }
    
    it 'sends simplified updates when enabled' do
      Flipper.enable(:dashboard_remove_duplicate_sync, user)
      
      post sync_session_progress_path(sync_session), 
           params: { progress: 50 },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      
      expect(response.body).to include('turbo-stream action="replace"')
      expect(response.body).to include('unified-sync-widget')
      expect(response.body).not_to include('legacy-sync-section')
    end
  end
end
```

### 3. Performance Testing

```ruby
# spec/performance/dashboard_optimization_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe 'Dashboard Performance', type: :performance do
  let(:user) { create(:user) }
  
  before do
    # Create realistic data set
    create_list(:expense, 1000, user: user)
    create_list(:category, 20)
    create_list(:email_account, 3, user: user)
  end
  
  describe 'query optimization' do
    it 'reduces N+1 queries' do
      control = ActiveRecord::QueryRecorder.new do
        DashboardOptimizer.new(user, simplified_metrics: false).optimized_data
      end
      
      optimized = ActiveRecord::QueryRecorder.new do
        DashboardOptimizer.new(user, simplified_metrics: true).optimized_data
      end
      
      expect(optimized.count).to be < (control.count * 0.6)
    end
    
    it 'meets performance budget' do
      result = Benchmark.measure do
        100.times do
          DashboardOptimizer.new(user, simplified_metrics: true).optimized_data
        end
      end
      
      expect(result.real).to be < 5.0 # 50ms per request average
    end
  end
  
  describe 'caching effectiveness' do
    it 'serves cached responses efficiently' do
      optimizer = DashboardOptimizer.new(user, simplified_metrics: true)
      
      # Prime cache
      optimizer.optimized_data
      
      cached_time = Benchmark.realtime do
        10.times { optimizer.optimized_data }
      end
      
      expect(cached_time).to be < 0.1 # 10ms per cached request
    end
  end
end
```

## Rollback Procedures

### 1. Feature Flag Rollback

```ruby
# lib/tasks/dashboard_rollback.rake
namespace :dashboard do
  desc "Rollback dashboard simplification features"
  task rollback: :environment do
    puts "Rolling back dashboard simplification..."
    
    # Disable all simplification features
    Feature::DASHBOARD_SIMPLIFICATION.values.each do |feature|
      Flipper.disable(feature)
      puts "Disabled: #{feature}"
    end
    
    # Clear all caches
    Rails.cache.clear
    Redis.new(url: ENV['REDIS_URL']).flushdb
    
    # Notify monitoring
    Services::Infrastructure::MonitoringService.notify(
      event: 'dashboard_rollback',
      severity: 'warning',
      details: { reason: ENV['ROLLBACK_REASON'] }
    )
    
    puts "Rollback complete. Legacy dashboard restored."
  end
  
  desc "Partial rollback of specific feature"
  task :rollback_feature, [:feature_key] => :environment do |_, args|
    feature = args[:feature_key].to_sym
    
    if Feature::DASHBOARD_SIMPLIFICATION.key?(feature)
      Flipper.disable(Feature::DASHBOARD_SIMPLIFICATION[feature])
      
      # Clear related caches
      Services::Infrastructure::CacheManager.delete_pattern("dashboard/*#{feature}*")
      
      puts "Rolled back: #{feature}"
    else
      puts "Unknown feature: #{feature}"
    end
  end
end
```

### 2. Database Rollback Strategy

```ruby
# app/services/dashboard_rollback_service.rb
class DashboardRollbackService
  def self.perform(user: nil, feature: nil)
    ActiveRecord::Base.transaction do
      if feature == :all || feature.nil?
        rollback_all_features(user)
      else
        rollback_specific_feature(user, feature)
      end
      
      # Log rollback
      create_rollback_audit(user, feature)
    end
  rescue => e
    Rails.logger.error "[Rollback Failed] #{e.message}"
    Sentry.capture_exception(e)
    raise
  end
  
  private
  
  def self.rollback_all_features(user)
    scope = user ? user.dashboard_preferences : DashboardPreference
    
    scope.update_all(
      show_duplicate_sync: true,
      show_full_metrics: true,
      show_separate_merchants: true,
      show_bank_breakdown: true,
      show_complex_charts: true,
      updated_at: Time.current
    )
  end
  
  def self.create_rollback_audit(user, feature)
    AuditLog.create!(
      action: 'dashboard_rollback',
      user: user,
      details: {
        feature: feature,
        timestamp: Time.current,
        reason: Thread.current[:rollback_reason]
      }
    )
  end
end
```

## Monitoring & Observability

### 1. Custom Metrics for Simplification

```ruby
# app/services/infrastructure/simplification_monitor.rb
module Services
  module Infrastructure
    class SimplificationMonitor
      METRICS = {
        render_time: 'dashboard.render_time',
        component_count: 'dashboard.component_count',
        query_count: 'dashboard.query_count',
        cache_hit_rate: 'dashboard.cache_hit_rate',
        feature_usage: 'dashboard.feature_usage'
      }.freeze
      
      def self.track_render(user, duration, simplified: false)
        StatsD.measure(METRICS[:render_time], duration, tags: {
          simplified: simplified,
          user_segment: user_segment(user)
        })
      end
      
      def self.track_feature_usage(feature, enabled)
        StatsD.increment(METRICS[:feature_usage], tags: {
          feature: feature,
          enabled: enabled
        })
      end
      
      def self.track_performance_impact
        {
          before_simplification: measure_baseline_performance,
          after_simplification: measure_simplified_performance,
          improvement_percentage: calculate_improvement
        }
      end
      
      private
      
      def self.measure_baseline_performance
        # Measure with all features disabled
        Benchmark.realtime do
          # Render dashboard with legacy components
        end
      end
      
      def self.measure_simplified_performance  
        # Measure with all features enabled
        Benchmark.realtime do
          # Render simplified dashboard
        end
      end
    end
  end
end
```

## Error Recovery & Resilience

### 1. Graceful Degradation

```ruby
# app/controllers/concerns/dashboard_resilience.rb
module DashboardResilience
  extend ActiveSupport::Concern
  
  included do
    rescue_from StandardError, with: :handle_dashboard_error
  end
  
  private
  
  def handle_dashboard_error(exception)
    Rails.logger.error "[Dashboard Error] #{exception.message}"
    Sentry.capture_exception(exception)
    
    # Fallback to minimal dashboard
    @fallback_mode = true
    @minimal_data = load_minimal_dashboard_data
    
    respond_to do |format|
      format.html { render 'expenses/minimal_dashboard', status: :ok }
      format.turbo_stream { render_fallback_streams }
    end
  end
  
  def load_minimal_dashboard_data
    {
      total_expenses: current_user.expenses.sum(:amount),
      recent_expenses: current_user.expenses.recent(5),
      sync_status: 'unavailable'
    }
  end
  
  def render_fallback_streams
    turbo_stream.replace('dashboard-content',
      partial: 'expenses/minimal_dashboard_content',
      locals: { data: @minimal_data }
    )
  end
end
```

## Conclusion

This technical design provides a comprehensive approach to dashboard simplification while:
- Maintaining system stability through feature flags and gradual rollout
- Preserving critical sync functionality that was recently fixed
- Optimizing performance through caching and query optimization
- Ensuring security through proper authorization and CSRF protection
- Providing robust testing and rollback procedures
- Implementing monitoring for tracking success metrics

The architecture emphasizes Rails 8 best practices, leverages Solid Queue for background processing, and maintains compatibility with the existing Turbo/Stimulus frontend infrastructure.