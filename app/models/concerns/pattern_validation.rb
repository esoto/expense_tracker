# frozen_string_literal: true

# Concern for validating and normalizing categorization patterns
# Provides comprehensive validation rules to ensure data quality and prevent performance issues
module PatternValidation
  extend ActiveSupport::Concern

  # Constants for validation rules
  MIN_PATTERN_LENGTH = 2
  MAX_PATTERN_LENGTH = 255
  MAX_REGEX_LENGTH = 100
  DANGEROUS_REGEX_PATTERNS = [
    /\([^)]*[+*]\)[+*]/,     # (a+)+ or (a*)*
    /\[[^\]]*[+*]\][+*]/,    # [a+]+ or [a*]*
    /(\w+[+*])+[+*]/,        # a++ or a**
    /\(.+[+*].+\)[+*]/,      # Complex nested quantifiers
    /\(\?\<[!=]/,            # Lookbehind assertions (can be slow)
    /\{(\d+,)?\d*\}\{/       # Multiple consecutive quantifiers
  ].freeze

  TIME_PATTERN_VALUES = %w[
    morning afternoon evening night
    weekend weekday
    business_hours after_hours
  ].freeze

  included do
    # Callbacks for normalization
    before_validation :normalize_pattern_value

    # Additional validations
    validate :validate_pattern_format
    validate :validate_pattern_complexity
    validate :check_for_duplicate_patterns
  end

  private

  # Normalize pattern values based on type
  def normalize_pattern_value
    return if pattern_value.blank?

    case pattern_type
    when "merchant", "keyword", "description"
      # Normalize text patterns
      self.pattern_value = pattern_value.strip.downcase
      # Remove excessive whitespace
      self.pattern_value = pattern_value.gsub(/\s+/, " ")
    when "amount_range"
      # Normalize amount ranges (ensure proper format)
      normalize_amount_range
    when "time"
      # Normalize time patterns
      self.pattern_value = pattern_value.strip.downcase
    when "regex"
      # Don't normalize regex patterns (case-sensitive)
      self.pattern_value = pattern_value.strip
    end
  end

  # Normalize amount range format
  def normalize_amount_range
    return unless pattern_value.match?(/\A-?\d+(\.\d+)?--?\d+(\.\d+)?\z/)

    # Parse and reformat with consistent decimal places
    parts = pattern_value.split(/(?<=\d)-(?=-?\d)/)
    return unless parts.size == 2

    min_val = format_amount(parts[0].to_f)
    max_val = format_amount(parts[1].to_f)

    self.pattern_value = "#{min_val}-#{max_val}"
  end

  # Format amount with two decimal places
  def format_amount(amount)
    sprintf("%.2f", amount)
  end

  # Validate pattern format based on type
  def validate_pattern_format
    case pattern_type
    when "merchant", "keyword", "description"
      validate_text_pattern
    when "amount_range"
      validate_amount_range_pattern
    when "time"
      validate_time_pattern
    when "regex"
      validate_regex_pattern
    end
  end

  # Validate text patterns
  def validate_text_pattern
    return if pattern_value.blank?

    # Check minimum length
    if pattern_value.length < MIN_PATTERN_LENGTH
      errors.add(:pattern_value, "must be at least #{MIN_PATTERN_LENGTH} characters long")
    end

    # Check maximum length
    if pattern_value.length > MAX_PATTERN_LENGTH
      errors.add(:pattern_value, "must be no more than #{MAX_PATTERN_LENGTH} characters long")
    end

    # Check for invalid characters (control characters, etc.)
    if pattern_value.match?(/[\x00-\x1F\x7F]/)
      errors.add(:pattern_value, "contains invalid control characters")
    end

    # Warn about patterns that are too generic
    generic_patterns = %w[the a an of in on at to for and or]
    if generic_patterns.include?(pattern_value.downcase)
      errors.add(:pattern_value, "is too generic to be useful for categorization")
    end
  end

  # Validate amount range patterns
  def validate_amount_range_pattern
    return if pattern_value.blank?

    # Check format
    unless pattern_value.match?(/\A-?\d+(\.\d{1,2})?--?\d+(\.\d{1,2})?\z/)
      errors.add(:pattern_value, "must be in format 'min-max' (e.g., '10.00-50.00')")
      return
    end

    # Parse and validate range
    parts = pattern_value.split(/(?<=\d)-(?=-?\d)/)
    if parts.size != 2
      errors.add(:pattern_value, "invalid amount range format")
      return
    end

    min_val = parts[0].to_f
    max_val = parts[1].to_f

    # Validate range logic
    if min_val >= max_val
      errors.add(:pattern_value, "minimum amount must be less than maximum amount")
    end

    # Warn about extremely large ranges
    if (max_val - min_val) > 10_000
      errors.add(:pattern_value, "range is too broad (difference > 10,000)")
    end

    # Warn about negative amounts if unexpected
    if min_val < 0 && pattern_type == "amount_range"
      # This is just a warning in metadata, not an error
      self.metadata ||= {}
      self.metadata["has_negative_amounts"] = true
    end
  end

  # Validate time patterns
  def validate_time_pattern
    return if pattern_value.blank?

    # Check against allowed values or time range format
    time_range_format = /\A\d{1,2}:\d{2}-\d{1,2}:\d{2}\z/

    unless TIME_PATTERN_VALUES.include?(pattern_value) || pattern_value.match?(time_range_format)
      errors.add(:pattern_value,
        "must be one of: #{TIME_PATTERN_VALUES.join(', ')}, or a time range (e.g., '09:00-17:00')")
    end

    # Validate time range if applicable
    if pattern_value.match?(time_range_format)
      validate_time_range_logic
    end
  end

  # Validate time range logic
  def validate_time_range_logic
    start_time_str, end_time_str = pattern_value.split("-")
    start_hour, start_min = start_time_str.split(":").map(&:to_i)
    end_hour, end_min = end_time_str.split(":").map(&:to_i)

    # Validate hour and minute ranges
    if start_hour > 23 || end_hour > 23
      errors.add(:pattern_value, "hours must be between 0 and 23")
    end

    if start_min > 59 || end_min > 59
      errors.add(:pattern_value, "minutes must be between 0 and 59")
    end
  rescue
    errors.add(:pattern_value, "invalid time range format")
  end

  # Validate regex patterns
  def validate_regex_pattern
    return if pattern_value.blank?

    # Check length
    if pattern_value.length > MAX_REGEX_LENGTH
      errors.add(:pattern_value, "regex pattern is too long (max #{MAX_REGEX_LENGTH} characters)")
      return
    end

    # Check for dangerous patterns (ReDoS vulnerability)
    DANGEROUS_REGEX_PATTERNS.each do |dangerous_pattern|
      if pattern_value.match?(dangerous_pattern)
        errors.add(:pattern_value, "contains potentially dangerous regex pattern (ReDoS vulnerability)")
        return
      end
    end

    # Try to compile the regex
    begin
      regex = Regexp.new(pattern_value)

      # Test regex performance with a sample string
      test_string = "a" * 100
      Timeout.timeout(0.1) do
        test_string.match?(regex)
      end
    rescue RegexpError => e
      errors.add(:pattern_value, "invalid regular expression: #{e.message}")
    rescue Timeout::Error
      errors.add(:pattern_value, "regex pattern is too complex (performance issue)")
    end
  end

  # Validate overall pattern complexity
  def validate_pattern_complexity
    return if pattern_value.blank?

    # Add metadata about pattern complexity
    self.metadata ||= {}

    case pattern_type
    when "regex"
      # Calculate regex complexity score
      complexity_score = calculate_regex_complexity
      self.metadata["complexity_score"] = complexity_score

      if complexity_score > 10
        errors.add(:pattern_value, "pattern is too complex (complexity score: #{complexity_score})")
      end
    when "merchant", "keyword"
      # Check for special characters that might cause issues
      special_char_count = pattern_value.scan(/[^a-zA-Z0-9\s]/).count
      if special_char_count > 5
        self.metadata["high_special_chars"] = true
      end
    end
  end

  # Calculate complexity score for regex patterns
  def calculate_regex_complexity
    score = 0

    # Count quantifiers
    score += pattern_value.scan(/[*+?]/).count * 2
    score += pattern_value.scan(/\{[\d,]+\}/).count * 3

    # Count groups
    score += pattern_value.scan(/\(/).count

    # Count alternations
    score += pattern_value.scan(/\|/).count * 2

    # Count character classes
    score += pattern_value.scan(/\[/).count

    # Penalize nested quantifiers heavily
    score += pattern_value.scan(/[*+]\s*[*+]/).count * 10

    score
  end

  # Check for duplicate patterns
  def check_for_duplicate_patterns
    return if pattern_value.blank?
    return unless new_record? || pattern_value_changed?

    # Skip duplicate check if pattern contains invalid characters
    return if pattern_value.match?(/[\x00-\x1F\x7F]/)

    # Check for exact duplicates within the same category
    scope = self.class.where(
      category_id: category_id,
      pattern_type: pattern_type,
      pattern_value: pattern_value
    )

    scope = scope.where.not(id: id) if persisted?

    if scope.exists?
      errors.add(:pattern_value, "already exists for this category and pattern type")
    end

    # Check for similar patterns (fuzzy matching)
    check_for_similar_patterns if pattern_type.in?(%w[merchant keyword description])
  end

  # Check for similar patterns using fuzzy matching
  def check_for_similar_patterns
    return unless respond_to?(:category_id)

    similar_patterns = self.class
      .where(category_id: category_id, pattern_type: pattern_type)
      .where.not(id: id)
      .where("similarity(pattern_value, ?) > 0.8", pattern_value)
      .limit(5)

    if similar_patterns.any?
      self.metadata ||= {}
      self.metadata["similar_patterns"] = similar_patterns.pluck(:pattern_value)

      # Only warn, don't error - similar patterns might be intentional
      if similar_patterns.count >= 3
        self.metadata["high_similarity_warning"] = true
      end
    end
  rescue ActiveRecord::StatementInvalid
    # Similarity function might not be available in all environments
    Rails.logger.debug "Similarity check skipped - pg_trgm extension may not be installed"
  end
end
