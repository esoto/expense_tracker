# frozen_string_literal: true

module Services::Categorization
  module Llm
    class PromptBuilder
      SYSTEM_INSTRUCTION = <<~INSTRUCTION.freeze
        You are an expense categorizer. Given an expense, return the single best
        matching category from the list below. Return ONLY the category key,
        nothing else.
      INSTRUCTION

      def build(expense:, correction_history: nil)
        prompt = build_base_prompt(expense)
        prompt += build_correction_note(correction_history) if correction_history
        prompt
      end

      private

      def build_base_prompt(expense)
        <<~PROMPT
          #{SYSTEM_INSTRUCTION}
          Categories:
          #{format_categories}

          Expense:
          Merchant: #{expense.merchant_name}
          Description: #{expense.description}
          Amount: #{expense.amount} #{expense.currency}
        PROMPT
      end

      def format_categories
        @formatted_categories ||= begin
          category_keys = Category.where.not(i18n_key: [ nil, "" ]).pluck(:i18n_key)
          category_keys.map { |key| "- #{key}" }.join("\n")
        end
      end

      def build_correction_note(correction_history)
        old_key = correction_history[:old]
        new_key = correction_history[:new]
        "\nNote: This merchant was previously categorized as #{old_key} but corrected to #{new_key} by the user.\n"
      end
    end
  end
end
