# frozen_string_literal: true

module Analytics
  # Analyzes performance metrics for categorization patterns
  class PatternPerformanceAnalyzer
      include ActiveSupport::NumberHelper

      # Constants for query optimization and validation
      MINIMUM_USAGE_THRESHOLD = 5
      TARGET_SUCCESS_RATE = 0.85
      DEFAULT_LIMIT = 10
      MAX_RECENT_ACTIVITY = 20
      DEFAULT_PAGE_SIZE = 25
      MAX_PAGE_SIZE = 100
      MAX_DATE_RANGE_YEARS = 2
      CACHE_TTL_MINUTES = 5
      HEATMAP_CACHE_TTL_MINUTES = 30

      # Validated interval formats for SQL safety
      INTERVAL_FORMATS = {
        hourly: "YYYY-MM-DD HH24",
        daily: "YYYY-MM-DD",
        weekly: "YYYY-IW",
        monthly: "YYYY-MM"
      }.freeze

      attr_reader :time_range, :category_filter, :pattern_type_filter

      def initialize(time_range: 30.days.ago..Time.current, category_id: nil, pattern_type: nil)
        @time_range = time_range
        @category_filter = category_id
        @pattern_type_filter = pattern_type
      end

      # Overall accuracy metrics across all patterns
      def overall_metrics
        patterns = filtered_patterns
        feedbacks = filtered_feedbacks

        total_usage = patterns.sum(:usage_count)
        total_success = patterns.sum(:success_count)

        {
          total_patterns: patterns.count,
          active_patterns: patterns.active.count,
          total_usage: total_usage,
          total_success: total_success,
          overall_accuracy: total_usage > 0 ? (total_success.to_f / total_usage * 100).round(2) : 0,
          average_confidence: patterns.average(:confidence_weight)&.round(2) || 0,
          feedback_count: feedbacks.count,
          acceptance_rate: calculate_acceptance_rate(feedbacks)
        }
      end

      # Performance breakdown by category with optimized queries
      def category_performance(page: 1, per_page: DEFAULT_PAGE_SIZE)
        # Validate pagination parameters
        page = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, MAX_PAGE_SIZE ].min, 1 ].max

        # Use a single optimized query to avoid N+1
        query = Category.joins(:categorization_patterns)

        # Apply filters only if they exist
        if pattern_type_filter.present?
          query = query.where(categorization_patterns: { pattern_type: pattern_type_filter })
        end

        categories_data = query
          .group("categories.id", "categories.name", "categories.color")
          .select(
            "categories.id",
            "categories.name",
            "categories.color",
            "COUNT(DISTINCT categorization_patterns.id) as pattern_count",
            "COUNT(DISTINCT CASE WHEN categorization_patterns.active = true THEN categorization_patterns.id END) as active_patterns_count",
            "COALESCE(SUM(categorization_patterns.usage_count), 0) as total_usage",
            "COALESCE(SUM(categorization_patterns.success_count), 0) as total_success",
            "COALESCE(AVG(categorization_patterns.confidence_weight), 0) as avg_confidence"
          )
          .offset((page - 1) * per_page)
          .limit(per_page)

        categories_data.map do |category|
          {
            id: category.id,
            name: category.name,
            color: category.color,
            pattern_count: category.pattern_count,
            active_patterns: category.active_patterns_count,
            total_usage: category.total_usage,
            total_success: category.total_success,
            accuracy: category.total_usage > 0 ? (category.total_success.to_f / category.total_usage * 100).round(2) : 0,
            average_confidence: category.avg_confidence.round(2)
          }
        end.sort_by { |c| -c[:accuracy] }
      end

      # Most effective patterns (top performers)
      def top_patterns(limit: DEFAULT_LIMIT)
        patterns = filtered_patterns
                    .where("usage_count >= ?", MINIMUM_USAGE_THRESHOLD)
                    .includes(:category)
                    .order(success_rate: :desc, usage_count: :desc)
                    .limit(limit)

        patterns.map do |pattern|
          {
            id: pattern.id,
            pattern_type: pattern.pattern_type,
            pattern_value: pattern.pattern_value,
            category_name: pattern.category.name,
            category_color: pattern.category.color,
            usage_count: pattern.usage_count,
            success_count: pattern.success_count,
            success_rate: (pattern.success_rate * 100).round(2),
            confidence_weight: pattern.confidence_weight.round(2),
            user_created: pattern.user_created,
            active: pattern.active
          }
        end
      end

      # Least effective patterns (candidates for improvement)
      def bottom_patterns(limit: DEFAULT_LIMIT)
        patterns = filtered_patterns
                    .where("usage_count >= ?", MINIMUM_USAGE_THRESHOLD)
                    .includes(:category)
                    .order(success_rate: :asc, usage_count: :desc)
                    .limit(limit)

        patterns.map do |pattern|
          {
            id: pattern.id,
            pattern_type: pattern.pattern_type,
            pattern_value: pattern.pattern_value,
            category_name: pattern.category.name,
            category_color: pattern.category.color,
            usage_count: pattern.usage_count,
            success_count: pattern.success_count,
            success_rate: (pattern.success_rate * 100).round(2),
            confidence_weight: pattern.confidence_weight.round(2),
            improvement_potential: calculate_improvement_potential(pattern),
            user_created: pattern.user_created,
            active: pattern.active
          }
        end
      end

      # Pattern type distribution and effectiveness
      def pattern_type_analysis
        CategorizationPattern::PATTERN_TYPES.map do |type|
          patterns = filtered_patterns.by_type(type)
          total_usage = patterns.sum(:usage_count)
          total_success = patterns.sum(:success_count)

          {
            type: type,
            count: patterns.count,
            active_count: patterns.active.count,
            usage_count: total_usage,
            success_count: total_success,
            accuracy: total_usage > 0 ? (total_success.to_f / total_usage * 100).round(2) : 0,
            average_confidence: patterns.average(:confidence_weight)&.round(2) || 0
          }
        end
      end

      # Pattern usage heatmap data (hourly/daily breakdown) - optimized
      def usage_heatmap
        # Use optimized query with proper indexes
        begin
          feedbacks_data = filtered_feedbacks
            .joins(:expense)
            .select(
              "EXTRACT(hour FROM expenses.transaction_date)::integer as hour",
              "EXTRACT(dow FROM expenses.transaction_date)::integer as day_of_week",
              "COUNT(*) as count"
            )
            .group("hour", "day_of_week")
            .having("COUNT(*) > 0") # Filter out empty cells
            .index_by { |row| [ row.hour, row.day_of_week ] }
        rescue ActiveRecord::StatementInvalid => e
          Rails.logger.error "Heatmap query failed: #{e.message}"
          return {} # Return empty hash immediately on error
        end

        # Return empty hash if query failed or no data
        return {} if feedbacks_data.nil? || feedbacks_data.empty?

        # Transform into heatmap format
        heatmap_data = []
        (0..6).each do |day| # 0 = Sunday, 6 = Saturday
          (0..23).each do |hour|
            row = feedbacks_data[[ hour, day ]]
            heatmap_data << {
              day: day,
              hour: hour,
              count: row&.count || 0,
              day_name: Date::DAYNAMES[day],
              hour_label: "#{hour}:00"
            }
          end
        end

        heatmap_data
      end

      # Trend analysis over time with proper SQL safety
      def trend_analysis(interval: :daily)
        # Validate interval to prevent SQL injection
        validated_interval = validate_interval(interval)

        begin
          # Use Arel for safe SQL generation
          feedbacks = filtered_feedbacks

          # Build the query using Arel to prevent SQL injection
          date_format_sql = case validated_interval
          when :hourly
                             "DATE_TRUNC('hour', pattern_feedbacks.created_at)"
          when :daily
                             "DATE_TRUNC('day', pattern_feedbacks.created_at)"
          when :weekly
                             "DATE_TRUNC('week', pattern_feedbacks.created_at)"
          when :monthly
                             "DATE_TRUNC('month', pattern_feedbacks.created_at)"
          else
                             "DATE_TRUNC('day', pattern_feedbacks.created_at)"
          end

          feedbacks = feedbacks
                      .select(
                        "#{date_format_sql} as date_group",
                        "feedback_type",
                        "COUNT(*) as count"
                      )
                      .group("date_group", "feedback_type")
                      .order("date_group")

          # Transform data for chart consumption
          grouped_data = {}
          feedbacks.each do |row|
            date_group = row.date_group
            feedback_type = row.feedback_type
            count = row.count

            grouped_data[date_group] ||= {}
            grouped_data[date_group][feedback_type] = count
          end

          grouped_data.map do |date, counts|
            accepted = counts["accepted"] || 0
            rejected = counts["rejected"] || 0
            corrected = counts["corrected"] || 0
            total = accepted + rejected + corrected

            {
              date: date,
              accepted: accepted,
              rejected: rejected,
              corrected: corrected,
              total: total,
              accuracy: total > 0 ? (accepted.to_f / total * 100).round(2) : 0
            }
          end.sort_by { |item| item[:date] }
        rescue ActiveRecord::StatementInvalid => e
          Rails.logger.error "Trend analysis query failed: #{e.message}"
          []
        rescue StandardError => e
          Rails.logger.error "Unexpected error in trend analysis: #{e.message}"
          []
        end
      end

      # Recent pattern activity with preloading
      def recent_activity(limit: MAX_RECENT_ACTIVITY)
        PatternFeedback.includes(:expense, :category, :categorization_pattern)
                      .recent
                      .limit([ limit, MAX_RECENT_ACTIVITY ].min)
                      .map do |feedback|
          {
            id: feedback.id,
            created_at: feedback.created_at,
            feedback_type: feedback.feedback_type,
            expense_description: feedback.expense&.description,
            expense_amount: feedback.expense&.amount,
            category_name: feedback.category.name,
            category_color: feedback.category.color,
            pattern_type: feedback.categorization_pattern&.pattern_type,
            pattern_value: feedback.categorization_pattern&.pattern_value,
            was_correct: feedback.was_correct
          }
        end
      end

      # Learning progress metrics
      def learning_metrics
        events = PatternLearningEvent.includes(:category)
                                    .where(created_at: time_range)

        {
          total_learning_events: events.count,
          patterns_created: events.where(event_type: "pattern_created").count,
          patterns_improved: events.where(event_type: "pattern_improved").count,
          patterns_deactivated: events.where(event_type: "pattern_deactivated").count,
          average_confidence_gain: calculate_avg_confidence_gain(events),
          categories_improved: events.select(:category_id).distinct.count
        }
      end

      private

      def filtered_patterns
        patterns = CategorizationPattern.all
        patterns = patterns.where(category_id: category_filter) if category_filter
        patterns = patterns.where(pattern_type: pattern_type_filter) if pattern_type_filter
        patterns
      end

      def filtered_feedbacks
        feedbacks = PatternFeedback.where(created_at: time_range)
        feedbacks = feedbacks.joins(:categorization_pattern)
                            .where(categorization_patterns: { category_id: category_filter }) if category_filter
        feedbacks = feedbacks.joins(:categorization_pattern)
                            .where(categorization_patterns: { pattern_type: pattern_type_filter }) if pattern_type_filter
        feedbacks
      end

      def calculate_acceptance_rate(feedbacks)
        total = feedbacks.count
        return 0 if total == 0

        accepted = feedbacks.accepted.count
        (accepted.to_f / total * 100).round(2)
      end

      def calculate_improvement_potential(pattern)
        # Calculate how much the pattern could improve based on its current performance
        current_rate = pattern.success_rate

        potential = ((TARGET_SUCCESS_RATE - current_rate) * 100).round(2)
        potential > 0 ? potential : 0
      end

      def base_pattern_conditions
        conditions = {}
        conditions[:pattern_type] = pattern_type_filter if pattern_type_filter.present?
        conditions
      end

      def validate_interval(interval)
        # Ensure interval is a valid symbol from our whitelist
        interval = interval.to_sym if interval.respond_to?(:to_sym)
        INTERVAL_FORMATS.key?(interval) ? interval : :daily
      end

      def calculate_avg_confidence_gain(events)
        improved = events.where(event_type: "pattern_improved")
        return 0 if improved.empty?

        gains = improved.map do |event|
          (event.metadata["new_confidence"] || 0) - (event.metadata["old_confidence"] || 0)
        end.compact

        gains.any? ? (gains.sum.to_f / gains.size).round(2) : 0
      end
  end
end
