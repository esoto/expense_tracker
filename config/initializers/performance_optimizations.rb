# frozen_string_literal: true

# Performance optimizations for the expense tracker application

# Note: Rails.cache is configured in config/environments/*.rb (Solid Cache in production).
# Do NOT set config.cache_store here — multiple initializers competing for it causes
# non-deterministic behavior (see PER-282).

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

# NOTE: a prior `RefreshDashboardMetricsJob` block lived here and invoked
# the SolidQueue RecurringJob AR API to schedule a 5-minute cron. That API
# does NOT exist — the RecurringJob constant is an ActiveJob::Base subclass,
# not an AR model, and has no AR persistence methods. The block was dead
# code: it raised NoMethodError at boot AND there is no `dashboard_metrics`
# materialized view in the schema for it to refresh. Removed 2026-04-17
# so that `assets:precompile` (which boots production env + runs
# after_initialize callbacks) stops failing. If a periodic refresh of a
# materialized view is needed in the future, add the job class under
# `app/jobs/` and wire it up via `config/recurring.yml` — the standard
# Solid Queue 1.x way.

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

# Preload frequently accessed data.
#
# Guarded with `ActiveRecord::Base.connected?` so the block is a no-op
# during `assets:precompile` (Docker build-time, no DB) and during rake
# tasks that intentionally boot without a DB. The `rescue` captures
# transient DB errors (unreachable DB during rolling deploys) so a cold
# cache never blocks boot.
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next unless defined?(Category) && defined?(CategorizationPattern)
  next unless ActiveRecord::Base.connection_pool.active_connection? ||
              (ActiveRecord::Base.connection_db_config.present? && ActiveRecord::Base.connection rescue nil)

  Rails.cache.fetch("categories:all", expires_in: 1.hour) { Category.all.to_a }
  Rails.cache.fetch("patterns:active", expires_in: 10.minutes) { CategorizationPattern.active.to_a }
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
  Rails.logger.warn "Cache warm-up skipped (DB not reachable): #{e.class}: #{e.message}"
end

Rails.logger.info "Performance optimizations loaded successfully"
