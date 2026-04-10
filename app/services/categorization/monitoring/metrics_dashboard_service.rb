# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Aggregates categorization metrics for the admin dashboard.
    # Uses single-query conditional aggregation for efficiency.
    class MetricsDashboardService
      def overview(period: 30.days)
        result = CategorizationMetric.recent(period).pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(CASE WHEN was_corrected = false THEN 1 END)"),
          Arel.sql("COUNT(CASE WHEN layer_used = 'haiku' THEN 1 END)"),
          Arel.sql("COUNT(CASE WHEN was_corrected = true THEN 1 END)"),
          Arel.sql("COALESCE(SUM(api_cost), 0)")
        )

        total, uncorrected, haiku, corrected, spend = result
        return empty_overview if total.zero?

        {
          empty: false,
          accuracy: percentage(uncorrected, total),
          fallback_rate: percentage(haiku, total),
          correction_rate: percentage(corrected, total),
          api_spend: spend.to_f
        }
      end

      def layer_performance(period: 30.days)
        CategorizationMetric.recent(period)
          .group(:layer_used)
          .pluck(
            :layer_used,
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(CASE WHEN was_corrected = true THEN 1 END)"),
            Arel.sql("ROUND(AVG(confidence)::numeric, 2)"),
            Arel.sql("ROUND(AVG(processing_time_ms)::numeric, 2)")
          ).map do |layer, total, corrected, avg_conf, avg_time|
            correct = total - corrected
            {
              layer: layer,
              total: total,
              correct: correct,
              corrected: corrected,
              accuracy: percentage(correct, total),
              avg_confidence: avg_conf.to_f,
              avg_time: avg_time.to_f
            }
          end
      end

      def problem_merchants(period: 30.days)
        CategorizationVector
          .includes(:category)
          .where(correction_count: 2.., last_seen_at: period.ago..)
          .order(correction_count: :desc)
          .map do |vector|
            {
              merchant: vector.merchant_normalized,
              category_name: vector.category.display_name,
              correction_count: vector.correction_count,
              last_seen_at: vector.last_seen_at
            }
          end
      end

      private

      def empty_overview
        { empty: true, accuracy: 0.0, fallback_rate: 0.0, correction_rate: 0.0, api_spend: 0.0 }
      end

      def percentage(numerator, denominator)
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator * 100).round(2)
      end
    end
  end
end
