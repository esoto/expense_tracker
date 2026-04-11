# frozen_string_literal: true

module Services::Categorization
  module Llm
    class ResponseParser
      FIXED_LLM_CONFIDENCE = 0.85

      def parse(response_text:)
        return empty_result(response_text) if response_text.nil? || response_text.strip.empty?

        cleaned_key = extract_category_key(response_text)
        category = Category.find_by(i18n_key: cleaned_key)

        if category
          { category: category, confidence: FIXED_LLM_CONFIDENCE, raw_response: response_text }
        else
          { category: nil, confidence: 0.0, raw_response: response_text }
        end
      end

      private

      def extract_category_key(response_text)
        # Strip leading/trailing whitespace, take the first non-empty line, downcase
        response_text.strip.split("\n").first.strip.downcase
      end

      def empty_result(response_text)
        { category: nil, confidence: 0.0, raw_response: response_text }
      end
    end
  end
end
