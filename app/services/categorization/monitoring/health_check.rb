# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Service for checking the health status of the categorization system
    class HealthCheck
      THRESHOLDS = {
        database_response_ms: 100,
        redis_response_ms: 10,
        min_patterns: 10,
        min_success_rate: 0.5,
        max_error_rate: 0.1,
        cache_min_hit_rate: 0.3
      }.freeze

      attr_reader :checks, :errors

      def initialize
        @checks = {}
        @errors = []
        @start_time = Time.current
      end

      # Perform all health checks
      def check_all
        @checks = {}
        @errors = []

        check_database
        check_redis
        check_pattern_cache
        check_service_metrics
        check_data_quality
        check_dependencies

        build_result
      end

      # Check database performance
      def check_database
        start = Time.current

        # Test database connectivity and performance
        result = ActiveRecord::Base.connection.execute("SELECT 1").first
        duration_ms = (Time.current - start) * 1000

        @checks[:database] = {
          status: duration_ms < THRESHOLDS[:database_response_ms] ? :healthy : :degraded,
          response_time_ms: duration_ms.round(2),
          threshold_ms: THRESHOLDS[:database_response_ms],
          connected: true
        }

        # Check pattern count
        pattern_count = CategorizationPattern.active.count
        @checks[:database][:pattern_count] = pattern_count

        if pattern_count < THRESHOLDS[:min_patterns]
          @checks[:database][:status] = :degraded
          @checks[:database][:warning] = "Low pattern count: #{pattern_count}"
        end
      rescue => e
        @checks[:database] = {
          status: :unhealthy,
          connected: false,
          error: e.message
        }
        @errors << "Database check failed: #{e.message}"
      end

      # Check Redis connectivity and performance
      def check_redis
        return unless redis_configured?

        start = Time.current

        # Test Redis connectivity
        redis_client.ping
        duration_ms = (Time.current - start) * 1000

        # Check memory usage
        info = redis_client.info("memory")
        memory_used = info["used_memory_human"] rescue "unknown"

        @checks[:redis] = {
          status: duration_ms < THRESHOLDS[:redis_response_ms] ? :healthy : :degraded,
          response_time_ms: duration_ms.round(2),
          threshold_ms: THRESHOLDS[:redis_response_ms],
          connected: true,
          memory_used: memory_used
        }

        check_redis_cache_stats
      rescue => e
        @checks[:redis] = {
          status: :unhealthy,
          connected: false,
          error: e.message
        }
        @errors << "Redis check failed: #{e.message}"
      end

      # Check pattern cache status
      def check_pattern_cache
        cache = Services::Categorization::PatternCache.instance

        stats = cache.stats
        hit_rate = calculate_hit_rate(stats[:hits], stats[:misses])

        @checks[:pattern_cache] = {
          status: determine_cache_status(stats, hit_rate),
          entries: stats[:entries],
          memory_bytes: stats[:memory_bytes],
          hit_rate: hit_rate.round(3),
          hits: stats[:hits],
          misses: stats[:misses],
          evictions: stats[:evictions]
        }

        if hit_rate < THRESHOLDS[:cache_min_hit_rate] && stats[:hits] > 100
          @checks[:pattern_cache][:warning] = "Low cache hit rate: #{(hit_rate * 100).round(1)}%"
        end
      rescue => e
        @checks[:pattern_cache] = {
          status: :unknown,
          error: e.message
        }
        @errors << "Pattern cache check failed: #{e.message}"
      end

      # Check overall service metrics
      def check_service_metrics
        # Get recent categorization statistics
        recent_window = 1.hour.ago
        total_attempts = Expense.where(updated_at: recent_window..).count
        successful = Expense.where(updated_at: recent_window..).where.not(category_id: nil).count

        success_rate = total_attempts.positive? ? successful.to_f / total_attempts : 0

        # Get learning activity
        recent_patterns = CategorizationPattern.where(created_at: 24.hours.ago..).count
        updated_patterns = CategorizationPattern.where(updated_at: 24.hours.ago..)
                                                .where("updated_at != created_at").count

        @checks[:service_metrics] = {
          status: determine_service_status(success_rate, total_attempts),
          total_patterns: CategorizationPattern.count,
          active_patterns: CategorizationPattern.active.count,
          recent_attempts: total_attempts,
          success_rate: success_rate.round(3),
          learning_activity: {
            new_patterns_24h: recent_patterns,
            updated_patterns_24h: updated_patterns
          }
        }

        if success_rate < THRESHOLDS[:min_success_rate] && total_attempts > 10
          @checks[:service_metrics][:warning] = "Low success rate: #{(success_rate * 100).round(1)}%"
        end
      rescue => e
        @checks[:service_metrics] = {
          status: :unknown,
          error: e.message
        }
        @errors << "Service metrics check failed: #{e.message}"
      end

      # Check data quality
      def check_data_quality
        quality_checker = DataQualityChecker.new
        audit_result = quality_checker.audit

        @checks[:data_quality] = {
          status: determine_data_quality_status(audit_result),
          quality_score: audit_result[:quality_score][:overall],
          quality_grade: audit_result[:quality_score][:grade],
          summary: audit_result[:summary],
          critical_issues: audit_result[:summary][:critical_issues],
          recommendations_count: audit_result[:summary][:total_recommendations]
        }

        if audit_result[:summary][:critical_issues] > 0
          @checks[:data_quality][:warning] = "#{audit_result[:summary][:critical_issues]} critical data quality issues found"
        end
      rescue => e
        @checks[:data_quality] = {
          status: :unknown,
          error: e.message
        }
        @errors << "Data quality check failed: #{e.message}"
      end

      # Check system dependencies
      def check_dependencies
        dependencies = {
          rails_cache: check_rails_cache,
          background_jobs: check_background_jobs,
          metrics_collector: check_metrics_collector
        }

        all_healthy = dependencies.values.all? { |d| d[:status] == :healthy }

        @checks[:dependencies] = {
          status: all_healthy ? :healthy : :degraded,
          services: dependencies
        }
      rescue => e
        @checks[:dependencies] = {
          status: :unknown,
          error: e.message
        }
        @errors << "Dependencies check failed: #{e.message}"
      end

      # Get overall health status
      def healthy?
        return false if @checks.empty?

        critical_checks = [ :database, :pattern_cache ]
        critical_healthy = critical_checks.all? do |check|
          @checks[check]&.fetch(:status, :unknown) != :unhealthy
        end

        critical_healthy && @errors.empty?
      end

      # Get status for readiness probe
      def ready?
        return false if @checks.empty?

        # System is ready if database and cache are available
        database_ready = @checks.dig(:database, :status) != :unhealthy
        cache_ready = @checks.dig(:pattern_cache, :status) != :unhealthy

        database_ready && cache_ready
      end

      # Get status for liveness probe
      def live?
        # System is live if it can respond to requests
        # Even if degraded, the system is still "live"
        true
      rescue
        false
      end

      # Build the complete health check result
      def build_result
        {
          status: overall_status,
          healthy: healthy?,
          ready: ready?,
          live: live?,
          timestamp: Time.current.iso8601,
          uptime_seconds: (Time.current - @start_time).round,
          checks: @checks,
          errors: @errors
        }
      end

      private

      def redis_configured?
        Rails.configuration.x.categorization&.dig(:cache, :redis_enabled) || false
      end

      def redis_client
        @redis_client ||= Redis.new(
          url: Rails.configuration.x.categorization&.dig(:cache, :redis_url) || "redis://localhost:6379/1"
        )
      end

      def check_redis_cache_stats
        return unless @checks[:redis][:connected]

        # Get cache statistics from Redis
        keys = redis_client.keys("categorization:*")

        @checks[:redis][:cache_keys] = keys.count
        @checks[:redis][:cache_patterns] = keys.count { |k| k.include?("pattern") }
      rescue => e
        @checks[:redis][:cache_stats_error] = e.message
      end

      def check_rails_cache
        start = Time.current
        test_key = "health_check_#{SecureRandom.hex(4)}"

        Rails.cache.write(test_key, "test", expires_in: 10.seconds)
        value = Rails.cache.read(test_key)
        Rails.cache.delete(test_key)

        duration_ms = (Time.current - start) * 1000

        {
          status: value == "test" ? :healthy : :unhealthy,
          response_time_ms: duration_ms.round(2),
          store: Rails.cache.class.name
        }
      rescue => e
        {
          status: :unhealthy,
          error: e.message
        }
      end

      def check_background_jobs
        # Check if Solid Queue is processing jobs
        if defined?(SolidQueue)
          job_count = SolidQueue::Job.where(created_at: 1.hour.ago..).count
          failed_count = SolidQueue::FailedExecution.where(created_at: 1.hour.ago..).count rescue 0

          {
            status: :healthy,
            provider: "SolidQueue",
            recent_jobs: job_count,
            recent_failures: failed_count
          }
        else
          {
            status: :unknown,
            provider: "none"
          }
        end
      rescue => e
        {
          status: :unhealthy,
          error: e.message
        }
      end

      def check_metrics_collector
        snapshot = MetricsCollector.instance.snapshot

        {
          status: snapshot[:enabled] ? :healthy : :disabled,
          enabled: snapshot[:enabled],
          connected: snapshot[:client_connected]
        }
      rescue => e
        {
          status: :unhealthy,
          error: e.message
        }
      end

      def calculate_hit_rate(hits, misses)
        total = hits + misses
        return 0.0 if total.zero?
        hits.to_f / total
      end

      def determine_cache_status(stats, hit_rate)
        return :unhealthy if stats[:entries].zero?
        return :degraded if hit_rate < THRESHOLDS[:cache_min_hit_rate]
        :healthy
      end

      def determine_service_status(success_rate, attempts)
        return :unknown if attempts.zero?
        return :unhealthy if success_rate < 0.3
        return :degraded if success_rate < THRESHOLDS[:min_success_rate]
        :healthy
      end

      def overall_status
        return :unknown if @checks.empty?

        # Check for unhealthy critical components
        critical_checks = [ :database, :pattern_cache ]
        critical_unhealthy = critical_checks.any? do |check|
          @checks[check]&.fetch(:status, :unknown) == :unhealthy
        end

        return :unhealthy if critical_unhealthy || @errors.present?

        # Check for degraded components
        degraded_checks = @checks.values.count { |check| check[:status] == :degraded }
        return :degraded if degraded_checks > 0

        :healthy
      end

      def determine_data_quality_status(audit_result)
        quality_score = audit_result[:quality_score][:overall]
        critical_issues = audit_result[:summary][:critical_issues]

        return :unhealthy if quality_score < 0.4 || critical_issues > 5
        return :degraded if quality_score < 0.7 || critical_issues > 0
        :healthy
      end
    end
  end
end
