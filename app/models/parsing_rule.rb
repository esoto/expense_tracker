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

    # Extract amount
    if amount_pattern.present?
      begin
        if amount_match = clean_content.match(Regexp.new(amount_pattern, Regexp::IGNORECASE))
          amount_str = amount_match[1] || amount_match[0]
          parsed_data[:amount] = extract_amount(amount_str)
        end
      rescue RegexpError => e
        Rails.logger.warn "Invalid amount pattern for #{bank_name}: #{e.message}"
      end
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
