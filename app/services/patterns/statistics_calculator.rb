# frozen_string_literal: true

module Patterns
  # Service object for calculating pattern statistics with caching
  class StatisticsCalculator
    include ActiveModel::Model

    CACHE_TTL = 15.minutes

    attr_accessor :filters

    def initialize(filters = {})
      @filters = filters
    end

    def calculate
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        {
          overview: calculate_overview,
          performance: calculate_performance,
          distribution: calculate_distribution,
          trends: calculate_trends,
          recommendations: generate_recommendations
        }
      end
    end

    def invalidate_cache
      Rails.cache.delete(cache_key)
    end

    private

    def cache_key
      [ "pattern_statistics", filters.sort.to_h ].join(":")
    end

    def base_scope
      scope = CategorizationPattern.all

      if filters[:category_id].present?
        scope = scope.where(category_id: filters[:category_id])
      end

      if filters[:pattern_type].present?
        scope = scope.where(pattern_type: filters[:pattern_type])
      end

      if filters[:active].present?
        scope = filters[:active] == "true" ? scope.active : scope.inactive
      end

      scope
    end

    def calculate_overview
      {
        total_patterns: base_scope.count,
        active_patterns: base_scope.active.count,
        user_created: base_scope.user_created.count,
        system_created: base_scope.system_created.count,
        average_success_rate: calculate_average_success_rate,
        total_usage: base_scope.sum(:usage_count),
        total_successes: base_scope.sum(:success_count)
      }
    end

    def calculate_average_success_rate
      patterns_with_usage = base_scope.where("usage_count > 0")
      return 0.0 if patterns_with_usage.empty?

      total_usage = patterns_with_usage.sum(:usage_count)
      total_successes = patterns_with_usage.sum(:success_count)

      return 0.0 if total_usage.zero?

      ((total_successes.to_f / total_usage) * 100).round(2)
    end

    def calculate_performance
      {
        patterns_by_type: patterns_by_type_performance,
        patterns_by_category: patterns_by_category_performance,
        low_performers: find_low_performers,
        high_performers: find_high_performers,
        accuracy_trend: calculate_accuracy_trend
      }
    end

    def calculate_accuracy_trend
      calculate_daily_accuracy(7)
    end

    def patterns_by_type_performance
      base_scope
        .group(:pattern_type)
        .select(
          :pattern_type,
          "COUNT(*) as count",
          "AVG(success_rate) as avg_success_rate",
          "SUM(usage_count) as total_usage"
        )
        .map do |result|
          {
            type: result.pattern_type,
            count: result.count,
            average_success_rate: (result.avg_success_rate * 100).round(2),
            total_usage: result.total_usage
          }
        end
        .sort_by { |r| -r[:average_success_rate] }
    end

    def patterns_by_category_performance
      Category
        .joins(:categorization_patterns)
        .merge(base_scope)
        .select(
          "categories.id",
          "categories.name",
          "COUNT(categorization_patterns.id) as pattern_count",
          "AVG(categorization_patterns.success_rate) as avg_success_rate",
          "SUM(categorization_patterns.usage_count) as total_usage"
        )
        .group("categories.id, categories.name")
        .map do |category|
          {
            id: category.id,
            name: category.name,
            pattern_count: category.pattern_count,
            average_success_rate: (category.avg_success_rate * 100).round(2),
            total_usage: category.total_usage
          }
        end
        .sort_by { |c| -c[:average_success_rate] }
    end

    def find_low_performers
      base_scope
        .active
        .where("usage_count >= 10 AND success_rate < 0.5")
        .includes(:category)
        .order(success_rate: :asc)
        .limit(10)
        .map { |p| format_pattern_stats(p) }
    end

    def find_high_performers
      base_scope
        .active
        .successful
        .frequently_used
        .includes(:category)
        .order(success_rate: :desc, usage_count: :desc)
        .limit(10)
        .map { |p| format_pattern_stats(p) }
    end

    def format_pattern_stats(pattern)
      {
        id: pattern.id,
        pattern_type: pattern.pattern_type,
        pattern_value: pattern.pattern_value,
        category: pattern.category.name,
        usage_count: pattern.usage_count,
        success_rate: (pattern.success_rate * 100).round(2),
        confidence_weight: pattern.confidence_weight
      }
    end

    def calculate_distribution
      {
        success_rate_distribution: calculate_success_distribution,
        usage_distribution: calculate_usage_distribution,
        confidence_distribution: calculate_confidence_distribution
      }
    end

    def calculate_success_distribution
      base_scope
        .group(
          Arel.sql("CASE
            WHEN success_rate >= 0.9 THEN '90-100%'
            WHEN success_rate >= 0.7 THEN '70-90%'
            WHEN success_rate >= 0.5 THEN '50-70%'
            WHEN success_rate >= 0.3 THEN '30-50%'
            ELSE '0-30%'
          END")
        )
        .count
    end

    def calculate_usage_distribution
      base_scope
        .group(
          Arel.sql("CASE
            WHEN usage_count >= 100 THEN '100+'
            WHEN usage_count >= 50 THEN '50-99'
            WHEN usage_count >= 20 THEN '20-49'
            WHEN usage_count >= 10 THEN '10-19'
            WHEN usage_count >= 1 THEN '1-9'
            ELSE '0'
          END")
        )
        .count
    end

    def calculate_confidence_distribution
      base_scope
        .group(
          Arel.sql("CASE
            WHEN confidence_weight >= 4 THEN 'Very High (4-5)'
            WHEN confidence_weight >= 3 THEN 'High (3-4)'
            WHEN confidence_weight >= 2 THEN 'Medium (2-3)'
            WHEN confidence_weight >= 1 THEN 'Low (1-2)'
            ELSE 'Very Low (<1)'
          END")
        )
        .count
    end

    def calculate_trends
      {
        daily_accuracy: calculate_daily_accuracy(7),
        weekly_usage: calculate_weekly_usage(4),
        monthly_growth: calculate_monthly_growth
      }
    end

    def calculate_daily_accuracy(days)
      return [] unless PatternFeedback.exists?

      PatternFeedback
        .joins(:categorization_pattern)
        .merge(base_scope)
        .where(created_at: days.days.ago..)
        .group_by_day(:created_at, format: "%Y-%m-%d")
        .group(:was_correct)
        .count
        .each_with_object({}) do |((date, was_correct), count), result|
          result[date] ||= { correct: 0, incorrect: 0, accuracy: 0 }
          if was_correct
            result[date][:correct] = count
          else
            result[date][:incorrect] = count
          end
        end
        .map do |date, counts|
          total = counts[:correct] + counts[:incorrect]
          accuracy = total > 0 ? (counts[:correct].to_f / total * 100).round(2) : 0

          {
            date: date,
            correct: counts[:correct],
            incorrect: counts[:incorrect],
            accuracy: accuracy
          }
        end
    end

    def calculate_weekly_usage(weeks)
      base_scope
        .where(created_at: weeks.weeks.ago..)
        .group_by_week(:created_at, format: "%Y-%m-%d")
        .count
    end

    def calculate_monthly_growth
      current_month_count = base_scope.where(created_at: Date.current.beginning_of_month..).count
      last_month_count = base_scope.where(created_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month).count

      return 0 if last_month_count.zero?

      growth_rate = ((current_month_count - last_month_count).to_f / last_month_count * 100).round(2)

      {
        current_month: current_month_count,
        last_month: last_month_count,
        growth_rate: growth_rate
      }
    end

    def generate_recommendations
      recommendations = []

      # Recommend deactivating poor performers
      low_performers = find_low_performers
      if low_performers.any?
        recommendations << {
          type: "performance",
          priority: "high",
          message: "#{low_performers.size} patterns have success rates below 50% and should be reviewed",
          action: "review_low_performers",
          data: low_performers.first(3)
        }
      end

      # Recommend pattern types that work well
      best_type = patterns_by_type_performance.first
      if best_type && best_type[:average_success_rate] > 80
        recommendations << {
          type: "pattern_type",
          priority: "medium",
          message: "#{best_type[:type]} patterns have the highest success rate (#{best_type[:average_success_rate]}%)",
          action: "focus_on_type",
          data: best_type
        }
      end

      # Recommend categories that need more patterns
      categories_needing_patterns = find_categories_needing_patterns
      if categories_needing_patterns.any?
        recommendations << {
          type: "coverage",
          priority: "low",
          message: "#{categories_needing_patterns.size} categories have fewer than 3 patterns",
          action: "add_patterns",
          data: categories_needing_patterns
        }
      end

      recommendations
    end

    def find_categories_needing_patterns
      Category
        .left_joins(:categorization_patterns)
        .group("categories.id, categories.name")
        .having("COUNT(categorization_patterns.id) < 3")
        .pluck(:name)
    end
  end
end
