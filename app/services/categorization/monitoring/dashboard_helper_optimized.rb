# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Optimized helper module for rendering monitoring dashboards and metrics
    module DashboardHelperOptimized
      class << self
        # Cache metrics for 10 seconds to avoid hammering the database
        METRICS_CACHE_TTL = 10.seconds

        # Generate dashboard metrics summary with caching
        def metrics_summary
          Rails.cache.fetch("dashboard:metrics_summary", expires_in: METRICS_CACHE_TTL) do
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
              categorization: categorization_metrics_optimized,
              patterns: pattern_metrics_optimized,
              cache: cache_metrics,
              performance: performance_metrics,
              learning: learning_metrics_optimized,
              system: system_metrics_safe
            }
          end
        end

        # Optimized categorization metrics with single query
        def categorization_metrics_optimized
          recent_window = 1.hour.ago

          # Single query using SELECT with conditional aggregation
          result = Expense.pluck(
            Arel.sql("COUNT(*) as total_count"),
            Arel.sql("COUNT(category_id) as categorized_count"),
            Arel.sql("COUNT(CASE WHEN updated_at >= '#{recent_window.to_formatted_s(:db)}' THEN 1 END) as recent_total"),
            Arel.sql("COUNT(CASE WHEN updated_at >= '#{recent_window.to_formatted_s(:db)}' AND category_id IS NOT NULL THEN 1 END) as recent_categorized")
          ).first

          total, categorized, recent_total, recent_categorized = result

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
        rescue => e
          Rails.logger.error "Failed to fetch categorization metrics: #{e.message}"
          fallback_categorization_metrics
        end

        # Optimized pattern metrics with fewer queries
        def pattern_metrics_optimized
          window_24h = 24.hours.ago

          # Batch load all counts in a single query
          result = CategorizationPattern.pluck(
            Arel.sql("COUNT(*) as total_count"),
            Arel.sql("COUNT(CASE WHEN active = true THEN 1 END) as active_count"),
            Arel.sql("COUNT(CASE WHEN confidence_weight >= 3.0 THEN 1 END) as high_confidence_count"),
            Arel.sql("COUNT(CASE WHEN created_at >= '#{window_24h.to_formatted_s(:db)}' THEN 1 END) as created_24h"),
            Arel.sql("COUNT(CASE WHEN updated_at >= '#{window_24h.to_formatted_s(:db)}' AND updated_at != created_at THEN 1 END) as updated_24h")
          ).first

          total, active, high_confidence, recent_created, recent_updated = result

          # Get type distribution separately (still needs GROUP BY)
          by_type = Rails.cache.fetch("dashboard:patterns_by_type", expires_in: 1.minute) do
            CategorizationPattern.group(:pattern_type).count
          end

          {
            total: total,
            active: active,
            inactive: total - active,
            high_confidence: high_confidence,
            by_type: by_type,
            recent_activity: {
              created_24h: recent_created,
              updated_24h: recent_updated,
              learning_rate: (recent_created + recent_updated).to_f / 24
            }
          }
        rescue => e
          Rails.logger.error "Failed to fetch pattern metrics: #{e.message}"
          fallback_pattern_metrics
        end

        # Optimized learning metrics
        def learning_metrics_optimized
          window = 24.hours.ago

          # Combine queries where possible
          result = CategorizationPattern
            .where(updated_at: window..)
            .pluck(
              Arel.sql("COUNT(CASE WHEN created_at >= '#{window.to_formatted_s(:db)}' THEN 1 END) as created_count"),
              Arel.sql("COUNT(CASE WHEN updated_at != created_at THEN 1 END) as updated_count"),
              Arel.sql("COUNT(CASE WHEN confidence_weight >= 3.0 THEN 1 END) as improved_count")
            ).first

          patterns_created, patterns_updated, confidence_improvements = result

          {
            patterns_created_24h: patterns_created,
            patterns_updated_24h: patterns_updated,
            confidence_improvements: confidence_improvements,
            learning_velocity: (patterns_created + patterns_updated).to_f / 24
          }
        rescue => e
          Rails.logger.error "Failed to fetch learning metrics: #{e.message}"
          {
            patterns_created_24h: 0,
            patterns_updated_24h: 0,
            confidence_improvements: 0,
            learning_velocity: 0.0
          }
        end

        # Thread-safe system metrics
        def system_metrics_safe
          {
            database: database_metrics_safe,
            memory: memory_metrics,
            background_jobs: background_job_metrics_safe
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
            throughput: calculate_throughput_optimized
          }
        rescue => e
          {
            error: "Unable to fetch performance metrics: #{e.message}"
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

        def calculate_throughput_optimized
          # Cache throughput calculation for 30 seconds
          Rails.cache.fetch("dashboard:throughput", expires_in: 30.seconds) do
            window = 1.hour.ago
            expenses_processed = Expense.where(updated_at: window..).count

            {
              expenses_per_hour: expenses_processed,
              expenses_per_minute: (expenses_processed.to_f / 60).round(2)
            }
          end
        end

        # Thread-safe database metrics
        def database_metrics_safe
          pool = ActiveRecord::Base.connection_pool

          # Use synchronize to ensure thread safety
          pool.synchronize do
            connections = pool.connections.dup
            {
              pool_size: pool.size,
              connections: connections.size,
              busy: connections.count(&:in_use?),
              idle: connections.count { |c| !c.in_use? }
            }
          end
        rescue => e
          Rails.logger.error "Failed to fetch database metrics: #{e.message}"
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

        # Thread-safe background job metrics
        def background_job_metrics_safe
          if defined?(SolidQueue)
            # Use pluck for better performance
            enqueued = SolidQueue::Job.where(finished_at: nil).count
            processing = SolidQueue::ClaimedExecution.count
            failed = SolidQueue::FailedExecution.where(created_at: 24.hours.ago..).count

            {
              provider: "SolidQueue",
              enqueued: enqueued,
              processing: processing,
              failed_24h: failed
            }
          else
            { provider: "none" }
          end
        rescue => e
          Rails.logger.error "Failed to fetch job metrics: #{e.message}"
          {}
        end

        # Fallback methods for error cases
        def fallback_categorization_metrics
          {
            total_expenses: 0,
            categorized: 0,
            uncategorized: 0,
            success_rate: 0,
            recent: {
              total: 0,
              categorized: 0,
              success_rate: 0
            }
          }
        end

        def fallback_pattern_metrics
          {
            total: 0,
            active: 0,
            inactive: 0,
            high_confidence: 0,
            by_type: {},
            recent_activity: {
              created_24h: 0,
              updated_24h: 0,
              learning_rate: 0.0
            }
          }
        end
      end
    end
  end
end
