# frozen_string_literal: true

module Categorization
  module Monitoring
    # Service for monitoring and reporting on categorization data quality
    # Provides comprehensive metrics, auditing, and recommendations for data improvements
    class DataQualityChecker
      # Quality thresholds
      QUALITY_THRESHOLDS = {
        min_patterns_per_category: 3,
        min_pattern_success_rate: 0.5,
        max_unused_days: 30,
        min_coverage_ratio: 0.7,
        max_duplicate_similarity: 0.9,
        min_diversity_score: 0.6
      }.freeze

      # Quality score weights
      SCORE_WEIGHTS = {
        coverage: 0.25,
        success_rate: 0.30,
        diversity: 0.20,
        active_ratio: 0.15,
        freshness: 0.10
      }.freeze

      attr_reader :results, :recommendations

      def initialize
        @results = {}
        @recommendations = []
      end

      # Perform comprehensive data quality audit
      def audit
        @results = {}
        @recommendations = []

        audit_patterns
        audit_categories
        audit_coverage
        audit_performance
        audit_duplicates
        calculate_quality_score

        build_audit_report
      end

      # Audit pattern data quality
      def audit_patterns
        patterns = CategorizationPattern.all
        active_patterns = patterns.active

        @results[:patterns] = {
          total: patterns.count,
          active: active_patterns.count,
          inactive: patterns.inactive.count,
          by_type: pattern_type_distribution(patterns),
          user_created: patterns.user_created.count,
          system_created: patterns.system_created.count,
          low_success: count_low_success_patterns(patterns),
          unused: count_unused_patterns(patterns),
          high_performers: count_high_performing_patterns(patterns),
          recently_added: patterns.where(created_at: 7.days.ago..).count,
          recently_updated: patterns.where(updated_at: 24.hours.ago..).count
        }

        analyze_pattern_quality
      end

      # Audit category coverage
      def audit_categories
        categories = Category.all

        with_patterns_count = categories.joins(:categorization_patterns).distinct.count
        without_patterns_count = categories.left_joins(:categorization_patterns)
                                          .where(categorization_patterns: { id: nil })
                                          .count

        @results[:categories] = {
          total: categories.count,
          with_patterns: with_patterns_count,
          without_patterns: without_patterns_count,
          pattern_distribution: category_pattern_distribution,
          avg_patterns_per_category: calculate_avg_patterns_per_category(with_patterns_count),
          categories_below_threshold: count_categories_below_threshold
        }

        analyze_category_quality
      end

      # Audit overall coverage
      def audit_coverage
        total_categories = Category.count
        covered_categories = Category.joins(:categorization_patterns).distinct.count

        coverage_ratio = total_categories.positive? ? covered_categories.to_f / total_categories : 0

        @results[:coverage] = {
          ratio: coverage_ratio.round(3),
          covered_categories: covered_categories,
          total_categories: total_categories,
          coverage_by_type: calculate_coverage_by_type,
          gaps: identify_coverage_gaps
        }

        analyze_coverage_quality
      end

      # Audit pattern performance
      def audit_performance
        patterns = CategorizationPattern.active

        @results[:performance] = {
          avg_success_rate: calculate_average_success_rate(patterns),
          median_success_rate: calculate_median_success_rate(patterns),
          total_usage: patterns.sum(:usage_count),
          total_successes: patterns.sum(:success_count),
          patterns_by_performance: group_patterns_by_performance(patterns),
          learning_velocity: calculate_learning_velocity
        }

        analyze_performance_quality
      end

      # Audit duplicate and similar patterns
      def audit_duplicates
        duplicates = find_duplicate_patterns
        similar = find_similar_patterns

        @results[:duplicates] = {
          exact_duplicates: duplicates[:exact].count,
          similar_patterns: similar.count,
          duplicate_details: duplicates[:details],
          similarity_clusters: similar
        }

        analyze_duplicate_quality
      end

      # Calculate overall data quality score
      def calculate_quality_score
        scores = {}

        # Coverage score
        scores[:coverage] = @results[:coverage][:ratio]

        # Success rate score
        avg_success = @results[:performance][:avg_success_rate]
        scores[:success_rate] = avg_success.present? ? avg_success : 0

        # Diversity score
        scores[:diversity] = calculate_diversity_score

        # Active ratio score
        total = @results[:patterns][:total]
        active = @results[:patterns][:active]
        scores[:active_ratio] = total.positive? ? active.to_f / total : 0

        # Freshness score
        scores[:freshness] = calculate_freshness_score

        # Calculate weighted overall score
        overall_score = SCORE_WEIGHTS.sum do |metric, weight|
          scores[metric] * weight
        end

        @results[:quality_score] = {
          overall: overall_score.round(3),
          components: scores.transform_values { |v| v.round(3) },
          grade: determine_quality_grade(overall_score)
        }
      end

      # Generate recommendations based on audit results
      def generate_recommendations
        @recommendations = []

        # Pattern recommendations
        recommend_pattern_improvements

        # Coverage recommendations
        recommend_coverage_improvements

        # Performance recommendations
        recommend_performance_improvements

        # Duplicate recommendations
        recommend_duplicate_cleanup

        # Maintenance recommendations
        recommend_maintenance_actions

        @recommendations
      end

      # Build complete audit report
      def build_audit_report
        generate_recommendations

        {
          timestamp: Time.current.iso8601,
          summary: build_summary,
          patterns: @results[:patterns],
          categories: @results[:categories],
          coverage: @results[:coverage],
          performance: @results[:performance],
          duplicates: @results[:duplicates],
          quality_score: @results[:quality_score],
          recommendations: @recommendations,
          next_audit: Time.current + 1.day
        }
      end

      # Check specific pattern quality
      def check_pattern_quality(pattern)
        issues = []

        # Check success rate
        if pattern.usage_count >= 10 && pattern.success_rate < QUALITY_THRESHOLDS[:min_pattern_success_rate]
          issues << { type: :low_success_rate, value: pattern.success_rate }
        end

        # Check if unused
        if pattern.usage_count.zero? && pattern.created_at < QUALITY_THRESHOLDS[:max_unused_days].days.ago
          issues << { type: :unused, days: (Time.current - pattern.created_at).to_i / 86400 }
        end

        # Check pattern value quality
        if pattern.pattern_type == "merchant" && pattern.pattern_value.length < 3
          issues << { type: :too_short, length: pattern.pattern_value.length }
        end

        {
          pattern_id: pattern.id,
          pattern_type: pattern.pattern_type,
          pattern_value: pattern.pattern_value,
          issues: issues,
          quality: issues.empty? ? :good : :needs_attention
        }
      end

      private

      # Pattern analysis helpers
      def pattern_type_distribution(patterns)
        patterns.group(:pattern_type).count
      end

      def count_low_success_patterns(patterns)
        patterns
          .where("usage_count >= ?", 10)
          .where("success_rate < ?", QUALITY_THRESHOLDS[:min_pattern_success_rate])
          .count
      end

      def count_unused_patterns(patterns)
        patterns
          .where(usage_count: 0)
          .where("created_at < ?", QUALITY_THRESHOLDS[:max_unused_days].days.ago)
          .count
      end

      def count_high_performing_patterns(patterns)
        patterns
          .where("usage_count >= ?", 20)
          .where("success_rate >= ?", 0.8)
          .count
      end

      def analyze_pattern_quality
        total = @results[:patterns][:total]
        return if total.zero?

        unused_ratio = @results[:patterns][:unused].to_f / total
        if unused_ratio > 0.3
          @recommendations << {
            type: :high_unused_patterns,
            severity: :medium,
            message: "#{(@results[:patterns][:unused])} unused patterns detected. Consider removing patterns unused for > 30 days.",
            action: :cleanup_unused_patterns
          }
        end
      end

      # Category analysis helpers
      def category_pattern_distribution
        Category
          .joins(:categorization_patterns)
          .group("categories.id")
          .count("categorization_patterns.id")
          .values
          .group_by(&:itself)
          .transform_values(&:count)
      end

      def calculate_avg_patterns_per_category(categories_with_patterns = nil)
        categories_with_patterns ||= Category.joins(:categorization_patterns).distinct.count
        return 0 if categories_with_patterns.zero?

        total_patterns = CategorizationPattern.count
        (total_patterns.to_f / categories_with_patterns).round(2)
      end

      def count_categories_below_threshold
        Category
          .left_joins(:categorization_patterns)
          .group("categories.id")
          .having("COUNT(categorization_patterns.id) < ?", QUALITY_THRESHOLDS[:min_patterns_per_category])
          .count
          .keys
          .count
      end

      def analyze_category_quality
        below_threshold = @results[:categories][:categories_below_threshold]
        total = @results[:categories][:total]

        if below_threshold > total * 0.3
          @recommendations << {
            type: :insufficient_category_patterns,
            severity: :high,
            message: "#{below_threshold} categories have fewer than #{QUALITY_THRESHOLDS[:min_patterns_per_category]} patterns.",
            action: :add_patterns_to_categories
          }
        end
      end

      # Coverage analysis helpers
      def calculate_coverage_by_type
        CategorizationPattern::PATTERN_TYPES.each_with_object({}) do |type, hash|
          patterns = CategorizationPattern.where(pattern_type: type)
          categories_covered = patterns.select(:category_id).distinct.count
          hash[type] = {
            patterns: patterns.count,
            categories_covered: categories_covered
          }
        end
      end

      def identify_coverage_gaps
        categories_without_patterns = Category
          .left_joins(:categorization_patterns)
          .where(categorization_patterns: { id: nil })
          .pluck(:name)

        {
          categories_without_patterns: categories_without_patterns,
          count: categories_without_patterns.count
        }
      end

      def analyze_coverage_quality
        coverage_ratio = @results[:coverage][:ratio]

        if coverage_ratio < QUALITY_THRESHOLDS[:min_coverage_ratio]
          @recommendations << {
            type: :low_coverage,
            severity: :high,
            message: "Pattern coverage is only #{(coverage_ratio * 100).round(1)}%. Aim for at least #{(QUALITY_THRESHOLDS[:min_coverage_ratio] * 100).round}%.",
            action: :improve_coverage
          }
        end
      end

      # Performance analysis helpers
      def calculate_average_success_rate(patterns)
        weighted_patterns = patterns.where("usage_count > ?", 0)
        return 0 if weighted_patterns.empty?

        total_usage = weighted_patterns.sum(:usage_count)
        return 0 if total_usage.zero?

        weighted_sum = weighted_patterns.sum("success_rate * usage_count")
        (weighted_sum / total_usage).round(3)
      end

      def calculate_median_success_rate(patterns)
        rates = patterns.where("usage_count > ?", 0).pluck(:success_rate).sort
        return 0 if rates.empty?

        mid = rates.length / 2
        rates.length.odd? ? rates[mid] : (rates[mid - 1] + rates[mid]) / 2.0
      end

      def group_patterns_by_performance(patterns)
        {
          excellent: patterns.where("success_rate >= ?", 0.9).count,
          good: patterns.where("success_rate >= ? AND success_rate < ?", 0.7, 0.9).count,
          fair: patterns.where("success_rate >= ? AND success_rate < ?", 0.5, 0.7).count,
          poor: patterns.where("success_rate < ?", 0.5).count
        }
      end

      def calculate_learning_velocity
        # Measure how quickly the system is learning (new patterns vs updated patterns)
        recent_window = 7.days.ago

        new_patterns = CategorizationPattern.where(created_at: recent_window..).count
        improved_patterns = CategorizationPattern
          .where(updated_at: recent_window..)
          .where("success_count > 0")
          .where("updated_at != created_at")
          .count

        {
          new_patterns_per_day: (new_patterns / 7.0).round(2),
          improved_patterns_per_day: (improved_patterns / 7.0).round(2)
        }
      end

      def analyze_performance_quality
        avg_success = @results[:performance][:avg_success_rate]

        if avg_success < QUALITY_THRESHOLDS[:min_pattern_success_rate]
          @recommendations << {
            type: :low_overall_success_rate,
            severity: :high,
            message: "Average success rate is #{(avg_success * 100).round(1)}%. Review and improve pattern quality.",
            action: :review_pattern_quality
          }
        end
      end

      # Duplicate analysis helpers
      def find_duplicate_patterns
        exact_duplicates = CategorizationPattern
          .group(:pattern_type, :pattern_value)
          .having("COUNT(*) > 1")
          .count

        details = exact_duplicates.map do |(type, value), count|
          {
            pattern_type: type,
            pattern_value: value,
            count: count,
            categories: CategorizationPattern
              .where(pattern_type: type, pattern_value: value)
              .joins(:category)
              .pluck("categories.name")
          }
        end

        {
          exact: exact_duplicates,
          details: details
        }
      end

      def find_similar_patterns
        similar_groups = []

        # Group patterns by type for similarity checking
        %w[merchant keyword description].each do |pattern_type|
          patterns = CategorizationPattern.where(pattern_type: pattern_type).pluck(:id, :pattern_value)

          # Use simple string similarity for now
          patterns.combination(2).each do |p1, p2|
            similarity = calculate_string_similarity(p1[1], p2[1])
            if similarity > QUALITY_THRESHOLDS[:max_duplicate_similarity]
              similar_groups << {
                pattern_ids: [ p1[0], p2[0] ],
                values: [ p1[1], p2[1] ],
                similarity: similarity.round(3),
                pattern_type: pattern_type
              }
            end
          end
        end

        similar_groups
      end

      def calculate_string_similarity(str1, str2)
        return 0 if str1.nil? || str2.nil?
        return 1 if str1 == str2

        # Simple Levenshtein distance-based similarity
        longer = [ str1.length, str2.length ].max
        return 0 if longer.zero?

        distance = levenshtein_distance(str1, str2)
        1.0 - (distance.to_f / longer)
      end

      def levenshtein_distance(str1, str2)
        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }

        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,
              matrix[i][j - 1] + 1,
              matrix[i - 1][j - 1] + cost
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end

      def analyze_duplicate_quality
        exact_count = @results[:duplicates][:exact_duplicates]
        similar_count = @results[:duplicates][:similar_patterns]

        if exact_count > 0
          @recommendations << {
            type: :exact_duplicates_found,
            severity: :medium,
            message: "Found #{exact_count} exact duplicate patterns. Consider consolidating.",
            action: :remove_duplicate_patterns
          }
        end

        if similar_count > 10
          @recommendations << {
            type: :many_similar_patterns,
            severity: :low,
            message: "Found #{similar_count} similar patterns. Review for potential consolidation.",
            action: :review_similar_patterns
          }
        end
      end

      # Score calculation helpers
      def calculate_diversity_score
        return 0 if @results[:patterns][:total].zero?

        # Consider pattern type diversity
        type_distribution = @results[:patterns][:by_type].values
        type_diversity = calculate_distribution_entropy(type_distribution)

        # Consider category coverage diversity
        category_distribution = category_pattern_distribution.values
        category_diversity = calculate_distribution_entropy(category_distribution)

        # Combined diversity score
        (type_diversity * 0.4 + category_diversity * 0.6).round(3)
      end

      def calculate_distribution_entropy(distribution)
        return 0 if distribution.empty?

        total = distribution.sum.to_f
        return 0 if total.zero?

        # Calculate Shannon entropy normalized to [0, 1]
        entropy = distribution.sum do |count|
          next 0 if count.zero?
          probability = count / total
          -probability * Math.log2(probability)
        end

        max_entropy = Math.log2(distribution.length)
        max_entropy.zero? ? 0 : (entropy / max_entropy)
      end

      def calculate_freshness_score
        return 0 if @results[:patterns][:total].zero?

        recently_active = @results[:patterns][:recently_updated]
        total = @results[:patterns][:total]

        # Score based on percentage of recently active patterns
        base_score = recently_active.to_f / total

        # Boost score if there's learning velocity
        velocity = @results[:performance][:learning_velocity]
        if velocity[:new_patterns_per_day] > 0 || velocity[:improved_patterns_per_day] > 0
          base_score = [ base_score * 1.2, 1.0 ].min
        end

        base_score
      end

      def determine_quality_grade(score)
        case score
        when 0.9..1.0 then "A"
        when 0.8...0.9 then "B"
        when 0.7...0.8 then "C"
        when 0.6...0.7 then "D"
        else "F"
        end
      end

      # Recommendation helpers
      def recommend_pattern_improvements
        # Check for pattern types that are underutilized
        type_distribution = @results[:patterns][:by_type]

        CategorizationPattern::PATTERN_TYPES.each do |type|
          if type_distribution[type].to_i < 5
            @recommendations << {
              type: :underutilized_pattern_type,
              severity: :low,
              message: "Pattern type '#{type}' has only #{type_distribution[type].to_i} patterns. Consider adding more.",
              action: :add_patterns,
              pattern_type: type
            }
          end
        end
      end

      def recommend_coverage_improvements
        gaps = @results[:coverage][:gaps]

        if gaps[:count] > 0
          categories = gaps[:categories_without_patterns].first(5).join(", ")
          more = gaps[:count] > 5 ? " and #{gaps[:count] - 5} more" : ""

          @recommendations << {
            type: :categories_without_patterns,
            severity: :high,
            message: "Categories without patterns: #{categories}#{more}",
            action: :add_patterns_to_categories,
            categories: gaps[:categories_without_patterns]
          }
        end
      end

      def recommend_performance_improvements
        poor_performers = @results[:performance][:patterns_by_performance][:poor]
        avg_success = @results[:performance][:avg_success_rate]

        # Check overall average success rate
        if avg_success < QUALITY_THRESHOLDS[:min_pattern_success_rate]
          @recommendations << {
            type: :low_overall_success_rate,
            severity: :high,
            message: "Average success rate is #{(avg_success * 100).round(1)}%. Review and improve pattern quality.",
            action: :review_pattern_quality
          }
        end

        # Check for many poor performing individual patterns
        if poor_performers > 10
          @recommendations << {
            type: :many_poor_performers,
            severity: :medium,
            message: "#{poor_performers} patterns have success rate < 50%. Review and improve or deactivate.",
            action: :review_poor_performers
          }
        end
      end

      def recommend_duplicate_cleanup
        # Already handled in analyze_duplicate_quality
      end

      def recommend_maintenance_actions
        # Check for stale patterns
        stale_patterns = CategorizationPattern
          .where("updated_at < ?", 90.days.ago)
          .where("usage_count < ?", 5)
          .count

        if stale_patterns > 20
          @recommendations << {
            type: :stale_patterns,
            severity: :low,
            message: "#{stale_patterns} patterns haven't been used in 90+ days. Consider archiving.",
            action: :archive_stale_patterns
          }
        end

        # Check for patterns needing retraining
        needs_retraining = CategorizationPattern
          .where("usage_count > ?", 50)
          .where("success_rate < ?", 0.6)
          .count

        if needs_retraining > 0
          @recommendations << {
            type: :patterns_need_retraining,
            severity: :medium,
            message: "#{needs_retraining} frequently-used patterns have low success rates. Consider retraining.",
            action: :retrain_patterns
          }
        end
      end

      def build_summary
        {
          total_patterns: @results[:patterns][:total],
          active_patterns: @results[:patterns][:active],
          category_coverage: "#{(@results[:coverage][:ratio] * 100).round(1)}%",
          avg_success_rate: "#{(@results[:performance][:avg_success_rate] * 100).round(1)}%",
          quality_grade: @results[:quality_score][:grade],
          quality_score: @results[:quality_score][:overall],
          critical_issues: @recommendations.count { |r| r[:severity] == :high },
          total_recommendations: @recommendations.count
        }
      end
    end
  end
end
