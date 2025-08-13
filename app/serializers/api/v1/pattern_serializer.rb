# frozen_string_literal: true

module Api
  module V1
    # Serializer for CategorizationPattern API responses
    class PatternSerializer
      attr_reader :pattern, :options

      def initialize(pattern, options = {})
        @pattern = pattern
        @options = options
      end

      def as_json
        base_attributes.tap do |json|
          json[:category] = category_attributes if include_category?
          json[:statistics] = statistics_attributes if include_statistics?
          json[:metadata] = pattern.metadata if include_metadata?
        end
      end

      def self.collection(patterns, options = {})
        # Preload associations if needed to avoid N+1 queries
        patterns = patterns.includes(:category) if patterns.respond_to?(:includes)

        patterns.map { |pattern| new(pattern, options).as_json }
      end

      private

      def base_attributes
        {
          id: pattern.id,
          pattern_type: pattern.pattern_type,
          pattern_value: pattern.pattern_value,
          confidence_weight: pattern.confidence_weight.round(2),
          active: pattern.active,
          user_created: pattern.user_created,
          created_at: pattern.created_at.iso8601,
          updated_at: pattern.updated_at.iso8601
        }
      end

      def category_attributes
        return nil unless pattern.category

        {
          id: pattern.category.id,
          name: pattern.category.name,
          color: pattern.category.color
        }
      end

      def statistics_attributes
        {
          usage_count: pattern.usage_count,
          success_count: pattern.success_count,
          success_rate: (pattern.success_rate || 0).round(3),
          effective_confidence: pattern.effective_confidence.round(3)
        }
      end

      def include_category?
        options[:include_category] != false
      end

      def include_statistics?
        options[:include_statistics] != false
      end

      def include_metadata?
        options[:include_metadata] == true
      end
    end
  end
end
