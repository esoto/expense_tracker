# frozen_string_literal: true

module Services::BulkCategorization
  # Service to generate AI-powered categorization suggestions for expenses
  class SuggestionService
    attr_reader :expenses, :options

    def initialize(expenses:, options: {}, engine: nil)
      @expenses = Array(expenses)
      @options = default_options.merge(options)
      # Use dependency injection - create new engine if not provided
      @categorization_engine = engine || Categorization::Engine.create
    end

    def generate_suggestions
      return [] if expenses.empty?

      suggestions = []

      # Get categorization suggestions for each expense
      expenses.each do |expense|
        result = @categorization_engine.categorize(
          expense,
          include_alternatives: true,
          auto_update: false
        )

        if result.successful?
          suggestions << build_suggestion(expense, result)
        end
      end

      # Aggregate and rank suggestions
      aggregate_suggestions(suggestions)
    end

    private

    def default_options
      {
        max_suggestions: 5,
        min_confidence: 0.5,
        include_alternatives: true
      }
    end

    def build_suggestion(expense, result)
      {
        expense_id: expense.id,
        primary_category: result.category,
        confidence: result.confidence,
        confidence_level: result.confidence_level,
        method: result.method,
        patterns_used: result.patterns_used,
        alternatives: format_alternatives(result.alternative_categories)
      }
    end

    def format_alternatives(alternatives)
      return [] unless alternatives.present?

      alternatives.map do |alt|
        {
          category: alt[:category],
          confidence: alt[:confidence],
          confidence_level: confidence_level(alt[:confidence])
        }
      end
    end

    def confidence_level(confidence)
      case confidence
      when 0.85..1.0 then :high
      when 0.70...0.85 then :medium
      when 0.50...0.70 then :low
      else :very_low
      end
    end

    def aggregate_suggestions(suggestions)
      # Group by suggested category
      grouped = suggestions.group_by { |s| s[:primary_category]&.id }

      # Calculate aggregated suggestions
      aggregated = grouped.map do |category_id, group|
        next if category_id.nil?

        category = group.first[:primary_category]

        {
          category: category,
          expense_count: group.size,
          average_confidence: group.sum { |g| g[:confidence] } / group.size.to_f,
          min_confidence: group.map { |g| g[:confidence] }.min,
          max_confidence: group.map { |g| g[:confidence] }.max,
          expense_ids: group.map { |g| g[:expense_id] },
          methods_used: group.map { |g| g[:method] }.uniq,
          confidence_distribution: calculate_confidence_distribution(group)
        }
      end.compact

      # Sort by average confidence and expense count
      aggregated.sort_by { |s| [ -s[:average_confidence], -s[:expense_count] ] }
               .first(options[:max_suggestions])
    end

    def calculate_confidence_distribution(group)
      {
        high: group.count { |g| g[:confidence_level] == :high },
        medium: group.count { |g| g[:confidence_level] == :medium },
        low: group.count { |g| g[:confidence_level] == :low },
        very_low: group.count { |g| g[:confidence_level] == :very_low }
      }
    end
  end
end
