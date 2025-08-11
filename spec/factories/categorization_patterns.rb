# frozen_string_literal: true

FactoryBot.define do
  factory :categorization_pattern do
    association :category

    pattern_type { "merchant" }
    pattern_value { "Test Merchant #{SecureRandom.hex(4)}" }
    confidence_weight { 1.0 }
    active { true }
    user_created { false }
    usage_count { 0 }
    success_count { 0 }
    success_rate { 0.0 }
    metadata { {} }

    trait :merchant do
      pattern_type { "merchant" }
      pattern_value { "Starbucks" }
    end

    trait :keyword do
      pattern_type { "keyword" }
      pattern_value { "coffee" }
    end

    trait :description do
      pattern_type { "description" }
      pattern_value { "purchase at" }
    end

    trait :amount_range do
      pattern_type { "amount_range" }
      pattern_value { "10.00-50.00" }
    end

    trait :regex do
      pattern_type { "regex" }
      pattern_value { "\\b(coffee|cafe)\\b" }
    end

    trait :time do
      pattern_type { "time" }
      pattern_value { "morning" }
    end

    trait :high_confidence do
      confidence_weight { 4.0 }
      success_rate { 0.95 }
      usage_count { 100 }
      success_count { 95 }
    end

    trait :frequently_used do
      usage_count { 50 }
      success_count { 40 }
      success_rate { 0.8 }
    end

    trait :inactive do
      active { false }
    end

    trait :user_created do
      user_created { true }
    end
  end
end
