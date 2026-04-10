# frozen_string_literal: true

FactoryBot.define do
  factory :categorization_vector do
    sequence(:merchant_normalized) { |n| "merchant #{n}" }
    association :category
    occurrence_count { 5 }
    correction_count { 0 }
    confidence { 0.8 }
    description_keywords { [] }
    last_seen_at { Time.current }
  end
end
