# frozen_string_literal: true

module BulkCategorization
  # Service to generate preview data before applying bulk categorization
  class PreviewService
    attr_reader :expenses, :category

    def initialize(expenses:, category:)
      @expenses = Array(expenses)
      @category = category
      @categorization_engine = Categorization::Engine.instance
    end

    def generate
      return empty_preview if expenses.empty? || category.nil?

      {
        category: category,
        expenses: expenses,
        expense_count: expenses.count,
        total_amount: expenses.sum(&:amount),
        average_confidence: calculate_average_confidence,
        confidence_breakdown: calculate_confidence_breakdown,
        date_range: {
          start: expenses.map(&:transaction_date).min,
          end: expenses.map(&:transaction_date).max
        },
        merchants: expenses.map(&:merchant_name).uniq.compact,
        impact: calculate_impact,
        warnings: generate_warnings
      }
    end

    private

    def empty_preview
      {
        category: nil,
        expenses: [],
        expense_count: 0,
        total_amount: 0,
        average_confidence: 0,
        warnings: [ "No expenses selected" ]
      }
    end

    def calculate_average_confidence
      confidences = expenses.map do |expense|
        result = @categorization_engine.categorize(expense, auto_update: false)

        if result.successful? && result.category == category
          result.confidence
        else
          0.5 # Default confidence for manual categorization
        end
      end

      return 0 if confidences.empty?

      (confidences.sum / confidences.count.to_f).round(3)
    end

    def calculate_confidence_breakdown
      results = expenses.map do |expense|
        result = @categorization_engine.categorize(expense, auto_update: false)

        confidence = if result.successful? && result.category == category
          result.confidence
        else
          0.5
        end

        case confidence
        when 0.85..1.0 then :high
        when 0.70...0.85 then :medium
        when 0.50...0.70 then :low
        else :very_low
        end
      end

      {
        high: results.count(:high),
        medium: results.count(:medium),
        low: results.count(:low),
        very_low: results.count(:very_low)
      }
    end

    def calculate_impact
      {
        budget_impact: calculate_budget_impact,
        pattern_confidence_increase: calculate_pattern_impact,
        new_patterns: count_new_patterns,
        affected_reports: affected_report_types
      }
    end

    def calculate_budget_impact
      # Check if this categorization affects any active budgets
      Budget.where(
        category: category,
        active: true
      ).where(
        "start_date <= ? AND (end_date IS NULL OR end_date >= ?)",
        Date.current,
        Date.current
      ).count
    end

    def calculate_pattern_impact
      # Estimate how much pattern confidence would increase
      existing_patterns = CategorizationPattern.where(
        category: category,
        pattern_type: "merchant",
        pattern_value: expenses.map(&:merchant_normalized).uniq.compact
      )

      return 0 if existing_patterns.empty?

      # Estimate confidence increase (simplified calculation)
      avg_current_confidence = existing_patterns.average(:success_rate) || 0
      estimated_increase = [ 5.0, (100 - avg_current_confidence * 100) * 0.1 ].min

      estimated_increase.round(1)
    end

    def count_new_patterns
      # Count how many new patterns would be created
      existing_merchants = CategorizationPattern.where(
        category: category,
        pattern_type: "merchant"
      ).pluck(:pattern_value)

      expense_merchants = expenses.map(&:merchant_normalized).uniq.compact

      (expense_merchants - existing_merchants).count
    end

    def affected_report_types
      reports = []
      reports << "Monthly Summary" if expenses.any? { |e| e.transaction_date.month == Date.current.month }
      reports << "Category Analysis"
      reports << "Merchant Spending" if expenses.map(&:merchant_name).uniq.count > 1
      reports
    end

    def generate_warnings
      warnings = []

      # Check for already categorized expenses
      already_categorized = expenses.select { |e| e.category.present? }
      if already_categorized.any?
        warnings << "#{already_categorized.count} expense(s) will be recategorized"
      end

      # Check for low confidence matches
      low_confidence_count = calculate_confidence_breakdown[:very_low]
      if low_confidence_count > 0
        warnings << "#{low_confidence_count} expense(s) have very low confidence for this category"
      end

      # Check for date range
      date_range = expenses.map(&:transaction_date)
      if date_range.max && date_range.min && (date_range.max - date_range.min).to_i > 90
        warnings << "Expenses span more than 90 days"
      end

      warnings
    end
  end
end
