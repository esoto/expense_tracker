# frozen_string_literal: true

FactoryBot.define do
  factory :user_category_preference do
    association :email_account
    association :category
    
    context_type { "merchant" }
    context_value { "test merchant" }
    preference_weight { 1 }
    usage_count { 0 }
    
    trait :merchant do
      context_type { "merchant" }
      context_value { "starbucks coffee" }
    end
    
    trait :time_of_day do
      context_type { "time_of_day" }
      context_value { "morning" }
    end
    
    trait :day_of_week do
      context_type { "day_of_week" }
      context_value { "monday" }
    end
    
    trait :amount_range do
      context_type { "amount_range" }
      context_value { "10-50" }
    end
    
    trait :high_weight do
      preference_weight { 10 }
      usage_count { 25 }
    end
    
    trait :frequently_used do
      usage_count { 50 }
      preference_weight { 5 }
    end
  end
end