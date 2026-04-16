# frozen_string_literal: true

module Services::Categorization
  module Llm
    class PromptBuilder
      SYSTEM_INSTRUCTION = <<~INSTRUCTION.freeze
        You are a local business expert and expense categorizer.
        Given a bank transaction, search the internet to identify what type
        of business the merchant is, then return ONLY the category key from
        the list below. No explanation, no extra text — just the key.

        The merchant name comes from a bank statement and may be truncated
        or abbreviated. Use the location (city and country) to search for
        the actual business.

        If the merchant is a payment processor (e.g., PayPal, Tilo Pay, Sinpe Móvil)
        and the underlying purchase is unknown, return "uncategorized".

        If you cannot identify the business even after searching, return "uncategorized".
      INSTRUCTION

      # Extract city and country from BAC email body.
      # Format: "Ciudad y país: <city>, <country> Fecha: ..."
      COUNTRY_REGEX = /Ciudad y pa[ií]s:\s*(.+?)\s+Fecha:/i

      def build(expense:, correction_history: nil)
        prompt = build_base_prompt(expense)
        prompt += build_correction_note(correction_history) if correction_history
        prompt
      end

      private

      def build_base_prompt(expense)
        <<~PROMPT
          Categories:
          #{format_categories}

          Transaction:
          #{format_transaction(expense)}
        PROMPT
      end

      def format_transaction(expense)
        lines = []
        lines << "Bank: #{expense.bank_name}" if expense.bank_name?
        lines << "Merchant: #{expense.merchant_name}" if expense.merchant_name?
        lines << "Amount: #{format_amount(expense)}"

        city, country = extract_location(expense)
        lines << "Location: #{[ city, country ].compact.join(', ')}" if city || country

        lines.join("\n")
      end

      def format_amount(expense)
        currency = expense.currency&.upcase || "CRC"
        formatted = number_with_delimiter(expense.amount)
        "#{formatted} #{currency}"
      end

      def extract_location(expense)
        body = expense.email_body.presence || expense.raw_email_content.presence || expense.parsed_data&.to_s
        return [ nil, nil ] unless body

        match = body.match(COUNTRY_REGEX)
        return [ nil, nil ] unless match

        raw = match[1].strip
        if raw.include?(",")
          city, country = raw.split(",", 2).map(&:strip)
          country = nil if country == "Pais no Definido"
          [ city, country ]
        else
          country = raw == "Pais no Definido" ? nil : raw
          [ nil, country ]
        end
      end

      def format_categories
        @formatted_categories ||= begin
          categories = Category.where.not(i18n_key: [ nil, "" ])
                               .pluck(:i18n_key, :name)
          categories.map { |key, name| "- #{key} (#{name})" }.join("\n")
        end
      end

      def build_correction_note(correction_history)
        old_key = correction_history[:old]
        new_key = correction_history[:new]
        "\nNote: This merchant was previously categorized as #{old_key} but corrected to #{new_key} by the user.\n"
      end

      def number_with_delimiter(number)
        return "0" unless number

        whole, decimal = number.to_s.split(".")
        whole_with_delimiters = whole.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        decimal ? "#{whole_with_delimiters}.#{decimal}" : whole_with_delimiters
      end
    end
  end
end
