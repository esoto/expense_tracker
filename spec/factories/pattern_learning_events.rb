# frozen_string_literal: true

FactoryBot.define do
  factory :pattern_learning_event do
    association :expense
    association :suggested_category, factory: :category
    association :pattern, factory: :categorization_pattern
    was_correct { true }
    confidence { 0.85 }
    feedback_type { "implicit" }
    
    trait :correct do
      was_correct { true }
    end
    
    trait :incorrect do
      was_correct { false }
    end
    
    trait :explicit_feedback do
      feedback_type { "explicit" }
    end
    
    trait :implicit_feedback do
      feedback_type { "implicit" }
    end
    
    trait :high_confidence do
      confidence { 0.95 }
    end
    
    trait :low_confidence do
      confidence { 0.60 }
    end
  end
end