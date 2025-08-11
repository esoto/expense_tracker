# frozen_string_literal: true

# CompositePattern represents complex categorization rules that combine multiple
# CategorizationPatterns using logical operators (AND, OR, NOT).
# This allows for more sophisticated matching like "Uber OR Lyft in morning hours"
# or "Restaurant AND amount > 50 AND weekend"
class CompositePattern < ApplicationRecord
  # Constants
  OPERATORS = %w[AND OR NOT].freeze
  DEFAULT_CONFIDENCE_WEIGHT = 1.5
  MIN_CONFIDENCE_WEIGHT = 0.1
  MAX_CONFIDENCE_WEIGHT = 5.0

  # Associations
  belongs_to :category

  # Validations
  validates :name, presence: true, uniqueness: { scope: :category_id }
  validates :operator, presence: true, inclusion: { in: OPERATORS }
  validates :pattern_ids, presence: true
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

  validate :pattern_ids_exist
  validate :success_count_not_greater_than_usage_count
  validate :validate_conditions_format

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :user_created, -> { where(user_created: true) }
  scope :system_created, -> { where(user_created: false) }
  scope :successful, -> { where("success_rate >= ?", 0.7) }
  scope :frequently_used, -> { where("usage_count >= ?", 10) }
  scope :ordered_by_success, -> { order(success_rate: :desc, usage_count: :desc) }
  scope :for_category, ->(category) { where(category: category) }

  # Callbacks
  before_save :calculate_success_rate
  after_commit :invalidate_cache

  # Public Methods

  # Get the component patterns
  def component_patterns
    return [] if pattern_ids.blank?

    CategorizationPattern.where(id: pattern_ids)
  end

  # Check if the composite pattern matches the given expense
  def matches?(expense)
    return false unless active?
    return false if component_patterns.empty?

    # Check additional conditions first
    return false unless conditions_match?(expense)

    # Evaluate based on operator
    case operator
    when "AND"
      matches_all?(expense)
    when "OR"
      matches_any?(expense)
    when "NOT"
      matches_none?(expense)
    else
      false
    end
  end

  # Record usage of this pattern and whether it was successful
  def record_usage(was_successful)
    self.usage_count += 1
    self.success_count += 1 if was_successful
    calculate_success_rate
    save!
  end

  # Get the effective confidence for this composite pattern
  def effective_confidence
    base_confidence = confidence_weight

    # Composite patterns should have higher confidence if all components are high confidence
    component_confidences = component_patterns.map(&:effective_confidence)

    if component_confidences.any?
      avg_component_confidence = component_confidences.sum / component_confidences.size

      # Weight composite confidence by component confidence average
      adjusted_confidence = base_confidence * (0.7 + (avg_component_confidence * 0.3))

      # Further adjust based on success rate if we have enough data
      if usage_count >= 5
        adjusted_confidence * (0.5 + (success_rate * 0.5))
      else
        adjusted_confidence * 0.8 # Lower confidence for patterns with little data
      end
    else
      0.0
    end
  end

  # Deactivate pattern if it's performing poorly
  def check_and_deactivate_if_poor_performance
    return unless usage_count >= 20
    return unless success_rate < 0.3

    update!(active: false)
  end

  # Add a pattern to this composite
  def add_pattern(pattern_or_id)
    pattern_id = pattern_or_id.is_a?(CategorizationPattern) ? pattern_or_id.id : pattern_or_id

    unless pattern_ids.include?(pattern_id)
      update!(pattern_ids: pattern_ids + [ pattern_id ])
    end
  end

  # Remove a pattern from this composite
  def remove_pattern(pattern_or_id)
    pattern_id = pattern_or_id.is_a?(CategorizationPattern) ? pattern_or_id.id : pattern_or_id

    if pattern_ids.include?(pattern_id)
      update!(pattern_ids: pattern_ids - [ pattern_id ])
    end
  end

  # Build a human-readable description of the composite pattern
  def description
    patterns = component_patterns.map do |p|
      "#{p.pattern_type}:#{p.pattern_value}"
    end

    case operator
    when "AND"
      patterns.join(" AND ")
    when "OR"
      patterns.join(" OR ")
    when "NOT"
      "NOT (#{patterns.join(' OR ')})"
    else
      name
    end
  end

  private

  def calculate_success_rate
    self.success_rate = if usage_count.positive?
                          success_count.to_f / usage_count
    else
                          0.0
    end
  end

  def pattern_ids_exist
    return if pattern_ids.blank?

    patterns = CategorizationPattern.where(id: pattern_ids)
    existing_ids = patterns.pluck(:id)
    missing_ids = pattern_ids - existing_ids

    if missing_ids.any?
      errors.add(:pattern_ids, "contains non-existent pattern IDs: #{missing_ids.join(', ')}")
    end

    # Ensure all patterns belong to the same category
    if patterns.any? && category_id
      different_category_ids = patterns.where.not(category_id: category_id).pluck(:id)
      if different_category_ids.any?
        errors.add(:pattern_ids, "contains patterns from different categories: #{different_category_ids.join(', ')}")
      end
    end
  end

  def success_count_not_greater_than_usage_count
    return if success_count <= usage_count

    errors.add(:success_count, "cannot be greater than usage count")
  end

  def validate_conditions_format
    return if conditions.blank?

    # Validate expected condition keys
    valid_keys = %w[min_amount max_amount days_of_week time_ranges merchant_blacklist]
    invalid_keys = conditions.keys - valid_keys

    if invalid_keys.any?
      errors.add(:conditions, "contains invalid keys: #{invalid_keys.join(', ')}")
    end

    # Validate specific condition formats
    validate_amount_conditions if conditions["min_amount"] || conditions["max_amount"]
    validate_days_of_week if conditions["days_of_week"]
    validate_time_ranges if conditions["time_ranges"]
  end

  def validate_amount_conditions
    if conditions["min_amount"] && !valid_amount?(conditions["min_amount"])
      errors.add(:conditions, "min_amount must be a positive number")
    end

    if conditions["max_amount"] && !valid_amount?(conditions["max_amount"])
      errors.add(:conditions, "max_amount must be a positive number")
    end

    if conditions["min_amount"] && conditions["max_amount"]
      min_val = conditions["min_amount"].to_f
      max_val = conditions["max_amount"].to_f

      if min_val >= max_val
        errors.add(:conditions, "min_amount must be less than max_amount")
      end
    end
  end

  def valid_amount?(value)
    value.is_a?(Numeric) && value > 0
  end

  def validate_days_of_week
    valid_days = %w[monday tuesday wednesday thursday friday saturday sunday]
    days = conditions["days_of_week"]

    unless days.is_a?(Array) && days.all? { |day| day.is_a?(String) && valid_days.include?(day.downcase) }
      errors.add(:conditions, "days_of_week must be an array of valid day names")
    end
  end

  def validate_time_ranges
    ranges = conditions["time_ranges"]

    unless ranges.is_a?(Array)
      errors.add(:conditions, "time_ranges must be an array")
      return
    end

    ranges.each do |range|
      unless range.is_a?(Hash) && range["start"] && range["end"]
        errors.add(:conditions, "each time_range must have 'start' and 'end' times")
        next
      end

      unless valid_time_format?(range["start"]) && valid_time_format?(range["end"])
        errors.add(:conditions, "time_ranges must be in HH:MM format")
      end
    end
  end

  def valid_time_format?(time_str)
    time_str.match?(/\A\d{1,2}:\d{2}\z/)
  end

  def conditions_match?(expense)
    return true if conditions.blank?

    # Check amount conditions
    if conditions["min_amount"] && expense.amount < conditions["min_amount"].to_f
      return false
    end

    if conditions["max_amount"] && expense.amount > conditions["max_amount"].to_f
      return false
    end

    # Check day of week conditions
    if conditions["days_of_week"] && expense.transaction_date
      day_name = expense.transaction_date.strftime("%A").downcase
      return false unless conditions["days_of_week"].map(&:downcase).include?(day_name)
    end

    # Check time range conditions
    if conditions["time_ranges"] && expense.transaction_date
      time_str = expense.transaction_date.strftime("%H:%M")

      in_range = conditions["time_ranges"].any? do |range|
        time_in_range?(time_str, range["start"], range["end"])
      end

      return false unless in_range
    end

    # Check merchant blacklist
    if conditions["merchant_blacklist"] && expense.merchant_name
      blacklist = conditions["merchant_blacklist"].map(&:downcase)
      return false if blacklist.include?(expense.merchant_name.downcase)
    end

    true
  end

  def time_in_range?(time_str, start_str, end_str)
    time = Time.parse(time_str)
    start_time = Time.parse(start_str)
    end_time = Time.parse(end_str)

    if end_time < start_time # Crosses midnight
      time >= start_time || time <= end_time
    else
      time.between?(start_time, end_time)
    end
  rescue ArgumentError
    false
  end

  def matches_all?(expense)
    component_patterns.all? { |pattern| pattern_matches_expense?(pattern, expense) }
  end

  def matches_any?(expense)
    component_patterns.any? { |pattern| pattern_matches_expense?(pattern, expense) }
  end

  def matches_none?(expense)
    component_patterns.none? { |pattern| pattern_matches_expense?(pattern, expense) }
  end

  def pattern_matches_expense?(pattern, expense)
    pattern.matches?(expense)
  end
  
  def invalidate_cache
    Categorization::PatternCache.instance.invalidate(self) if defined?(Categorization::PatternCache)
  rescue => e
    Rails.logger.error "[CompositePattern] Cache invalidation failed: #{e.message}"
  end
end
