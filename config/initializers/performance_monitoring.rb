# frozen_string_literal: true

# Performance monitoring configuration
# Tracks and reports on cache performance, categorization speed, and system health

Rails.application.configure do
  # Only enable in development and production
  if Rails.env.development? || Rails.env.production?

    # Configure performance monitoring
    config.after_initialize do
      # Start monitoring thread for periodic health checks
      PerformanceMonitoring.start if defined?(Services::Infrastructure::MonitoringService)

      # Configure cache performance tracking
      PerformanceMonitoring.configure_cache if defined?(Categorization::PatternCache)

      # Set up performance alerts
      PerformanceMonitoring.configure_alerts if Rails.env.production?
    end
  end
end

# Performance monitoring module
module PerformanceMonitoring
  class << self
    attr_reader :monitoring_thread

    def start
      # Ensure we don't start multiple monitoring threads
      return if @monitoring_thread&.alive?

      # Run periodic health checks in background
      @monitoring_thread = Thread.new do
        Thread.current.name = "performance_monitoring"
        Thread.current.report_on_exception = true

        loop do
          begin
            # Use configuration for sleep duration
            sleep_duration = Services::Infrastructure::PerformanceConfig.monitoring_interval
            sleep sleep_duration

            # Collect metrics
            metrics = Services::Infrastructure::MonitoringService.cache_metrics

            # Log performance summary
            log_performance_summary(metrics)

            # Check for performance issues
            check_performance_issues(metrics)

          rescue StandardError => e
            Rails.logger.error "[PerformanceMonitoring] Error in monitoring thread: #{e.message}"
            Rails.logger.error e.backtrace.first(5).join("\n") if e.backtrace
            sleep 60 # Wait before retrying
          end
        end
      end

      Rails.logger.info "[PerformanceMonitoring] Performance monitoring started (thread: #{@monitoring_thread.object_id})"
    end

    def stop
      if @monitoring_thread&.alive?
        Rails.logger.info "[PerformanceMonitoring] Stopping monitoring thread..."
        @monitoring_thread.kill
        @monitoring_thread.join(5) # Wait up to 5 seconds for thread to finish
        @monitoring_thread = nil
        Rails.logger.info "[PerformanceMonitoring] Monitoring thread stopped"
      end
    end

    def configure_cache
      # Add instrumentation to pattern cache
      ActiveSupport::Notifications.subscribe("pattern_cache.lookup") do |name, start, finish, id, payload|
        duration_ms = (finish - start) * 1000

        # Record metric
        Services::Infrastructure::MonitoringService.record_metric(
          "pattern_cache.lookup_time",
          duration_ms,
          {
            cache_hit: payload[:cache_hit],
            pattern_type: payload[:pattern_type]
          }
        )

        # Log slow lookups
        if duration_ms > 5
          Rails.logger.warn "[PerformanceMonitoring] Slow pattern lookup: #{duration_ms.round(2)}ms for #{payload[:pattern]}"
        end
      end

      ActiveSupport::Notifications.subscribe("pattern_cache.warm") do |name, start, finish, id, payload|
        duration_seconds = finish - start

        Services::Infrastructure::MonitoringService.record_metric(
          "pattern_cache.warming_duration",
          duration_seconds,
          {
            patterns_warmed: payload[:patterns_count],
            success: payload[:success]
          }
        )

        Rails.logger.info "[PerformanceMonitoring] Cache warming completed in #{duration_seconds.round(2)}s"
      end

      Rails.logger.info "[PerformanceMonitoring] Cache monitoring configured"
    end

    def configure_alerts
      # Set up alerts for production environment
      ActiveSupport::Notifications.subscribe("performance.alert") do |name, start, finish, id, payload|
        alert_type = payload[:type]
        severity = payload[:severity]
        message = payload[:message]
        metrics = payload[:metrics]

        # Log alert
        case severity
        when :critical
          Rails.logger.error "[PERFORMANCE ALERT - CRITICAL] #{alert_type}: #{message}"
          Rails.logger.error "Metrics: #{metrics.inspect}"

          # Send to error tracking service
          if defined?(Services::Infrastructure::MonitoringService)
            Services::Infrastructure::MonitoringService.record_error(
              "performance_alert_critical",
              {
                type: alert_type,
                message: message,
                metrics: metrics
              }
            )
          end

        when :warning
          Rails.logger.warn "[PERFORMANCE ALERT - WARNING] #{alert_type}: #{message}"
          Rails.logger.warn "Metrics: #{metrics.inspect}"

        else
          Rails.logger.info "[PERFORMANCE ALERT] #{alert_type}: #{message}"
        end
      end

      Rails.logger.info "[PerformanceMonitoring] Performance alerts configured"
    end

    def log_performance_summary(metrics)
      return unless metrics[:pattern_cache]

      cache_metrics = metrics[:pattern_cache]
      health = metrics[:health]

      Rails.logger.info "[PerformanceMonitoring] Cache Performance Summary:"
      Rails.logger.info "  Hit Rate: #{cache_metrics[:hit_rate]}%"
      Rails.logger.info "  Memory Entries: #{cache_metrics[:memory_entries]}"
      Rails.logger.info "  Avg Lookup Time: #{cache_metrics[:average_lookup_time_ms]}ms"
      Rails.logger.info "  Health Status: #{health[:overall]}"

      if health[:recommendations].any?
        Rails.logger.info "  Recommendations:"
        health[:recommendations].each do |rec|
          Rails.logger.info "    - #{rec}"
        end
      end
    end

    def check_performance_issues(metrics)
      return unless metrics[:pattern_cache]

      cache_metrics = metrics[:pattern_cache]
      issues = []

      # Check cache hit rate using configuration
      hit_rate = cache_metrics[:hit_rate].to_f
      hit_rate_severity = Services::Infrastructure::PerformanceConfig.check_threshold(:cache, :hit_rate, 100 - hit_rate)

      if hit_rate_severity != :healthy
        target = Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :hit_rate, :target)
        issues << {
          type: :low_hit_rate,
          severity: hit_rate_severity,
          message: "Cache hit rate is #{hit_rate}% (target: >#{target}%)",
          metrics: { hit_rate: hit_rate }
        }
      end

      # Check lookup time using configuration
      lookup_time = cache_metrics[:average_lookup_time_ms].to_f
      lookup_severity = Services::Infrastructure::PerformanceConfig.check_threshold(:cache, :lookup_time_ms, lookup_time)

      if lookup_severity != :healthy
        target = Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :lookup_time_ms, :target)
        issues << {
          type: :slow_lookups,
          severity: lookup_severity,
          message: "Average lookup time is #{lookup_time}ms (target: <#{target}ms)",
          metrics: { avg_lookup_time_ms: lookup_time }
        }
      end

      # Check memory usage using configuration
      memory_entries = cache_metrics[:memory_entries].to_i
      memory_severity = Services::Infrastructure::PerformanceConfig.check_threshold(:cache, :memory_entries, memory_entries)

      if memory_severity != :healthy
        warning_threshold = Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :memory_entries, :warning)
        critical_threshold = Services::Infrastructure::PerformanceConfig.threshold_for(:cache, :memory_entries, :critical)
        issues << {
          type: :high_memory_usage,
          severity: memory_severity,
          message: "Cache has #{memory_entries} entries (warning: >#{warning_threshold}, critical: >#{critical_threshold})",
          metrics: { memory_entries: memory_entries }
        }
      end

      # Check warmup status
      if cache_metrics[:warmup_status] && cache_metrics[:warmup_status][:status] == "outdated"
        issues << {
          type: :cache_not_warmed,
          severity: :warning,
          message: "Cache warmup is outdated (last run: #{cache_metrics[:warmup_status][:minutes_ago]} minutes ago)",
          metrics: cache_metrics[:warmup_status]
        }
      end

      # Trigger alerts for issues with throttling
      issues.each do |issue|
        throttle_key = "alert_throttle:#{issue[:type]}:#{issue[:severity]}"
        unless Rails.cache.exist?(throttle_key)
          ActiveSupport::Notifications.instrument("performance.alert", issue)
          # Prevent duplicate alerts for configured interval
          throttle_minutes = Services::Infrastructure::PerformanceConfig::MONITORING_CONFIG[:alert_throttle_minutes]
          Rails.cache.write(throttle_key, true, expires_in: throttle_minutes.minutes)
        end
      end
    end
  end
end

# Add performance tracking methods to ApplicationController if needed
if defined?(ApplicationController)
  class ApplicationController
    around_action :track_request_performance, if: -> { Rails.env.production? }

    private

    def track_request_performance
      start_time = Time.current

      yield

      duration_ms = (Time.current - start_time) * 1000

      # Log slow requests
      if duration_ms > 1000
        Rails.logger.warn "[PerformanceMonitoring] Slow request: #{request.path} took #{duration_ms.round}ms"
      end

      # Record metric
      if defined?(Services::Infrastructure::MonitoringService)
        Services::Infrastructure::MonitoringService.record_metric(
          "request.duration",
          duration_ms,
          {
            controller: controller_name,
            action: action_name,
            method: request.request_method,
            path: request.path
          }
        )
      end
    rescue => e
      # Don't let monitoring errors break the request
      Rails.logger.error "[PerformanceMonitoring] Error tracking request: #{e.message}"
      raise e
    end
  end
end

# Register shutdown hook to clean up monitoring thread
at_exit do
  PerformanceMonitoring.stop if defined?(PerformanceMonitoring)
end
