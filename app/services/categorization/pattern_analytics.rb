# frozen_string_literal: true

module Services::Categorization
  # Service for generating analytics and statistics about CategorizationPatterns.
  #
  # generate_statistics — overall counts, averages, type/category breakdowns
  # performance_over_time — daily pattern match counts over the last 30 days
  class PatternAnalytics
    PERFORMANCE_WINDOW_DAYS = 30

    # Generate a summary statistics hash.
    #
    # @return [Hash] with keys:
    #   :total_patterns       [Integer]
    #   :active_count         [Integer]
    #   :inactive_count       [Integer]
    #   :avg_success_rate     [Float]  0–100 percentage
    #   :patterns_by_type     [Hash]   pattern_type => count
    #   :top_categories       [Array]  up to 10 categories sorted by pattern count desc
    def generate_statistics
      {
        total_patterns:   CategorizationPattern.count,
        active_count:     CategorizationPattern.active.count,
        inactive_count:   CategorizationPattern.inactive.count,
        avg_success_rate: calculate_avg_success_rate,
        patterns_by_type: patterns_by_type,
        top_categories:   top_categories
      }
    end

    # Return daily pattern usage counts over the last 30 days.
    #
    # Uses PatternFeedback records when available; falls back to an empty
    # structure when the table has no data.
    #
    # @return [Hash] with keys:
    #   :daily   [Array<Hash>]  each entry: { date: "YYYY-MM-DD", total: N, correct: N, incorrect: N }
    #   :weekly  [Array<Hash>]  each entry: { week_start: "YYYY-MM-DD", total: N }
    #   :summary [Hash]         { total_matches: N, avg_daily: Float }
    def performance_over_time
      daily_data  = build_daily_data
      weekly_data = aggregate_weekly(daily_data)
      total       = daily_data.sum { |d| d[:total] }

      {
        daily:   daily_data,
        weekly:  weekly_data,
        summary: {
          total_matches: total,
          avg_daily:     (total.to_f / PERFORMANCE_WINDOW_DAYS).round(2)
        }
      }
    end

    private

    def calculate_avg_success_rate
      scope = CategorizationPattern.where("usage_count > 0")
      return 0.0 if scope.empty?

      total_usage    = scope.sum(:usage_count).to_f
      total_success  = scope.sum(:success_count).to_f
      return 0.0 if total_usage.zero?

      ((total_success / total_usage) * 100).round(2)
    end

    def patterns_by_type
      CategorizationPattern
        .group(:pattern_type)
        .count
        .transform_keys(&:to_s)
    end

    def top_categories
      Category
        .joins(:categorization_patterns)
        .group("categories.id", "categories.name")
        .select(
          "categories.id",
          "categories.name",
          "COUNT(categorization_patterns.id) AS pattern_count",
          "AVG(categorization_patterns.success_rate) AS avg_success_rate"
        )
        .order("pattern_count DESC")
        .limit(10)
        .map do |cat|
          {
            id:               cat.id,
            name:             cat.name,
            pattern_count:    cat.pattern_count.to_i,
            avg_success_rate: (cat.avg_success_rate.to_f * 100).round(2)
          }
        end
    end

    def build_daily_data
      window_start = PERFORMANCE_WINDOW_DAYS.days.ago.to_date
      window_end   = Date.current

      # Pre-aggregate feedback counts grouped by date and correctness
      feedback_counts = fetch_feedback_counts(window_start, window_end)

      # Build one entry per day in the window
      (window_start..window_end).map do |date|
        date_str  = date.to_s
        correct   = feedback_counts.dig(date_str, true)  || 0
        incorrect = feedback_counts.dig(date_str, false) || 0

        {
          date:      date_str,
          total:     correct + incorrect,
          correct:   correct,
          incorrect: incorrect
        }
      end
    end

    def fetch_feedback_counts(window_start, window_end)
      return {} unless defined?(PatternFeedback) && PatternFeedback.table_exists?

      PatternFeedback
        .where(created_at: window_start.beginning_of_day..window_end.end_of_day)
        .group(Arel.sql("DATE(created_at)"), :was_correct)
        .count
        .each_with_object({}) do |((date, was_correct), count), hash|
          hash[date.to_s] ||= {}
          hash[date.to_s][was_correct] = count
        end
    rescue StandardError => e
      Rails.logger.warn "[PatternAnalytics] Could not fetch feedback counts: #{e.message}"
      {}
    end

    def aggregate_weekly(daily_data)
      daily_data
        .group_by { |d| Date.parse(d[:date]).beginning_of_week.to_s }
        .map do |week_start, days|
          {
            week_start: week_start,
            total:      days.sum { |d| d[:total] }
          }
        end
        .sort_by { |w| w[:week_start] }
    end
  end
end
