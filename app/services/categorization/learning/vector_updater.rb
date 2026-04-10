# frozen_string_literal: true

module Services::Categorization
  module Learning
    # Maintains categorization_vectors from expense categorization events.
    #
    # Called by the categorization pipeline after each expense is categorized,
    # and when users correct a categorization. Keeps vector occurrence counts,
    # correction counts, and description keywords up to date for the
    # similarity-based categorization layer.
    class VectorUpdater
      MAX_KEYWORDS = 20

      def initialize(logger: Rails.logger)
        @logger = logger
      end

      # Create or update a categorization vector for a merchant+category pair.
      #
      # @param merchant [String] raw merchant name (will be normalized)
      # @param category [Category] the category associated with this merchant
      # @param description_keywords [Array<String>] keywords from expense description
      # @return [CategorizationVector, nil] the upserted vector, or nil if inputs invalid
      def upsert(merchant:, category:, description_keywords: [])
        normalized = normalize(merchant)
        return nil if normalized.blank? || category.nil?

        vector = CategorizationVector.find_or_initialize_by(
          merchant_normalized: normalized,
          category: category
        )

        if vector.new_record?
          vector.assign_attributes(
            occurrence_count: 1,
            correction_count: 0,
            confidence: 0.5,
            description_keywords: Array(description_keywords).first(MAX_KEYWORDS),
            last_seen_at: Time.current
          )
        else
          vector.occurrence_count += 1
          vector.last_seen_at = Time.current
          vector.description_keywords = merge_keywords(vector.description_keywords, description_keywords)
        end

        vector.save!
        vector
      rescue => e
        @logger.error "[VectorUpdater] upsert failed for merchant=#{merchant.inspect} category=#{category&.id}: #{e.class}: #{e.message}"
        nil
      end

      # Record a user correction: bump correction_count on the old vector,
      # upsert a vector for the new category.
      #
      # @param merchant [String] raw merchant name
      # @param old_category [Category] the category being corrected from
      # @param new_category [Category] the category being corrected to
      # @return [Hash, nil] { old_vector:, new_vector: } or nil if inputs invalid
      def record_correction(merchant:, old_category:, new_category:)
        normalized = normalize(merchant)
        return nil if normalized.blank?

        old_vector = CategorizationVector.find_by(
          merchant_normalized: normalized,
          category: old_category
        )

        old_vector&.increment!(:correction_count)

        new_vector = upsert(merchant: merchant, category: new_category)

        { old_vector: old_vector, new_vector: new_vector }
      rescue => e
        @logger.error "[VectorUpdater] record_correction failed for merchant=#{merchant.inspect}: #{e.class}: #{e.message}"
        nil
      end

      private

      def normalize(merchant)
        Services::Categorization::MerchantNormalizer.normalize(merchant)
      end

      def merge_keywords(existing, incoming)
        (Array(existing) | Array(incoming)).first(MAX_KEYWORDS)
      end
    end
  end
end
