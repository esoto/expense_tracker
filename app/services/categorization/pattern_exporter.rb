# frozen_string_literal: true

require "csv"

module Services::Categorization
  # Service for exporting all active CategorizationPatterns to CSV.
  #
  # Returns a CSV string with the following headers:
  #   pattern_type, pattern_value, category_name, confidence_weight,
  #   active, usage_count, success_rate
  class PatternExporter
    CSV_HEADERS = %w[
      pattern_type
      pattern_value
      category_name
      confidence_weight
      active
      usage_count
      success_rate
    ].freeze

    def export_to_csv
      CSV.generate(headers: true) do |csv|
        csv << CSV_HEADERS

        patterns_scope.each do |pattern|
          csv << build_row(pattern)
        end
      end
    end

    private

    def patterns_scope
      CategorizationPattern
        .active
        .includes(:category)
        .order(:pattern_type, :pattern_value)
    end

    def build_row(pattern)
      [
        pattern.pattern_type,
        pattern.pattern_value,
        pattern.category&.name,
        pattern.confidence_weight,
        pattern.active,
        pattern.usage_count,
        pattern.success_rate
      ]
    end
  end
end
