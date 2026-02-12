# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Helper module for rendering monitoring dashboards and metrics
    module DashboardHelper
      class << self
        # Generate dashboard metrics summary
        def metrics_summary
          health_check = HealthCheck.new
          health_result = health_check.check_all
          metrics_snapshot = MetricsCollector.instance.snapshot

          {
            health: {
              status: health_result[:status],
              healthy: health_result[:healthy],
              ready: health_result[:ready],
              uptime_seconds: health_result[:uptime_seconds]
            },
            categorization: categorization_metrics,
            patterns: pattern_metrics,
            cache: cache_metrics,
            performance: performance_metrics,
            learning: learning_metrics,
            system: system_metrics
          }
        end

        # Get categorization success metrics
        def categorization_metrics
          total = Expense.count
          categorized = Expense.where.not(category_id: nil).count
          recent_window = 1.hour.ago

          recent_total = Expense.where(updated_at: recent_window..).count
          recent_categorized = Expense.where(updated_at: recent_window..)
                                      .where.not(category_id: nil).count

          {
            total_expenses: total,
            categorized: categorized,
            uncategorized: total - categorized,
            success_rate: total.positive? ? (categorized.to_f / total * 100).round(2) : 0,
            recent: {
              total: recent_total,
              categorized: recent_categorized,
              success_rate: recent_total.positive? ? (recent_categorized.to_f / recent_total * 100).round(2) : 0
            }
          }
        end

        # Get pattern statistics
        def pattern_metrics
          total = CategorizationPattern.count
          active = CategorizationPattern.active.count
          high_confidence = CategorizationPattern.where("confidence_weight >= ?", 0.8).count

          by_type = CategorizationPattern.group(:pattern_type).count

          recent_24h = CategorizationPattern.where(created_at: 24.hours.ago..).count
          updated_24h = CategorizationPattern.where(updated_at: 24.hours.ago..)
                                             .where("updated_at != created_at").count

          {
            total: total,
            active: active,
            inactive: total - active,
            high_confidence: high_confidence,
            by_type: by_type,
            recent_activity: {
              created_24h: recent_24h,
              updated_24h: updated_24h,
              learning_rate: (recent_24h + updated_24h).to_f / 24
            }
          }
        end

        # Get cache performance metrics
        def cache_metrics
          cache = PatternCache.instance
          stats = cache.stats

          hit_rate = if stats[:hits] + stats[:misses] > 0
                      (stats[:hits].to_f / (stats[:hits] + stats[:misses]) * 100).round(2)
          else
                      0
          end

          {
            entries: stats[:entries],
            memory_mb: (stats[:memory_bytes].to_f / 1024 / 1024).round(2),
            hits: stats[:hits],
            misses: stats[:misses],
            hit_rate: hit_rate,
            evictions: stats[:evictions]
          }
        rescue => e
          {
            error: "Unable to fetch cache metrics: #{e.message}"
          }
        end

        # Get performance metrics
        def performance_metrics
          tracker = PerformanceTracker.instance
          metrics = tracker.metrics

          {
            operations: metrics[:operations],
            averages: {
              categorization: metrics[:operations]["categorize_expense"]&.dig(:avg_duration).to_f.round(2),
              learning: metrics[:operations]["learn_pattern"]&.dig(:avg_duration).to_f.round(2),
              cache_lookup: metrics[:operations]["cache_lookup"]&.dig(:avg_duration).to_f.round(2)
            },
            slow_operations: count_slow_operations(metrics),
            throughput: calculate_throughput
          }
        rescue => e
          {
            error: "Unable to fetch performance metrics: #{e.message}"
          }
        end

        # Get learning activity metrics
        def learning_metrics
          window = 24.hours.ago

          patterns_created = CategorizationPattern.where(created_at: window..).count
          patterns_updated = CategorizationPattern.where(updated_at: window..)
                                                  .where("updated_at != created_at").count

          confidence_improvements = CategorizationPattern.where(updated_at: window..)
                                                         .where("success_rate > 0.8")
                                                         .count rescue 0

          {
            patterns_created_24h: patterns_created,
            patterns_updated_24h: patterns_updated,
            confidence_improvements: confidence_improvements,
            learning_velocity: (patterns_created + patterns_updated).to_f / 24
          }
        end

        # Get system resource metrics
        def system_metrics
          {
            database: database_metrics,
            memory: memory_metrics,
            background_jobs: background_job_metrics
          }
        end

        private

        def count_slow_operations(metrics)
          return 0 unless metrics[:operations]

          metrics[:operations].values.sum do |op_metrics|
            next 0 unless op_metrics[:durations]
            op_metrics[:durations].count { |d| d > 100 } # Count operations > 100ms
          end
        end

        def calculate_throughput
          window = 1.hour.ago
          expenses_processed = Expense.where(updated_at: window..).count

          {
            expenses_per_hour: expenses_processed,
            expenses_per_minute: (expenses_processed.to_f / 60).round(2)
          }
        end

        def database_metrics
          pool = ActiveRecord::Base.connection_pool

          {
            pool_size: pool.size,
            connections: pool.connections.size,
            busy: pool.connections.count(&:in_use?),
            idle: pool.connections.count { |c| !c.in_use? }
          }
        rescue
          {}
        end

        def memory_metrics
          if defined?(GetProcessMem)
            mem = GetProcessMem.new
            {
              rss_mb: (mem.rss.to_f / 1024 / 1024).round(2),
              percent: mem.percent.round(2)
            }
          else
            {}
          end
        rescue
          {}
        end

        def background_job_metrics
          if defined?(SolidQueue)
            {
              provider: "SolidQueue",
              enqueued: SolidQueue::Job.where(finished_at: nil).count,
              processing: SolidQueue::ClaimedExecution.count,
              failed_24h: SolidQueue::FailedExecution.where(created_at: 24.hours.ago..).count
            }
          else
            { provider: "none" }
          end
        rescue
          {}
        end
      end
    end
  end
end
