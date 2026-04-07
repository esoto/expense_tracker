module Services::EmailProcessing
  module Strategies
    class Regex < Base
      include Services::EmailProcessing::DateParsingHelper

      def parse_email(email_content)
        parsed_data = {}

        # Extract amount
        if amount_match = email_content.match(Regexp.new(parsing_rule.amount_pattern, Regexp::IGNORECASE))
          amount_str = amount_match[1] || amount_match[0]
          parsed_data[:amount] = extract_amount(amount_str)
        end

        # Extract date
        if date_match = email_content.match(Regexp.new(parsing_rule.date_pattern, Regexp::IGNORECASE))
          date_str = date_match[1] || date_match[0]
          parsed_data[:transaction_date] = parse_date(date_str)
        end

        # Extract merchant
        if parsing_rule.merchant_pattern?
          if merchant_match = email_content.match(Regexp.new(parsing_rule.merchant_pattern, Regexp::IGNORECASE))
            parsed_data[:merchant_name] = merchant_match[1] || merchant_match[0]
          end
        end

        # Extract description
        if parsing_rule.description_pattern?
          if desc_match = email_content.match(Regexp.new(parsing_rule.description_pattern, Regexp::IGNORECASE))
            parsed_data[:description] = desc_match[1] || desc_match[0]
          end
        end

        parsed_data
      end

      def can_parse?(email_content)
        return false if email_content.blank?

        # Check if the required patterns match
        amount_match = email_content.match(Regexp.new(parsing_rule.amount_pattern, Regexp::IGNORECASE))
        date_match = email_content.match(Regexp.new(parsing_rule.date_pattern, Regexp::IGNORECASE))

        amount_match.present? && date_match.present?
      rescue RegexpError
        false
      end

      private

      def extract_amount(amount_str)
        return nil if amount_str.blank?

        # Remove currency symbols and convert to decimal
        cleaned = amount_str.gsub(/[₡$,\s]/, "").gsub(",", ".")
        BigDecimal(cleaned)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
