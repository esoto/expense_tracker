# frozen_string_literal: true

FactoryBot.define do
  factory :canonical_merchant do
    sequence(:name) { |n| "merchant_#{n}" }
    display_name { name.titleize }
    category_hint { nil }
    metadata { {} }
    usage_count { 0 }
    
    trait :popular do
      usage_count { 100 }
    end
    
    trait :with_category_hint do
      category_hint { "Food & Dining" }
    end
    
    trait :with_metadata do
      metadata do
        {
          website: "https://example.com",
          phone: "555-1234",
          address: "123 Main St"
        }
      end
    end
  end
end