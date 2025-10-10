# frozen_string_literal: true

class UserCategoryPreference < ApplicationRecord
  belongs_to :email_account
  belongs_to :category

  # Constants for classification ranges
  TIME_RANGES = {
    morning: 6..11,
    afternoon: 12..16,
    evening: 17..20
  }.freeze

  AMOUNT_RANGES = {
    small: 0...25,
    medium: 25...100,
    large: 100...500
  }.freeze

  CONTEXT_TYPES = %w[merchant time_of_day day_of_week amount_range].freeze
  WEIGHT_INCREMENT_THRESHOLD = 5

  validates :context_type, presence: true, inclusion: { in: CONTEXT_TYPES }
  validates :context_value, presence: true
  validates :preference_weight, numericality: { greater_than_or_equal_to: 1 }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }

  scope :for_context, ->(type, value) { where(context_type: type, context_value: value) }
  scope :by_weight, -> { order(preference_weight: :desc) }

  # Callbacks
  after_commit :invalidate_cache

  # Class method to learn from expense categorization
  def self.learn_from_categorization(email_account:, expense:, category:)
    generators = {
      "merchant" => -> {
        expense.merchant_name? ? expense.merchant_name.downcase : nil
      },
      "time_of_day" => -> {
        expense.transaction_date? ? classify_time_of_day(expense.transaction_date.hour) : nil
      },
      "day_of_week" => -> {
        expense.transaction_date? ? classify_day_of_week(expense.transaction_date) : nil
      },
      "amount_range" => -> {
        expense.amount? ? classify_amount_range(expense.amount) : nil
      }
    }

    generators.each do |context_type, generator|
      context_value = generator.call
      next if context_value.nil?

      learn_preference(
        email_account: email_account,
        category: category,
        context_type: context_type,
        context_value: context_value
      )
    end
  end

  # Find preferences that match an expense context
  def self.matching_preferences(email_account:, expense:)
    conditions = []

    # Build conditions for each context type
    if expense.merchant_name?
      conditions << { context_type: "merchant", context_value: expense.merchant_name.downcase }
    end

    if expense.transaction_date?
      conditions << { context_type: "time_of_day", context_value: classify_time_of_day(expense.transaction_date.hour) }
      conditions << { context_type: "day_of_week", context_value: classify_day_of_week(expense.transaction_date) }
    end

    if expense.amount.present?
      conditions << { context_type: "amount_range", context_value: classify_amount_range(expense.amount) }
    end

    return none if conditions.empty?

    subquery = where(email_account: email_account)
      .where(conditions.map { |c| arel_table[:context_type].eq(c[:context_type]).and(arel_table[:context_value].eq(c[:context_value])) }.reduce(:or))
      .select("DISTINCT ON (context_type) id")
      .order(:context_type, updated_at: :desc)

    where(id: subquery)
  end

  private

  # Classification helper methods
  def self.classify_time_of_day(hour)
    TIME_RANGES.each do |period, range|
      return period.to_s if range.cover?(hour)
    end
    "night"
  end

  def self.classify_day_of_week(date)
    date.strftime("%A").downcase
  end

  def self.classify_amount_range(amount)
    AMOUNT_RANGES.each do |range_name, range|
      return range_name.to_s if range.cover?(amount)
    end
    "very_large"
  end

  # Query helper method for finding preferences
  def self.find_context_preferences(email_account:, context_type:, context_value:)
    where(
      email_account: email_account,
      context_type: context_type,
      context_value: context_value
    )
  end

  # Learn and update preference weights
  def self.learn_preference(email_account:, category:, context_type:, context_value:)
    preference = find_or_initialize_by(
      email_account: email_account,
      category: category,
      context_type: context_type,
      context_value: context_value
    )

    if preference.persisted?
      preference.increment!(:usage_count)
      preference.increment!(:preference_weight) if preference.usage_count > WEIGHT_INCREMENT_THRESHOLD
    else
      preference.assign_attributes(
        preference_weight: 1,
        usage_count: 1
      )
      preference.save!
    end

    preference
  end

  private

  def invalidate_cache
    # Invalidate cache for merchant-based preferences
    Services::Categorization::PatternCache.instance.invalidate(self) if context_type == "merchant"
  rescue => e
    Rails.logger.error "[UserCategoryPreference] Cache invalidation failed: #{e.message}"
  end
end
