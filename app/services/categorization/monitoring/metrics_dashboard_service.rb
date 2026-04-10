# frozen_string_literal: true

module Services::Categorization
  module Monitoring
    # Aggregates categorization metrics for the admin dashboard.
    # Provides overview stats and per-layer performance breakdowns.
    class MetricsDashboardService
      def overview(period: 30.days)
        metrics = CategorizationMetric.recent(period)
        total = metrics.count

        return empty_overview if total.zero?

        {
          accuracy: percentage(metrics.uncorrected.count, total),
          fallback_rate: percentage(metrics.for_layer("haiku").count, total),
          correction_rate: percentage(metrics.corrected.count, total),
          api_spend: metrics.sum(:api_cost).to_f
        }
      end

      def layer_performance(period: 30.days)
        metrics = CategorizationMetric.recent(period)

        metrics.group(:layer_used).pluck(:layer_used).map do |layer|
          layer_metrics = metrics.for_layer(layer)
          total = layer_metrics.count

          next if total.zero?

          corrected_count = layer_metrics.corrected.count
          correct_count = total - corrected_count

          {
            layer: layer,
            total: total,
            correct: correct_count,
            corrected: corrected_count,
            accuracy: percentage(correct_count, total),
            avg_confidence: layer_metrics.average(:confidence).to_f.round(2),
            avg_time: layer_metrics.average(:processing_time_ms).to_f.round(2)
          }
        end.compact
      end

      private

      def empty_overview
        { accuracy: 0.0, fallback_rate: 0.0, correction_rate: 0.0, api_spend: 0.0 }
      end

      def percentage(numerator, denominator)
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator * 100).round(2)
      end
    end
  end
end
