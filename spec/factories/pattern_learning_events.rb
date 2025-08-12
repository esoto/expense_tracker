# frozen_string_literal: true

FactoryBot.define do
  factory :pattern_learning_event do
    association :expense
    association :category
    pattern_used { "keyword:test_pattern" }
    was_correct { true }
    confidence_score { 0.85 }
    context_data { {} }

    trait :correct do
      was_correct { true }
    end

    trait :incorrect do
      was_correct { false }
    end


    trait :high_confidence do
      confidence_score { 0.95 }
    end

    trait :low_confidence do
      confidence_score { 0.60 }
    end
  end
end
