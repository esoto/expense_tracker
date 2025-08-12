# frozen_string_literal: true

module BulkCategorization
  # Service to group similar uncategorized expenses for bulk processing
  # Uses merchant similarity, amounts, and dates to create logical groups
  class GroupingService
    SIMILARITY_THRESHOLD = 0.7
    DATE_WINDOW_DAYS = 30
    MIN_GROUP_SIZE = 2
    MAX_GROUPS = 50

    attr_reader :expenses, :options

    def initialize(expenses, options = {})
      @expenses = expenses
      @options = default_options.merge(options)
      # Use factory instead of singleton for better testability
      @categorization_engine = options[:categorization_engine] || Categorization::EngineFactory.default
    end

    # Main method to group expenses by similarity
    def group_by_similarity
      return [] if expenses.blank?

      Rails.logger.info "Grouping #{expenses.count} expenses"
      groups = []

      # First, group by exact merchant match
      merchant_groups = group_by_merchant

      # Then, find fuzzy matches for remaining expenses
      remaining = expenses - merchant_groups.flat_map { |g| g[:expenses] }
      fuzzy_groups = group_by_fuzzy_matching(remaining)

      # Combine and enrich groups with suggestions
      all_groups = (merchant_groups + fuzzy_groups)
      enrich_groups_with_suggestions(all_groups)

      # Sort by confidence and size
      all_groups.sort_by { |g| [ -g[:confidence], -g[:expenses].count ] }
                .first(MAX_GROUPS)
    end

    # Group expenses by specific criteria
    def group_by(criteria)
      case criteria
      when :merchant
        group_by_merchant
      when :amount
        group_by_amount_range
      when :date
        group_by_date_range
      when :pattern
        group_by_pattern_match
      else
        raise ArgumentError, "Unknown grouping criteria: #{criteria}"
      end
    end

    private

    def default_options
      {
        similarity_threshold: SIMILARITY_THRESHOLD,
        date_window: DATE_WINDOW_DAYS,
        min_group_size: MIN_GROUP_SIZE,
        include_suggestions: true,
        max_groups: MAX_GROUPS
      }
    end

    def group_by_merchant
      groups = []

      # Group by normalized merchant name
      expenses_by_merchant = expenses.group_by(&:merchant_normalized)

      expenses_by_merchant.each do |merchant, merchant_expenses|
        next if merchant.blank?
        next if merchant_expenses.count < options[:min_group_size]

        groups << build_group(
          expenses: merchant_expenses,
          grouping_key: merchant,
          grouping_type: :exact_merchant,
          confidence: calculate_merchant_confidence(merchant_expenses)
        )
      end

      groups
    end

    def group_by_fuzzy_matching(remaining_expenses)
      return [] if remaining_expenses.empty?

      # Use PostgreSQL trigram similarity for efficient fuzzy matching
      # This replaces the O(n²) algorithm with database-level similarity search
      groups = []
      processed = Set.new

      # Use batch processing to find similar merchants using pg_trgm
      remaining_expenses.each do |expense|
        next if processed.include?(expense.id)
        next if expense.merchant_normalized.blank?

        # Use database query with trigram similarity instead of in-memory calculation
        similar_expenses = find_similar_expenses_optimized(expense, remaining_expenses, processed)

        if similar_expenses.count >= options[:min_group_size]
          similar_expenses.each { |e| processed.add(e.id) }

          groups << build_group(
            expenses: similar_expenses,
            grouping_key: generate_group_key(similar_expenses),
            grouping_type: :fuzzy_match,
            confidence: calculate_group_confidence(similar_expenses)
          )
        end
      end

      groups
    end

    def group_by_amount_range
      ranges = [
        { min: 0, max: 10_000, label: "Small (< ₡10,000)" },
        { min: 10_000, max: 50_000, label: "Medium (₡10,000 - ₡50,000)" },
        { min: 50_000, max: 200_000, label: "Large (₡50,000 - ₡200,000)" },
        { min: 200_000, max: Float::INFINITY, label: "Very Large (> ₡200,000)" }
      ]

      groups = []

      ranges.each do |range|
        range_expenses = expenses.select do |e|
          e.amount >= range[:min] && e.amount < range[:max]
        end

        next if range_expenses.count < options[:min_group_size]

        groups << build_group(
          expenses: range_expenses,
          grouping_key: range[:label],
          grouping_type: :amount_range,
          confidence: 0.5 # Lower confidence for amount-based grouping
        )
      end

      groups
    end

    def group_by_date_range
      groups = []

      # Group by month
      expenses_by_month = expenses.group_by do |e|
        e.transaction_date.beginning_of_month
      end

      expenses_by_month.each do |month, month_expenses|
        next if month_expenses.count < options[:min_group_size]

        groups << build_group(
          expenses: month_expenses,
          grouping_key: month.strftime("%B %Y"),
          grouping_type: :date_range,
          confidence: 0.4 # Lower confidence for date-based grouping
        )
      end

      groups
    end

    def group_by_pattern_match
      groups = []
      patterns = CategorizationPattern.active.frequently_used

      patterns.each do |pattern|
        matching_expenses = expenses.select { |e| pattern.matches?(e) }

        next if matching_expenses.count < options[:min_group_size]

        groups << build_group(
          expenses: matching_expenses,
          grouping_key: "Pattern: #{pattern.pattern_value}",
          grouping_type: :pattern_match,
          confidence: pattern.confidence_weight,
          suggested_category: pattern.category
        )
      end

      groups
    end

    # Optimized version using PostgreSQL trigram similarity
    def find_similar_expenses_optimized(reference_expense, all_expenses, processed_ids)
      return [ reference_expense ] if reference_expense.merchant_normalized.blank?

      # Get IDs of unprocessed expenses from the provided collection
      unprocessed_ids = all_expenses.reject { |e| processed_ids.include?(e.id) }.map(&:id)

      # Use PostgreSQL trigram similarity for efficient matching
      # This query uses the gin index on merchant_normalized for fast similarity search
      similar_ids = Expense
        .where(id: unprocessed_ids)
        .where.not(merchant_normalized: nil)
        .where(
          "similarity(merchant_normalized, ?) >= ?",
          reference_expense.merchant_normalized,
          options[:similarity_threshold]
        )
        .pluck(:id)

      # Return the matching expenses from our collection
      all_expenses.select { |e| similar_ids.include?(e.id) }
    end

    # Legacy method kept for compatibility but deprecated
    def find_similar_expenses(reference_expense, candidates)
      Rails.logger.warn "Using deprecated find_similar_expenses method - use find_similar_expenses_optimized instead"
      similar = []

      candidates.each do |candidate|
        similarity = calculate_similarity(reference_expense, candidate)

        if similarity >= options[:similarity_threshold]
          similar << candidate
        end
      end

      similar
    end

    def calculate_similarity(expense1, expense2)
      scores = []

      # Merchant similarity (highest weight)
      if expense1.merchant_name.present? && expense2.merchant_name.present?
        merchant_sim = string_similarity(
          expense1.merchant_normalized || expense1.merchant_name,
          expense2.merchant_normalized || expense2.merchant_name
        )
        scores << merchant_sim * 0.5
      end

      # Description similarity
      if expense1.description.present? && expense2.description.present?
        desc_sim = string_similarity(expense1.description, expense2.description)
        scores << desc_sim * 0.3
      end

      # Amount similarity (within 20%)
      amount_diff = (expense1.amount - expense2.amount).abs
      amount_avg = (expense1.amount + expense2.amount) / 2.0
      amount_sim = 1.0 - [ amount_diff / amount_avg, 1.0 ].min
      scores << amount_sim * 0.1

      # Date proximity (within date window)
      days_apart = (expense1.transaction_date - expense2.transaction_date).abs
      date_sim = 1.0 - [ days_apart.to_f / options[:date_window], 1.0 ].min
      scores << date_sim * 0.1

      scores.sum
    end

    def string_similarity(str1, str2)
      return 0.0 if str1.blank? || str2.blank?

      # Normalize strings
      s1 = str1.downcase.strip
      s2 = str2.downcase.strip

      return 1.0 if s1 == s2

      # Use Levenshtein distance for similarity
      distance = levenshtein_distance(s1, s2)
      max_length = [ s1.length, s2.length ].max

      1.0 - (distance.to_f / max_length)
    end

    def levenshtein_distance(str1, str2)
      m = str1.length
      n = str2.length

      return n if m == 0
      return m if n == 0

      # Create distance matrix
      d = Array.new(m + 1) { Array.new(n + 1) }

      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }

      (1..n).each do |j|
        (1..m).each do |i|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,    # deletion
            d[i][j - 1] + 1,    # insertion
            d[i - 1][j - 1] + cost # substitution
          ].min
        end
      end

      d[m][n]
    end

    def enrich_groups_with_suggestions(groups)
      return groups unless options[:include_suggestions]

      groups.each do |group|
        next if group[:suggested_category].present?

        # Get categorization suggestion for the first expense in the group
        representative = group[:expenses].first
        result = @categorization_engine.categorize(representative)

        if result.successful?
          group[:suggested_category] = result.category
          group[:suggestion_confidence] = result.confidence
          group[:confidence] = [ group[:confidence], result.confidence ].max
        end
      end

      groups
    end

    def build_group(expenses:, grouping_key:, grouping_type:, confidence:, suggested_category: nil)
      {
        id: SecureRandom.uuid,
        grouping_key: grouping_key,
        grouping_type: grouping_type,
        expenses: expenses,
        expense_ids: expenses.map(&:id),
        count: expenses.count,
        total_amount: expenses.sum(&:amount),
        date_range: {
          start: expenses.map(&:transaction_date).min,
          end: expenses.map(&:transaction_date).max
        },
        confidence: confidence,
        suggested_category: suggested_category,
        merchants: expenses.map(&:merchant_name).uniq.compact,
        created_at: Time.current
      }
    end

    def generate_group_key(expenses)
      # Generate a descriptive key for the group
      merchants = expenses.map(&:merchant_name).compact.uniq

      if merchants.count == 1
        merchants.first
      elsif merchants.count <= 3
        merchants.join(", ")
      else
        "#{merchants.first(2).join(', ')} and #{merchants.count - 2} others"
      end
    end

    def calculate_merchant_confidence(expenses)
      # Higher confidence for exact merchant matches
      base_confidence = 0.9

      # Adjust based on group size
      size_factor = [ expenses.count / 10.0, 1.0 ].min

      base_confidence * (0.8 + 0.2 * size_factor)
    end

    # Optimized confidence calculation using database aggregation
    def calculate_group_confidence(expenses)
      return 0.5 if expenses.empty?

      # For groups with same merchant, use high confidence
      merchants = expenses.map(&:merchant_normalized).compact.uniq
      return 0.9 if merchants.size == 1

      # For mixed groups, calculate confidence based on group characteristics
      # Avoid O(n²) comparison by using statistical measures
      base_confidence = 0.7

      # Adjust based on group size (larger groups = higher confidence)
      size_factor = [ expenses.count / 10.0, 1.0 ].min

      # Adjust based on date proximity
      date_range = (expenses.map(&:transaction_date).max - expenses.map(&:transaction_date).min).days
      date_factor = date_range <= options[:date_window] ? 0.1 : 0.0

      (base_confidence + size_factor * 0.2 + date_factor).clamp(0.0, 1.0)
    end

    # Legacy method kept for compatibility
    def calculate_fuzzy_confidence(expenses)
      calculate_group_confidence(expenses)
    end
  end
end
