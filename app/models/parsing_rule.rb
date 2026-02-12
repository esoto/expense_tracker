class ParsingRule < ApplicationRecord
  # Associations
  has_many :email_accounts, primary_key: :bank_name, foreign_key: :bank_name

  # Validations
  validates :bank_name, presence: true
  validates :amount_pattern, presence: true
  validates :date_pattern, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_bank, ->(bank) { where(bank_name: bank) }

  # Instance methods
  def parse_email(email_content)
    parsed_data = {}
    
    # Ensure UTF-8 encoding and clean up invalid bytes
    clean_content = ensure_utf8(email_content)
    
    return parsed_data if clean_content.blank?

    # Fix encoding issues - ensure content is UTF-8
    if email_content.respond_to?(:force_encoding)
      email_content = email_content.dup
      unless email_content.encoding == Encoding::UTF_8
        email_content = email_content.force_encoding("UTF-8")
        # If it's not valid UTF-8, try to clean it up
        unless email_content.valid_encoding?
          email_content = email_content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        end
      end
    end

    Rails.logger.debug "[ParsingRule] Testing amount pattern: #{amount_pattern}"
    Rails.logger.debug "[ParsingRule] Email content preview: #{email_content.slice(0, 200)}"

    # Extract amount and detect currency
    if amount_match = email_content.match(Regexp.new(amount_pattern, Regexp::IGNORECASE))
      amount_str = amount_match[1] || amount_match[0]
      parsed_data[:amount] = extract_amount(amount_str)
      Rails.logger.debug "[ParsingRule] Found amount: #{parsed_data[:amount]}"

      # Detect currency from the full match or surrounding context
      full_match = amount_match[0]
      parsed_data[:currency] = detect_currency(full_match, email_content)
      Rails.logger.debug "[ParsingRule] Currency: #{parsed_data[:currency]}"
    else
      Rails.logger.debug "[ParsingRule] Amount pattern did not match"
    end

    # Extract date
    if date_pattern.present?
      begin
        if date_match = clean_content.match(Regexp.new(date_pattern, Regexp::IGNORECASE))
          date_str = date_match[1] || date_match[0]
          parsed_data[:transaction_date] = parse_date(date_str)
        end
      rescue RegexpError => e
        Rails.logger.warn "Invalid date pattern for #{bank_name}: #{e.message}"
      end
    end

    # Extract merchant
    if merchant_pattern.present?
      begin
        if merchant_match = clean_content.match(Regexp.new(merchant_pattern, Regexp::IGNORECASE | Regexp::MULTILINE))
          parsed_data[:merchant_name] = (merchant_match[1] || merchant_match[0]).strip
        end
      rescue RegexpError => e
        Rails.logger.warn "Invalid merchant pattern for #{bank_name}: #{e.message}"
      end
    end

    # Extract description
    if description_pattern.present?
      begin
        if desc_match = clean_content.match(Regexp.new(description_pattern, Regexp::IGNORECASE | Regexp::MULTILINE))
          parsed_data[:description] = (desc_match[1] || desc_match[0]).strip
        end
      rescue RegexpError => e
        Rails.logger.warn "Invalid description pattern for #{bank_name}: #{e.message}"
      end
    end

    parsed_data
  end

  def test_patterns(email_content)
    clean_content = ensure_utf8(email_content)
    
    {
      amount: test_pattern(amount_pattern, clean_content),
      date: test_pattern(date_pattern, clean_content),
      merchant: test_pattern(merchant_pattern, clean_content),
      description: test_pattern(description_pattern, clean_content)
    }
  end

  private
  
  def ensure_utf8(content)
    return "" if content.nil?
    
    # Try to force UTF-8 encoding and replace invalid characters
    if content.respond_to?(:encode)
      content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    else
      content.to_s
    end
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
    Rails.logger.warn "Encoding issue in parsing rule: #{e.message}"
    # Last resort: convert to ASCII and back
    content.to_s.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
  end

  def extract_amount(amount_str)
    # Remove currency symbols and spaces, but keep numbers, commas, and dots
    # Then handle different decimal separator conventions
    cleaned = amount_str.gsub(/[₡$\s]/, "")

    # Handle different number formats:
    # 25,500.00 (US format - comma as thousands, dot as decimal)
    # 25.500,00 (European format - dot as thousands, comma as decimal)
    if cleaned =~ /^\d{1,3}(,\d{3})*(\.\d+)?$/
      # US format: 1,234.56 or 25,500.00
      cleaned = cleaned.gsub(",", "")
    elsif cleaned =~ /^\d{1,3}(\.\d{3})*(,\d+)?$/
      # European format: 1.234,56
      cleaned = cleaned.gsub(".", "").gsub(",", ".")
    else
      # Fallback: assume comma is thousands separator
      cleaned = cleaned.gsub(",", "")
    end

    BigDecimal(cleaned)
  rescue ArgumentError, TypeError
    nil
  end

  def detect_currency(amount_context, full_text)
    # Check for currency symbols or codes in the amount context first
    return "crc" if amount_context =~ /₡|colones|CRC/i
    return "usd" if amount_context =~ /\$|USD|dollars?/i
    return "eur" if amount_context =~ /€|EUR|euros?/i

    # Check broader context if not found in immediate context
    # Look within 50 characters before and after the amount
    amount_index = full_text.index(amount_context)
    if amount_index
      context_start = [ amount_index - 50, 0 ].max
      context_end = [ amount_index + amount_context.length + 50, full_text.length ].min
      broader_context = full_text[context_start...context_end]

      return "crc" if broader_context =~ /₡|colones|CRC/i
      return "usd" if broader_context =~ /\$|USD|dollars?/i
      return "eur" if broader_context =~ /€|EUR|euros?/i
    end

    # Default based on bank if known
    case bank_name
    when "BAC", "BCR", "Banco Nacional"
      "crc"  # Costa Rican banks default to colones
    else
      "usd"  # Default to USD for international banks
    end
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

  def test_pattern(pattern, text)
    return nil if pattern.blank?

    match = text.match(Regexp.new(pattern, Regexp::IGNORECASE))
    return nil unless match

    {
      matched: true,
      full_match: match[0],
      captured_group: match[1],
      position: match.begin(0)
    }
  rescue RegexpError => e
    { error: e.message }
  end
end
