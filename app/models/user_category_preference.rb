# frozen_string_literal: true

class UserCategoryPreference < ApplicationRecord
  belongs_to :email_account
  belongs_to :category
  
  validates :context_type, presence: true, inclusion: { in: %w[merchant time_of_day day_of_week amount_range] }
  validates :context_value, presence: true
  validates :preference_weight, numericality: { greater_than_or_equal_to: 1 }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
  
  scope :for_context, ->(type, value) { where(context_type: type, context_value: value) }
  scope :by_weight, -> { order(preference_weight: :desc) }
  
  # Class method to learn from expense categorization
  def self.learn_from_categorization(email_account:, expense:, category:)
    # Learn from merchant
    if expense.merchant_name.present?
      learn_preference(
        email_account: email_account,
        category: category,
        context_type: "merchant",
        context_value: expense.merchant_name.downcase
      )
    end
    
    # Learn from time of day  
    if expense.transaction_date.present?
      hour = expense.transaction_date.hour
      time_context = case hour
                     when 6..11 then "morning"
                     when 12..16 then "afternoon" 
                     when 17..20 then "evening"
                     else "night"
                     end
      
      learn_preference(
        email_account: email_account,
        category: category,
        context_type: "time_of_day",
        context_value: time_context
      )
    end
    
    # Learn from day of week
    if expense.transaction_date.present?
      day_name = expense.transaction_date.strftime("%A").downcase
      learn_preference(
        email_account: email_account,
        category: category,
        context_type: "day_of_week",
        context_value: day_name
      )
    end
    
    # Learn from amount range
    if expense.amount.present?
      amount_range = case expense.amount
                     when 0..25 then "small"
                     when 25..100 then "medium"
                     when 100..500 then "large"
                     else "very_large"
                     end
      
      learn_preference(
        email_account: email_account,
        category: category,
        context_type: "amount_range",
        context_value: amount_range
      )
    end
  end
  
  # Find preferences that match an expense context
  def self.matching_preferences(email_account:, expense:)
    preferences = []
    
    # Match merchant preferences
    if expense.merchant_name.present?
      preferences += where(
        email_account: email_account,
        context_type: "merchant",
        context_value: expense.merchant_name.downcase
      )
    end
    
    # Match time of day preferences
    if expense.transaction_date.present?
      hour = expense.transaction_date.hour
      time_context = case hour
                     when 6..11 then "morning"
                     when 12..16 then "afternoon"
                     when 17..20 then "evening"
                     else "night"
                     end
      
      preferences += where(
        email_account: email_account,
        context_type: "time_of_day",
        context_value: time_context
      )
    end
    
    # Match day of week preferences
    if expense.transaction_date.present?
      day_name = expense.transaction_date.strftime("%A").downcase
      preferences += where(
        email_account: email_account,
        context_type: "day_of_week", 
        context_value: day_name
      )
    end
    
    # Match amount range preferences
    if expense.amount.present?
      amount_range = case expense.amount
                     when 0..25 then "small"
                     when 25..100 then "medium"
                     when 100..500 then "large"
                     else "very_large"
                     end
      
      preferences += where(
        email_account: email_account,
        context_type: "amount_range",
        context_value: amount_range
      )
    end
    
    preferences.uniq
  end
  
  private
  
  def self.learn_preference(email_account:, category:, context_type:, context_value:)
    preference = find_or_initialize_by(
      email_account: email_account,
      category: category,
      context_type: context_type,
      context_value: context_value
    )
    
    if preference.persisted?
      preference.increment!(:usage_count)
      preference.increment!(:preference_weight) if preference.usage_count > 5
    else
      preference.assign_attributes(
        preference_weight: 1,
        usage_count: 1
      )
      preference.save!
    end
    
    preference
  end
end