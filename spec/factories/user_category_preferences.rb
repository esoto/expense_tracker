# frozen_string_literal: true

FactoryBot.define do
  factory :user_category_preference do
    association :email_account
    association :category
    context_type { "merchant" }
    sequence(:context_value) { |n| "merchant_#{n}" }
    preference_weight { 1 }
    usage_count { 0 }

    trait :for_merchant do
      context_type { "merchant" }
    end

    trait :for_description do
      context_type { "description" }
    end

    trait :high_weight do
      preference_weight { 10 }
      usage_count { 25 }
    end
  end
end
