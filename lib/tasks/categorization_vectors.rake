# frozen_string_literal: true

namespace :categorization do
  desc "Backfill categorization_vectors from existing expenses"
  task backfill_vectors: :environment do
    logger = Logger.new($stdout)
    logger.info "[BackfillVectors] Starting backfill..."

    scope = Expense.where.not(category_id: nil).where.not(merchant_name: [ nil, "" ])
    total = scope.count
    logger.info "[BackfillVectors] Found #{total} categorizable expenses"

    processed = 0

    # Group by normalized merchant + category to batch-create vectors
    scope.select(:merchant_name, :category_id, :description)
         .group_by { |e| [ e.merchant_name, e.category_id ] }
         .each do |(merchant_name, category_id), expenses|
      normalized = Services::Categorization::MerchantNormalizer.normalize(merchant_name)
      next if normalized.blank?

      category = Category.find_by(id: category_id)
      next unless category

      keywords = extract_keywords(expenses.map(&:description))

      vector = CategorizationVector.find_or_initialize_by(
        merchant_normalized: normalized,
        category_id: category_id
      )

      if vector.new_record?
        vector.assign_attributes(
          occurrence_count: expenses.size,
          correction_count: 0,
          confidence: 0.5,
          description_keywords: keywords,
          last_seen_at: Time.current
        )
      else
        # Idempotent: set occurrence_count to group size (not increment)
        # so re-running produces the same result
        vector.occurrence_count = expenses.size
        vector.description_keywords = keywords
        vector.last_seen_at = Time.current
      end

      vector.save!
      processed += expenses.size

      if (processed % 500).zero? || processed == total
        logger.info "[BackfillVectors] Progress: #{processed}/#{total} expenses processed"
      end
    end

    vector_count = CategorizationVector.count
    logger.info "[BackfillVectors] Done. #{vector_count} vectors in database. #{processed} expenses processed."
  end
end

# Extract top 5 most common meaningful keywords from descriptions.
#
# @param descriptions [Array<String>] expense descriptions
# @return [Array<String>] top 5 keywords
def extract_keywords(descriptions)
  word_counts = Hash.new(0)

  descriptions.each do |desc|
    next if desc.blank?

    desc.downcase
        .gsub(/[^a-z0-9\s]/, "")
        .split
        .reject { |w| w.length < 3 }
        .each { |word| word_counts[word] += 1 }
  end

  word_counts.sort_by { |_word, count| -count }
             .first(5)
             .map(&:first)
end
