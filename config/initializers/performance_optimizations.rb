# frozen_string_literal: true

# Performance optimizations for the expense tracker application

# Configure Rails cache for dashboard metrics
Rails.application.configure do
  # Use memory store in development, Redis in production
  if Rails.env.production?
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
      expires_in: 1.minute,
      namespace: "expense_tracker_dashboard",
      pool_size: 10,
      pool_timeout: 5,
      compress: true,
      compress_threshold: 1.kilobyte
    }
  else
    config.cache_store = :memory_store, { size: 64.megabytes }
  end
end

# Configure ActiveRecord for better performance
ActiveRecord::Base.establish_connection(
  ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first.configuration_hash.merge(
    pool: ENV.fetch("RAILS_MAX_THREADS", 5).to_i * 2,
    checkout_timeout: 5,
    reaping_frequency: 10,
    prepared_statements: true,
    advisory_locks: true,
    lazy_transactions_enabled: true
  )
)

# Enable query cache for read-heavy operations
module DashboardQueryCache
  extend ActiveSupport::Concern

  included do
    around_action :enable_query_cache, if: :dashboard_action?
  end

  private

  def enable_query_cache(&block)
    ActiveRecord::Base.cache(&block)
  end

  def dashboard_action?
    controller_name.include?("dashboard") || action_name.include?("metrics")
  end
end

# Include in ApplicationController if needed
# ApplicationController.include(DashboardQueryCache) if defined?(ApplicationController)

# Configure connection pool monitoring
if Rails.env.production?
  ActiveSupport::Notifications.subscribe("!connection_pool.active_record") do |name, start, finish, id, payload|
    pool = payload[:connection_pool]
    available = pool.instance_variable_get(:@available)

    if available.instance_variable_get(:@queue).size > 0
      Rails.logger.warn "Connection pool pressure detected: #{available.instance_variable_get(:@queue).size} threads waiting"
    end

    if pool.stat[:busy] > pool.size * 0.8
      Rails.logger.warn "Connection pool near capacity: #{pool.stat[:busy]}/#{pool.size} connections in use"
    end
  end
end

# Configure automatic query optimization hints
module QueryOptimizer
  extend ActiveSupport::Concern

  class_methods do
    def optimized_count(*args)
      # Use approximate count for large tables
      if count > 10_000
        connection.execute("SELECT reltuples FROM pg_class WHERE relname = '#{table_name}'").first["reltuples"].to_i
      else
        count(*args)
      end
    rescue
      count(*args)
    end

    def with_query_cache(&block)
      ActiveRecord::Base.cache(&block)
    end
  end
end

# Include in ApplicationRecord if needed
# ApplicationRecord.include(QueryOptimizer) if defined?(ApplicationRecord)

# Configure statement timeout for dashboard queries
module StatementTimeout
  extend ActiveSupport::Concern

  included do
    default_scope -> { connection.execute("SET statement_timeout = '5s'") if Rails.env.production? }
  end
end

# Background job for refreshing materialized views
Rails.application.config.after_initialize do
  if defined?(SolidQueue) && defined?(ApplicationJob) && ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    class RefreshDashboardMetricsJob < ApplicationJob
      queue_as :low_priority

      def perform
        ActiveRecord::Base.connection.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_metrics")
        Rails.logger.info "Dashboard metrics materialized view refreshed"
      rescue => e
        Rails.logger.error "Failed to refresh dashboard metrics: #{e.message}"
      end
    end

    # Schedule the job to run every 5 minutes in production
    if Rails.env.production? && defined?(SolidQueue::RecurringJob)
      SolidQueue::RecurringJob.create(
        name: "refresh_dashboard_metrics",
        class_name: "RefreshDashboardMetricsJob",
        cron: "*/5 * * * *"
      )
    end
  end
end

# Memory optimization settings
if defined?(GetProcessMem)
  # Monitor memory usage and trigger GC if needed
  Thread.new do
    loop do
      sleep 60 # Check every minute

      mem = GetProcessMem.new
      if mem.mb > ENV.fetch("MAX_MEMORY_MB", 512).to_i
        GC.start(full_mark: true, immediate_sweep: true)
        Rails.logger.info "Triggered GC due to high memory usage: #{mem.mb}MB"
      end
    rescue => e
      Rails.logger.error "Memory monitor error: #{e.message}"
    end
  end
end

# Preload frequently accessed data
Rails.application.config.after_initialize do
  if Rails.env.production? && defined?(Category) && defined?(CategorizationPattern)
    # Warm up the cache with common queries
    Rails.cache.fetch("categories:all", expires_in: 1.hour) { Category.all.to_a }
    Rails.cache.fetch("patterns:active", expires_in: 10.minutes) { CategorizationPattern.active.to_a }
  end
end

Rails.logger.info "Performance optimizations loaded successfully"
