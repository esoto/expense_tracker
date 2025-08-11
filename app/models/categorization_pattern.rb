# frozen_string_literal: true

# CategorizationPattern represents a pattern-based rule for automatically categorizing expenses.
# Each pattern has a type (merchant, keyword, description, amount_range, regex, time) and a value
# that is matched against expense attributes to suggest a category.
#
# The pattern tracks its performance through usage_count, success_count, and success_rate
# to continuously improve categorization accuracy.
class CategorizationPattern < ApplicationRecord
  # Constants
  PATTERN_TYPES = %w[merchant keyword description amount_range regex time].freeze
  DEFAULT_CONFIDENCE_WEIGHT = 1.0
  MIN_CONFIDENCE_WEIGHT = 0.1
  MAX_CONFIDENCE_WEIGHT = 5.0

  # Associations
  belongs_to :category
  has_many :pattern_feedbacks, dependent: :destroy
  has_many :expenses, through: :pattern_feedbacks

  # Validations
  validates :pattern_type, presence: true, inclusion: { in: PATTERN_TYPES }
  validates :pattern_value, presence: true
  validates :confidence_weight, 
            numericality: { 
              greater_than_or_equal_to: MIN_CONFIDENCE_WEIGHT,
              less_than_or_equal_to: MAX_CONFIDENCE_WEIGHT 
            }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
  validates :success_count, numericality: { greater_than_or_equal_to: 0 }
  validates :success_rate, 
            numericality: { 
              greater_than_or_equal_to: 0.0, 
              less_than_or_equal_to: 1.0 
            }
  
  validate :validate_pattern_value_format
  validate :success_count_not_greater_than_usage_count

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :user_created, -> { where(user_created: true) }
  scope :system_created, -> { where(user_created: false) }
  scope :by_type, ->(type) { where(pattern_type: type) }
  scope :high_confidence, -> { where("confidence_weight >= ?", 2.0) }
  scope :successful, -> { where("success_rate >= ?", 0.7) }
  scope :frequently_used, -> { where("usage_count >= ?", 10) }
  scope :ordered_by_success, -> { order(success_rate: :desc, usage_count: :desc) }

  # Callbacks
  before_save :calculate_success_rate

  # Public Methods
  
  # Record usage of this pattern and whether it was successful
  def record_usage(was_successful)
    self.usage_count += 1
    self.success_count += 1 if was_successful
    calculate_success_rate
    save!
  end

  # Check if pattern matches the given text or expense
  def matches?(text_or_options)
    # Handle both string and hash/expense parameters
    if text_or_options.is_a?(Hash)
      expense = text_or_options[:expense]
      text = text_or_options[:merchant_name] || text_or_options[:description]
    elsif text_or_options.respond_to?(:merchant_name)
      # It's an expense object
      expense = text_or_options
      text = case pattern_type
             when "merchant"
               expense.merchant_name
             when "description", "keyword", "regex"
               expense.description || expense.merchant_name
             else
               nil
             end
    else
      text = text_or_options
      expense = nil
    end
    
    case pattern_type
    when "merchant", "keyword", "description"
      return false if text.blank?
      matches_text_pattern?(text)
    when "regex"
      return false if text.blank?
      matches_regex_pattern?(text)
    when "amount_range"
      # If expense object, use its amount; otherwise use the raw value for testing
      value = expense ? expense.amount : text_or_options
      matches_amount_range?(value)
    when "time"
      # If expense object, use its transaction_date; otherwise use the raw value for testing
      value = expense ? expense.transaction_date : text_or_options
      matches_time_pattern?(value)
    else
      false
    end
  end

  # Get the effective confidence for this pattern
  def effective_confidence
    base_confidence = confidence_weight
    
    # Adjust based on success rate if we have enough data
    if usage_count >= 5
      base_confidence * (0.5 + (success_rate * 0.5))
    else
      base_confidence * 0.7 # Lower confidence for patterns with little data
    end
  end

  # Deactivate pattern if it's performing poorly
  def check_and_deactivate_if_poor_performance
    return unless usage_count >= 20
    return unless success_rate < 0.3
    return if user_created # Don't deactivate user-created patterns
    
    update!(active: false)
  end

  private

  def calculate_success_rate
    self.success_rate = if usage_count.positive?
                          success_count.to_f / usage_count
                        else
                          0.0
                        end
  end

  def validate_pattern_value_format
    case pattern_type
    when "amount_range"
      validate_amount_range_format
    when "regex"
      validate_regex_format
    when "time"
      validate_time_format
    end
  end

  def validate_amount_range_format
    return if pattern_value.blank?
    
    unless pattern_value.match?(/\A\d+(\.\d{1,2})?-\d+(\.\d{1,2})?\z/)
      errors.add(:pattern_value, "must be in format 'min-max' (e.g., '10.00-50.00')")
    end
    
    if pattern_value.include?("-")
      min_val, max_val = pattern_value.split("-").map(&:to_f)
      if min_val >= max_val
        errors.add(:pattern_value, "minimum must be less than maximum")
      end
    end
  end

  def validate_regex_format
    return if pattern_value.blank?
    
    Regexp.new(pattern_value)
  rescue RegexpError
    errors.add(:pattern_value, "must be a valid regular expression")
  end

  def validate_time_format
    return if pattern_value.blank?
    
    # Accept formats like "morning", "evening", "weekend", "weekday", or specific hours "09:00-17:00"
    valid_formats = %w[morning afternoon evening night weekend weekday]
    time_range_format = /\A\d{1,2}:\d{2}-\d{1,2}:\d{2}\z/
    
    unless valid_formats.include?(pattern_value) || pattern_value.match?(time_range_format)
      errors.add(:pattern_value, "must be a valid time pattern")
    end
  end

  def success_count_not_greater_than_usage_count
    return if success_count <= usage_count
    
    errors.add(:success_count, "cannot be greater than usage count")
  end

  def matches_text_pattern?(text)
    normalized_text = text.downcase.strip
    normalized_pattern = pattern_value.downcase.strip
    
    # Simple substring matching for now
    normalized_text.include?(normalized_pattern)
  end

  def matches_regex_pattern?(text)
    regex = Regexp.new(pattern_value, Regexp::IGNORECASE)
    text.match?(regex)
  rescue RegexpError
    false
  end

  def matches_amount_range?(value)
    return false unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+(\.\d+)?\z/)
    
    amount = value.to_f
    min_val, max_val = pattern_value.split("-").map(&:to_f)
    
    amount >= min_val && amount <= max_val
  end

  def matches_time_pattern?(datetime_or_string)
    return false if datetime_or_string.blank?
    
    datetime = parse_datetime(datetime_or_string)
    return false unless datetime
    
    case pattern_value
    when "morning"
      datetime.hour.between?(6, 11)
    when "afternoon"
      datetime.hour.between?(12, 16)
    when "evening"
      datetime.hour.between?(17, 20)
    when "night"
      datetime.hour.between?(21, 23) || datetime.hour.between?(0, 5)
    when "weekend"
      datetime.saturday? || datetime.sunday?
    when "weekday"
      !datetime.saturday? && !datetime.sunday?
    else
      matches_time_range?(datetime)
    end
  end

  def matches_time_range?(datetime)
    return false unless pattern_value.include?("-")
    
    start_time, end_time = pattern_value.split("-").map { |t| Time.parse(t).hour }
    datetime.hour.between?(start_time, end_time)
  rescue ArgumentError
    false
  end

  def parse_datetime(value)
    case value
    when DateTime, Time
      value
    when Date
      value.to_datetime
    when String
      DateTime.parse(value)
    else
      nil
    end
  rescue ArgumentError
    nil
  end
end