# frozen_string_literal: true

FactoryBot.define do
  factory :pattern_feedback do
    association :expense
    association :category
    was_correct { true }
    feedback_type { "accepted" }

    trait :correction do
      was_correct { false }
      feedback_type { "correction" }
    end

    trait :rejection do
      was_correct { false }
      feedback_type { "rejection" }
    end

    trait :manual do
      feedback_type { "manual" }
      was_correct { true }
    end
  end
end
