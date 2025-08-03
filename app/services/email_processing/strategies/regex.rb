module EmailProcessing
  module Strategies
    class Regex < Base
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
        if parsing_rule.merchant_pattern.present?
          if merchant_match = email_content.match(Regexp.new(parsing_rule.merchant_pattern, Regexp::IGNORECASE))
            parsed_data[:merchant_name] = merchant_match[1] || merchant_match[0]
          end
        end

        # Extract description
        if parsing_rule.description_pattern.present?
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

      def parse_date(date_str)
        # Clean up the date string
        date_str = date_str.strip

        # Handle Spanish abbreviated months
        spanish_months = {
          "Ene" => "Jan", "Feb" => "Feb", "Mar" => "Mar", "Abr" => "Apr",
          "May" => "May", "Jun" => "Jun", "Jul" => "Jul", "Ago" => "Aug",
          "Sep" => "Sep", "Oct" => "Oct", "Nov" => "Nov", "Dic" => "Dec"
        }

        # Convert Spanish months to English for parsing
        spanish_months.each do |spanish, english|
          date_str = date_str.gsub(spanish, english)
        end

        # Try multiple date formats common in Costa Rica
        formats = [
          "%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d",
          "%d/%m/%Y %H:%M", "%d-%m-%Y %H:%M",
          "%d de %B de %Y", "%d %B %Y",
          "%b %d, %Y, %H:%M",  # "Aug 1, 2025, 14:16"
          "%b %d, %Y"          # "Aug 1, 2025"
        ]

        formats.each do |format|
          begin
            return Date.strptime(date_str, format)
          rescue ArgumentError
            next
          end
        end

        # Fallback to chronic gem for natural language parsing
        Chronic.parse(date_str)&.to_date
      rescue
        nil
      end
    end
  end
end