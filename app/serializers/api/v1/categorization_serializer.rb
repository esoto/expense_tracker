# frozen_string_literal: true

module Api
  module V1
    # Serializer for categorization suggestions and feedback
    class CategorizationSerializer
      attr_reader :suggestion, :options

      def initialize(suggestion, options = {})
        @suggestion = suggestion
        @options = options
      end

      def as_json
        {
          category: category_attributes,
          confidence: suggestion[:confidence]&.round(3),
          reason: suggestion[:reason],
          type: suggestion[:type],
          pattern_id: pattern_id
        }
      end

      def self.collection(suggestions, options = {})
        suggestions.map { |suggestion| new(suggestion, options).as_json }
      end

      def self.feedback(feedback_record)
        {
          id: feedback_record.id,
          expense_id: feedback_record.expense_id,
          category_id: feedback_record.category_id,
          category: {
            id: feedback_record.category_id,
            name: feedback_record.category&.name
          },
          pattern_id: feedback_record.categorization_pattern_id,
          feedback_type: feedback_record.feedback_type,
          was_correct: feedback_record.was_correct,
          confidence_score: feedback_record.confidence_score&.round(3),
          created_at: feedback_record.created_at.iso8601
        }
      end

      private

      def category_attributes
        category = suggestion[:category]
        return nil unless category

        {
          id: category.id,
          name: category.name,
          color: category.color,
          parent_id: category.parent_id
        }
      end

      def pattern_id
        return nil unless suggestion[:pattern]

        case suggestion[:pattern]
        when CategorizationPattern
          suggestion[:pattern].id
        when CompositePattern
          "composite_#{suggestion[:pattern].id}"
        else
          nil
        end
      end
    end
  end
end
