# frozen_string_literal: true

FactoryBot.define do
  factory :user_category_preference do
    association :category
    context_type { "merchant" }
    sequence(:context_value) { |n| "merchant_#{n}" }
    confidence { 1.0 }
    
    trait :for_merchant do
      context_type { "merchant" }
    end
    
    trait :for_description do
      context_type { "description" }
    end
    
    trait :low_confidence do
      confidence { 0.5 }
    end
  end
end