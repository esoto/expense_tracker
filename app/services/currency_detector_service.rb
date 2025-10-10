module Services
  class CurrencyDetectorService
  # Currency detection patterns
  USD_PATTERNS = %w[$ usd dollar].freeze
  EUR_PATTERNS = %w[€ eur euro].freeze

  # Default currency for Costa Rican banks
  DEFAULT_CURRENCY = "crc".freeze

  def initialize(email_content: nil)
    @email_content = email_content
  end

  def detect_currency(parsed_data = {})
    currency_text = build_detection_text(parsed_data)

    if contains_usd?(currency_text)
      "usd"
    elsif contains_eur?(currency_text)
      "eur"
    else
      DEFAULT_CURRENCY
    end
  end

  def apply_currency_to_expense(expense, parsed_data = {})
    currency = detect_currency(parsed_data)

    case currency
    when "usd"
      expense.usd!
    when "eur"
      expense.eur!
    when "crc"
      expense.crc!
    else
      expense.crc! # Fallback to default
    end
  end

  private

  def build_detection_text(parsed_data)
    content_parts = [
      @email_content,
      parsed_data[:amount],
      parsed_data[:description],
      parsed_data[:merchant_name]
    ]

    content_parts.compact.join(" ").downcase
  end

  def contains_usd?(text)
    USD_PATTERNS.any? { |pattern| text.include?(pattern) }
  end

  def contains_eur?(text)
    EUR_PATTERNS.any? { |pattern| text.include?(pattern) }
  end
  end
end
