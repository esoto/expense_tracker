# frozen_string_literal: true

module Services
  module Infrastructure
    # Centralized performance configuration module
    # Contains all performance thresholds and configuration settings
    module PerformanceConfig
      extend ActiveSupport::Concern

      # Cache performance thresholds
      CACHE_THRESHOLDS = {
        hit_rate: {
          target: 90,
          warning: 80,
          critical: 50
        },
        lookup_time_ms: {
          target: 1,
          warning: 5,
          critical: 10
        },
        memory_entries: {
          target: 5_000,
          warning: 10_000,
          critical: 50_000
        },
        warmup_interval_minutes: {
          target: 15,
          warning: 30,
          critical: 60
        }
      }.freeze

      # Request performance thresholds
      REQUEST_THRESHOLDS = {
        duration_ms: {
          target: 200,
          warning: 500,
          critical: 1000
        }
      }.freeze

      # Job performance thresholds
      JOB_THRESHOLDS = {
        wait_time_seconds: {
          target: 5,
          warning: 30,
          critical: 60
        },
        execution_time_seconds: {
          target: 10,
          warning: 60,
          critical: 300
        },
        failure_rate_percent: {
          target: 1,
          warning: 5,
          critical: 10
        }
      }.freeze

      # Monitoring configuration
      MONITORING_CONFIG = {
        health_check_interval: {
          production: 300, # 5 minutes
          development: 60  # 1 minute
        },
        metrics_sample_rate: 0.01, # Sample 1% of requests
        metrics_retention_hours: 24,
        max_metric_values: 1000, # Keep last 1000 values per metric
        alert_throttle_minutes: 15 # Don't repeat same alert within 15 minutes
      }.freeze

      # Cache configuration
      CACHE_CONFIG = {
        version: "v2", # Increment when cache structure changes
        race_condition_ttl: 10.seconds, # Prevents cache stampede
        memory_cache_max_size_mb: 50,
        memory_cache_ttl: 5.minutes,
        redis_cache_ttl: 24.hours,
        pattern_cache_warming: {
          enabled: true,
          interval: 15.minutes,
          batch_size: 100
        }
      }.freeze

      # System resource thresholds
      SYSTEM_THRESHOLDS = {
        disk_usage_percent: {
          target: 60,
          warning: 80,
          critical: 90
        },
        memory_usage_percent: {
          target: 60,
          warning: 80,
          critical: 90
        }
      }.freeze

      class << self
        # Get threshold value for a specific metric
        def threshold_for(category, metric, level = :target)
          category_thresholds = const_get("#{category.upcase}_THRESHOLDS")
          category_thresholds.dig(metric, level)
        rescue NameError
          nil
        end

        # Get monitoring interval based on environment
        def monitoring_interval
          interval_config = MONITORING_CONFIG[:health_check_interval]
          Rails.env.production? ? interval_config[:production] : interval_config[:development]
        end

        # Check if a value exceeds threshold and return severity
        def check_threshold(category, metric, value)
          thresholds = const_get("#{category.upcase}_THRESHOLDS")[metric]
          return :healthy unless thresholds

          # Convert to float for comparison
          val = value.to_f

          if val >= thresholds[:critical]
            :critical
          elsif val >= thresholds[:warning]
            :warning
          elsif val >= thresholds[:target]
            :degraded
          else
            :healthy
          end
        rescue StandardError
          :unknown
        end

        # Get cache version for invalidation
        def cache_version
          CACHE_CONFIG[:version]
        end

        # Get race condition TTL for cache stampede protection
        def race_condition_ttl
          CACHE_CONFIG[:race_condition_ttl]
        end

        # Check if pattern cache warming is enabled
        def pattern_cache_warming_enabled?
          CACHE_CONFIG.dig(:pattern_cache_warming, :enabled)
        end

        # Get pattern cache warming interval
        def pattern_cache_warming_interval
          CACHE_CONFIG.dig(:pattern_cache_warming, :interval)
        end

        # Generate cache key with version
        def versioned_cache_key(base_key)
          "#{base_key}:#{cache_version}"
        end

        # Get all configured thresholds as a hash
        def all_thresholds
          {
            cache: CACHE_THRESHOLDS,
            request: REQUEST_THRESHOLDS,
            job: JOB_THRESHOLDS,
            system: SYSTEM_THRESHOLDS
          }
        end

        # Export configuration as JSON for monitoring dashboards
        def to_json
          {
            thresholds: all_thresholds,
            monitoring: MONITORING_CONFIG,
            cache: CACHE_CONFIG,
            version: cache_version,
            environment: Rails.env
          }.to_json
        end
      end
    end
  end
end
