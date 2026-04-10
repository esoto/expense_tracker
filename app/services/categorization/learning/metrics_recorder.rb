# frozen_string_literal: true

module Services::Categorization
  module Learning
    # Records categorization metrics for every expense categorization.
    # Used by Engine to track per-layer performance, accuracy, and API costs.
    class MetricsRecorder
      def initialize(logger: Rails.logger)
        @logger = logger
      end

      # Record a categorization result.
      #
      # @param expense [Expense]
      # @param result [CategorizationResult]
      # @param layer_name [String] "pattern", "pg_trgm", "haiku", or "manual"
      # @param api_cost [Float] cost of the API call (0 for local layers)
      def record(expense:, result:, layer_name:, api_cost: 0)
        CategorizationMetric.create!(
          expense: expense,
          layer_used: layer_name,
          confidence: result.successful? ? result.confidence : nil,
          category: result.successful? ? result.category : nil,
          was_corrected: false,
          processing_time_ms: result.processing_time_ms,
          api_cost: api_cost
        )
      rescue => e
        @logger.error "[MetricsRecorder] Failed to record metric: #{e.class}: #{e.message}"
      end

      # Record a user correction on a previously categorized expense.
      # Updates the most recent metric for the given expense.
      #
      # @param expense [Expense]
      # @param corrected_to_category [Category]
      def record_correction(expense:, corrected_to_category:)
        metric = CategorizationMetric
          .where(expense: expense)
          .order(created_at: :desc)
          .first

        return unless metric

        hours = ((Time.current - metric.created_at) / 1.hour).round

        metric.update!(
          was_corrected: true,
          corrected_to_category: corrected_to_category,
          time_to_correction_hours: hours
        )
      rescue => e
        @logger.error "[MetricsRecorder] Failed to record correction: #{e.class}: #{e.message}"
      end
    end
  end
end
