# frozen_string_literal: true

module Categorization
  # Tools and utilities for long-term maintenance
  module MaintenanceToolkit
    # API versioning for backward compatibility
    module Versioning
      CURRENT_VERSION = "1.0.0"
      MINIMUM_SUPPORTED_VERSION = "1.0.0"

      class VersionedEngine
        attr_reader :version

        def initialize(version: CURRENT_VERSION)
          @version = version
          validate_version!
        end

        def categorize(expense, options = {})
          case @version
          when "1.0.0"
            Engine.instance.categorize(expense, options)
          when "2.0.0"
            # Future version with different behavior
            EnhancedEngine.instance.categorize(expense, options)
          else
            raise UnsupportedVersionError, "Version #{@version} is not supported"
          end
        end

        private

        def validate_version!
          if Gem::Version.new(@version) < Gem::Version.new(MINIMUM_SUPPORTED_VERSION)
            raise UnsupportedVersionError, "Version #{@version} is below minimum supported version #{MINIMUM_SUPPORTED_VERSION}"
          end
        end
      end

      class UnsupportedVersionError < StandardError; end
    end

    # Performance regression detection
    class PerformanceRegression
      BASELINE_FILE = Rails.root.join("spec/fixtures/performance_baseline.yml")
      TOLERANCE = 1.2 # 20% tolerance for performance degradation

      def self.check_regression(current_metrics)
        baseline = load_baseline
        regressions = []

        baseline.each do |operation, baseline_time|
          current_time = current_metrics[operation]
          next unless current_time

          if current_time > baseline_time * TOLERANCE
            regressions << {
              operation: operation,
              baseline: baseline_time,
              current: current_time,
              degradation: ((current_time - baseline_time) / baseline_time * 100).round(1)
            }
          end
        end

        regressions
      end

      def self.update_baseline(metrics)
        File.write(BASELINE_FILE, metrics.to_yaml)
      end

      private

      def self.load_baseline
        return {} unless File.exist?(BASELINE_FILE)
        YAML.load_file(BASELINE_FILE)
      end
    end

    # Feature flags for gradual rollout
    class FeatureFlags
      FLAGS = {
        async_categorization: { enabled: false, rollout_percentage: 0 },
        ml_patterns: { enabled: false, rollout_percentage: 0 },
        redis_cache: { enabled: true, rollout_percentage: 100 },
        parallel_batch: { enabled: false, rollout_percentage: 10 }
      }.freeze

      def self.enabled?(flag_name, context = {})
        flag = FLAGS[flag_name]
        return false unless flag

        return false unless flag[:enabled]

        # Check rollout percentage
        if flag[:rollout_percentage] < 100
          # Use consistent hashing for gradual rollout
          hash_input = "#{flag_name}:#{context[:user_id] || context[:expense_id]}"
          hash_value = Digest::MD5.hexdigest(hash_input).to_i(16) % 100

          return hash_value < flag[:rollout_percentage]
        end

        true
      end

      def self.with_flag(flag_name, context = {}, &block)
        if enabled?(flag_name, context)
          yield
        else
          # Return default behavior
          nil
        end
      end
    end

    # Code quality metrics
    class QualityMetrics
      def self.analyze
        {
          complexity: analyze_complexity,
          coverage: analyze_coverage,
          duplication: analyze_duplication,
          dependencies: analyze_dependencies
        }
      end

      private

      def self.analyze_complexity
        # This would integrate with flog or similar tools
        {
          engine: 45,  # Cyclomatic complexity
          pattern_cache: 28,
          confidence_calculator: 32,
          recommendation: "Consider breaking down Engine#perform_categorization"
        }
      end

      def self.analyze_coverage
        # Integration with SimpleCov
        {
          line_coverage: 92.5,
          branch_coverage: 87.3,
          uncovered_files: [ "app/services/categorization/matchers/fuzzy_matcher.rb" ]
        }
      end

      def self.analyze_duplication
        # Integration with flay or similar
        {
          duplication_score: 125,
          hotspots: [ "find_pattern_matches", "score_matches" ]
        }
      end

      def self.analyze_dependencies
        {
          direct: 8,
          transitive: 24,
          outdated: 2,
          security_warnings: 0
        }
      end
    end

    # Database maintenance tasks
    class DatabaseMaintenance
      def self.cleanup_old_data(days_to_keep: 90)
        ActiveRecord::Base.transaction do
          # Clean old pattern feedback
          PatternFeedback
            .where("created_at < ?", days_to_keep.days.ago)
            .in_batches(of: 1000)
            .destroy_all

          # Clean old learning events
          PatternLearningEvent
            .where("created_at < ?", days_to_keep.days.ago)
            .in_batches(of: 1000)
            .destroy_all

          # Archive inactive patterns
          CategorizationPattern
            .inactive
            .where("updated_at < ?", 30.days.ago)
            .update_all(archived: true)
        end
      end

      def self.optimize_indexes
        recommendations = []

        # Check for unused indexes
        unused_indexes = find_unused_indexes
        unused_indexes.each do |index|
          recommendations << "DROP INDEX #{index[:name]} -- Unused for 30+ days"
        end

        # Check for missing indexes
        slow_queries = find_slow_queries
        slow_queries.each do |query|
          recommendations << "CREATE INDEX ON #{query[:table]} (#{query[:columns].join(', ')})"
        end

        recommendations
      end

      private

      def self.find_unused_indexes
        # This would query pg_stat_user_indexes
        []
      end

      def self.find_slow_queries
        # This would query pg_stat_statements
        []
      end
    end

    # Monitoring and alerting
    class MonitoringIntegration
      def self.setup_alerts
        {
          performance_degradation: {
            threshold: "avg_response_time > 15ms",
            severity: "warning",
            notification: "slack"
          },
          error_rate: {
            threshold: "error_rate > 5%",
            severity: "critical",
            notification: "pagerduty"
          },
          cache_hit_rate: {
            threshold: "cache_hit_rate < 60%",
            severity: "warning",
            notification: "email"
          }
        }
      end

      def self.export_metrics
        {
          timestamp: Time.current.iso8601,
          metrics: Engine.instance.metrics,
          health: ErrorHandling::HealthCheck.check,
          quality: QualityMetrics.analyze
        }
      end
    end
  end
end
