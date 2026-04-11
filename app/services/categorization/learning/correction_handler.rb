# frozen_string_literal: true

module Services::Categorization
  module Learning
    # Orchestrates user corrections: updates vectors, records metrics,
    # and implements three-strike escalation for disputed merchants.
    #
    # Three-strike rule: when a merchant's old-category vector accumulates
    # >= 3 corrections within 30 days, confidence is dropped to 0.1 and
    # the LLM cache entry is purged so the merchant gets re-evaluated.
    class CorrectionHandler
      THREE_STRIKE_THRESHOLD = 3
      THREE_STRIKE_WINDOW = 30.days
      PENALIZED_CONFIDENCE = 0.1
      CORRECTION_CACHE_TTL = 90.days

      def initialize(logger: Rails.logger)
        @logger = logger
        @vector_updater = VectorUpdater.new(logger: logger)
        @metrics_recorder = MetricsRecorder.new(logger: logger)
      end

      # Process a user correction on an expense.
      #
      # @param expense [Expense] the corrected expense
      # @param old_category [Category] the previous (incorrect) category
      # @param new_category [Category] the user-chosen correct category
      # @return [Hash] { three_strike_triggered:, old_vector:, new_vector: }
      def handle_correction(expense:, old_category:, new_category:)
        vector_result = @vector_updater.record_correction(
          merchant: expense.merchant_name,
          old_category: old_category,
          new_category: new_category
        )

        @metrics_recorder.record_correction(
          expense: expense,
          corrected_to_category: new_category
        )

        old_vector = vector_result&.fetch(:old_vector, nil)
        new_vector = vector_result&.fetch(:new_vector, nil)

        three_strike = check_three_strike(old_vector, expense.merchant_name, old_category, new_category)

        {
          three_strike_triggered: three_strike,
          old_vector: old_vector,
          new_vector: new_vector
        }
      rescue => e
        @logger.error "[CorrectionHandler] handle_correction failed: #{e.class}: #{e.message}"
        { three_strike_triggered: false, old_vector: nil, new_vector: nil }
      end

      private

      def check_three_strike(old_vector, merchant_name, old_category, new_category)
        return false if old_vector.nil?

        # Must have enough corrections AND recent activity
        return false unless old_vector.correction_count >= THREE_STRIKE_THRESHOLD
        return false unless old_vector.last_seen_at.present? && old_vector.last_seen_at > THREE_STRIKE_WINDOW.ago

        apply_three_strike(old_vector, merchant_name, old_category, new_category)
        true
      end

      def apply_three_strike(old_vector, merchant_name, old_category, new_category)
        normalized = MerchantNormalizer.normalize(merchant_name)

        old_vector.update!(confidence: PENALIZED_CONFIDENCE)

        LlmCategorizationCacheEntry
          .where(merchant_normalized: normalized)
          .delete_all

        # Store correction context so LlmStrategy can pass it to PromptBuilder
        Rails.cache.write(
          "llm_correction:#{normalized}",
          { old: old_category.i18n_key, new: new_category.i18n_key },
          expires_in: CORRECTION_CACHE_TTL
        )

        @logger.info "[CorrectionHandler] Three-strike triggered for merchant=#{normalized}"
      end
    end
  end
end
