# frozen_string_literal: true

module Api
  # Health check controller for monitoring and Kubernetes probes
  class HealthController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Comprehensive health check endpoint
    # GET /api/health
    def index
      health_check = Services::Categorization::Monitoring::HealthCheck.new
      result = health_check.check_all

      if health_check.healthy?
        render json: format_response(result), status: :ok
      else
        render json: format_response(result), status: :service_unavailable
      end
    end

    # Kubernetes readiness probe
    # GET /api/health/ready
    def ready
      health_check = Services::Categorization::Monitoring::HealthCheck.new
      health_check.check_all

      if health_check.ready?
        render json: {
          status: "ready",
          timestamp: Time.current.iso8601
        }, status: :ok
      else
        render json: {
          status: "not_ready",
          timestamp: Time.current.iso8601,
          checks: health_check.checks.select { |_, v| v[:status] == :unhealthy }
        }, status: :service_unavailable
      end
    end

    # Kubernetes liveness probe
    # GET /api/health/live
    def live
      health_check = Services::Categorization::Monitoring::HealthCheck.new

      if health_check.live?
        render json: {
          status: "live",
          timestamp: Time.current.iso8601
        }, status: :ok
      else
        render json: {
          status: "dead",
          timestamp: Time.current.iso8601
        }, status: :service_unavailable
      end
    end

    # Metrics endpoint for monitoring
    # GET /api/health/metrics
    def metrics
      metrics = collect_metrics

      render json: metrics, status: :ok
    rescue => e
      render json: {
        error: "Failed to collect metrics",
        message: e.message
      }, status: :internal_server_error
    end

    private

    def format_response(result)
      {
        status: result[:status],
        healthy: result[:healthy],
        timestamp: result[:timestamp],
        uptime_seconds: result[:uptime_seconds],
        checks: format_checks(result[:checks]),
        errors: result[:errors]
      }.compact
    end

    def format_checks(checks)
      checks.transform_values do |check|
        check.slice(:status, :response_time_ms, :connected, :error, :warning)
             .merge(details: check.except(:status, :response_time_ms, :connected, :error, :warning))
             .compact
      end
    end

    def collect_metrics
      # Collect current metrics snapshot
      {
        timestamp: Time.current.iso8601,
        categorization: {
          total_expenses: Expense.count,
          categorized_expenses: Expense.where.not(category_id: nil).count,
          uncategorized_expenses: Expense.where(category_id: nil).count,
          success_rate: calculate_success_rate
        },
        patterns: {
          total: CategorizationPattern.count,
          active: CategorizationPattern.active.count,
          high_confidence: CategorizationPattern.where("confidence_weight >= ?", 3.0).count,
          recently_updated: CategorizationPattern.where(updated_at: 24.hours.ago..).count
        },
        performance: {
          cache_stats: cache_metrics,
          recent_activity: recent_activity_metrics
        },
        system: {
          database_pool: database_pool_metrics,
          memory: memory_metrics
        }
      }
    end

    def calculate_success_rate
      total = Expense.count
      return 0 if total.zero?

      (Expense.where.not(category_id: nil).count.to_f / total * 100).round(2)
    end

    def cache_metrics
      cache = Services::Categorization::PatternCache.instance
      stats = cache.stats

      {
        entries: stats[:entries],
        hits: stats[:hits],
        misses: stats[:misses],
        hit_rate: (stats[:hits].to_f / (stats[:hits] + stats[:misses]).to_f rescue 0),
        memory_bytes: stats[:memory_bytes]
      }
    rescue
      { error: "Unable to fetch cache metrics" }
    end

    def recent_activity_metrics
      window = 1.hour.ago

      {
        expenses_processed: Expense.where(updated_at: window..).count,
        patterns_learned: CategorizationPattern.where(created_at: window..).count,
        patterns_updated: CategorizationPattern.where(updated_at: window..)
                                               .where("updated_at != created_at").count
      }
    end

    def database_pool_metrics
      pool = ActiveRecord::Base.connection_pool

      {
        size: pool.size,
        connections: pool.connections.size,
        busy: pool.connections.count(&:in_use?),
        idle: pool.connections.count { |c| !c.in_use? }
      }
    rescue
      { error: "Unable to fetch database pool metrics" }
    end

    def memory_metrics
      if defined?(GetProcessMem)
        mem = GetProcessMem.new
        {
          rss_mb: (mem.rss.to_f / 1024 / 1024).round(2),
          percent: mem.percent.round(2)
        }
      else
        { note: "Memory metrics not available (install get_process_mem gem)" }
      end
    rescue
      { error: "Unable to fetch memory metrics" }
    end
  end
end
