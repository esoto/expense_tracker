# frozen_string_literal: true

class CategorizationService
  def categorize_expense(expense)
    return { category: nil, confidence: 0, method: "no_match", error: "Invalid expense" } if expense.nil?

    begin
      # Check user preferences first if expense has an email_account
      if expense.email_account.present? && expense.merchant_name?
        user_pref = UserCategoryPreference.find_by(
          email_account: expense.email_account,
          context_type: "merchant",
          context_value: expense.merchant_name.downcase
        )
        if user_pref
          # Calculate confidence based on usage_count and preference_weight
          confidence = [ 0.7 + (user_pref.usage_count * 0.01) + (user_pref.preference_weight * 0.05), 1.0 ].min
          update_expense(expense, user_pref.category, confidence, "user_preference")
          return {
            category: user_pref.category,
            confidence: confidence,
            method: "user_preference",
            patterns_used: []
          }
        end
      end

      # Find matching patterns
      pattern_matches = find_pattern_matches(expense)
      composite_matches = find_composite_matches(expense)

      # Combine and score matches
      all_matches = combine_matches(pattern_matches, composite_matches)

      if all_matches.empty?
        return { category: nil, confidence: 0, method: "no_match", patterns_used: [] }
      end

      # Sort by confidence score
      sorted_matches = all_matches.sort_by { |m| -m[:score] }
      best_match = sorted_matches.first

      # Update expense if confidence is high enough
      if best_match[:score] > 0.5
        update_expense(expense, best_match[:category], best_match[:score], best_match[:method])
      end

      {
        category: best_match[:category],
        confidence: best_match[:score],
        method: best_match[:method],
        patterns_used: best_match[:patterns],
        alternative_categories: sorted_matches[1..2].compact.map do |match|
          { category: match[:category], confidence: match[:score] }
        end
      }
    rescue StandardError => e
      Rails.logger.error "Categorization error: #{e.message}"
      { category: nil, confidence: 0, method: "error", error: "Database error: #{e.message}" }
    end
  end

  def bulk_categorize(expenses)
    # Preload all active patterns for efficiency
    patterns = CategorizationPattern.active.includes(:category)
    composites = CompositePattern.active.includes(:category)

    expenses.map do |expense|
      categorize_expense(expense)
    end
  end

  def record_feedback(expense, category, was_correct)
    # Find patterns that were used
    patterns = CategorizationPattern.active.select do |pattern|
      pattern.matches?(expense)
    end

    patterns.each do |pattern|
      if pattern.category == category
        pattern.record_usage(was_correct)
      else
        # Pattern matched but pointed to wrong category - always record as failure
        pattern.record_usage(false)
      end
    end

    # Create learning event
    PatternLearningEvent.create!(
      expense: expense,
      category: category,
      was_correct: was_correct,
      pattern_used: patterns.map(&:pattern_value).join(", "),
      confidence_score: calculate_confidence(patterns),
      context_data: {
        merchant: expense.merchant_name,
        amount: expense.amount,
        description: expense.description
      }
    )
  end

  def suggest_new_patterns
    # Find frequently uncategorized merchants
    uncategorized = Expense.where(category_id: nil)
                          .group(:merchant_name)
                          .count
                          .sort_by { |_, count| -count }
                          .first(20)

    uncategorized.map do |(merchant, count)|
      # Try to find similar categorized merchants
      similar = find_similar_merchants(merchant)
      suggested_category = similar.first&.category

      {
        merchant: merchant,
        frequency: count,
        suggested_category: suggested_category,
        similar_merchants: similar.map(&:merchant_name)
      }
    end
  end

  def pattern_performance_report
    patterns = CategorizationPattern.all

    high_performing = patterns.select { |p| p.success_rate > 0.8 && p.usage_count > 10 }
    low_performing = patterns.select { |p| p.success_rate < 0.5 && p.usage_count > 10 }

    {
      high_performing: high_performing,
      low_performing: low_performing,
      summary: {
        total_patterns: patterns.count,
        average_success_rate: patterns.map(&:success_rate).sum.to_f / patterns.count
      },
      recommendations: {
        deactivate: low_performing.reject(&:user_created)
      }
    }
  end

  private

  def find_pattern_matches(expense)
    matches = []

    CategorizationPattern.active.each do |pattern|
      if pattern.matches?(expense)
        score = pattern.effective_confidence
        matches << {
          category: pattern.category,
          score: score,
          method: "pattern_matching",
          patterns: [ "#{pattern.pattern_type}:#{pattern.pattern_value}" ]
        }
      end
    end

    matches
  end

  def find_composite_matches(expense)
    matches = []

    CompositePattern.active.each do |composite|
      next unless composite.matches?(expense)

      score = composite.effective_confidence
      matches << {
        category: composite.category,
        score: score,
        method: "composite_pattern",
        patterns: [ "composite:#{composite.name}" ]
      }
    end

    matches
  end

  def combine_matches(pattern_matches, composite_matches)
    all_matches = pattern_matches + composite_matches

    # Group by category and combine scores
    grouped = all_matches.group_by { |m| m[:category] }

    grouped.map do |category, matches|
      combined_score = calculate_combined_score(matches.map { |m| m[:score] })
      all_patterns = matches.flat_map { |m| m[:patterns] }

      {
        category: category,
        score: combined_score,
        method: matches.first[:method],
        patterns: all_patterns
      }
    end
  end

  def calculate_combined_score(scores)
    return 0 if scores.empty?

    # Sort scores in descending order to prioritize higher confidence patterns
    sorted_scores = scores.sort.reverse

    # For multiple patterns matching the same category, we boost confidence
    # Use the highest score with a small boost for additional matches
    max_score = sorted_scores.first
    boost = sorted_scores[1..-1].sum { |s| s * 0.1 } # 10% boost per additional match

    # Return the boosted score, clamped to 0-1 range
    (max_score + boost).clamp(0, 1)
  end

  def calculate_confidence(patterns)
    return 0 if patterns.empty?

    patterns.map(&:effective_confidence).max
  end

  def update_expense(expense, category, confidence, method)
    expense.update!(
      category: category,
      auto_categorized: true,
      categorization_confidence: confidence,
      categorization_method: method
    )
  end

  def find_similar_merchants(merchant_name)
    # Simple similarity based on shared words
    words = merchant_name.downcase.split(/\W+/)

    Expense.joins(:category)
           .where.not(category_id: nil)
           .where("LOWER(merchant_name) LIKE ANY (ARRAY[?])", words.map { |w| "%#{w}%" })
           .distinct
           .limit(5)
  end
end
