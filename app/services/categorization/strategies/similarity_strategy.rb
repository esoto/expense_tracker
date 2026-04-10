# frozen_string_literal: true

module Services::Categorization
  module Strategies
    # Layer 2 categorization strategy that uses PostgreSQL's pg_trgm
    # extension to find similar merchants in the categorization_vectors table.
    #
    # This strategy queries the GiST trigram index for fuzzy merchant name
    # matching, then applies confidence scoring based on similarity score,
    # occurrence count, and description keyword overlap.
    class SimilarityStrategy < BaseStrategy
      # Minimum similarity from pg_trgm for high confidence path
      HIGH_SIMILARITY_THRESHOLD = 0.6
      # Minimum similarity for medium confidence path
      MEDIUM_SIMILARITY_THRESHOLD = 0.4
      # Minimum occurrence_count to qualify for high confidence
      HIGH_OCCURRENCE_THRESHOLD = 2
      # Tolerance for considering two similarity scores "close"
      TIEBREAK_TOLERANCE = 0.1

      # @param logger [Logger]
      def initialize(logger: Rails.logger)
        @logger = logger
      end

      # @return [String]
      def layer_name
        "pg_trgm"
      end

      # Attempt to categorize an expense via pg_trgm similarity matching
      # against the categorization_vectors table.
      #
      # @param expense [Expense]
      # @param _options [Hash] unused — confidence thresholds are internal to this strategy
      # @return [CategorizationResult]
      def call(expense, _options = {})
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        normalized = normalize_merchant(expense)
        if normalized.blank?
          return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
        end

        scored_vectors = fetch_and_score_vectors(normalized)
        if scored_vectors.empty?
          return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
        end

        best = select_best_vector(scored_vectors, expense)
        confidence = calculate_confidence(best[:similarity], best[:vector])

        build_result(best[:vector], confidence, best[:similarity], duration_ms(start_time))
      end

      private

      def normalize_merchant(expense)
        return "" unless expense.merchant_name?

        MerchantNormalizer.normalize(expense.merchant_name)
      end

      # Single query: fetches vectors AND their similarity scores together.
      # Eliminates N+1 by selecting similarity() as a virtual attribute.
      def fetch_and_score_vectors(normalized)
        quoted = CategorizationVector.connection.quote(normalized)

        CategorizationVector
          .for_merchant(normalized)
          .select("categorization_vectors.*, similarity(merchant_normalized, #{quoted}) AS trgm_score")
          .includes(:category)
          .map { |v| { vector: v, similarity: v.trgm_score.to_f } }
      end

      def select_best_vector(scored_vectors, expense)
        scored_vectors.sort_by! { |s| -s[:similarity] }

        top = scored_vectors.first
        close_contenders = scored_vectors.select { |s| (top[:similarity] - s[:similarity]).abs < TIEBREAK_TOLERANCE }

        if close_contenders.size > 1 && expense.description?
          tiebreak_by_keywords(close_contenders, expense.description)
        else
          top
        end
      end

      def tiebreak_by_keywords(contenders, description)
        desc_words = description.downcase.split(/\s+/).to_set

        contenders.max_by do |entry|
          keywords = entry[:vector].description_keywords || []
          overlap = keywords.count { |kw| desc_words.include?(kw.downcase) }
          [ overlap, entry[:similarity] ]
        end
      end

      def calculate_confidence(similarity, vector)
        if similarity > HIGH_SIMILARITY_THRESHOLD && vector.occurrence_count > HIGH_OCCURRENCE_THRESHOLD
          0.7 + (similarity * 0.3)
        elsif similarity > MEDIUM_SIMILARITY_THRESHOLD
          0.4 + (similarity * 0.3)
        else
          similarity * 0.5
        end
      end

      def build_result(vector, confidence, similarity, processing_time_ms)
        CategorizationResult.new(
          category: vector.category,
          confidence: confidence,
          method: "pg_trgm_similarity",
          patterns_used: [ "vector:#{vector.merchant_normalized}" ],
          processing_time_ms: processing_time_ms,
          metadata: {
            similarity_score: similarity.round(4),
            vector_id: vector.id,
            occurrence_count: vector.occurrence_count,
            merchant_normalized: vector.merchant_normalized
          }
        )
      end

      def duration_ms(start_time)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      end
    end
  end
end
