# frozen_string_literal: true

module Services::Categorization
  # Shared merchant name normalization for pg_trgm similarity matching.
  #
  # Used by SimilarityStrategy (Layer 2) and VectorUpdater (B2) to ensure
  # consistent normalization when querying and updating categorization_vectors.
  module MerchantNormalizer
    module_function

    # Normalize a merchant name for pg_trgm comparison.
    #
    # Strips whitespace, downcases, removes non-alphanumeric characters
    # (except spaces), and collapses multiple spaces.
    #
    # @param name [String, nil] the merchant name to normalize
    # @return [String] normalized name, or empty string if nil/blank
    def normalize(name)
      return "" if name.nil?

      name.downcase
          .strip
          .gsub(/[^a-z0-9\s]/, "")
          .gsub(/\s+/, " ")
          .strip
    end
  end
end
