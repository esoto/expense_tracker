FactoryBot.define do
  factory :expense_with_confidence, parent: :expense do
    ml_confidence { 0.85 }
    ml_confidence_explanation { "High confidence based on merchant pattern match" }

    trait :high_confidence do
      ml_confidence { 0.90 }
      ml_confidence_explanation { "Very high confidence - exact merchant match" }
    end

    trait :medium_confidence do
      ml_confidence { 0.75 }
      ml_confidence_explanation { "Medium confidence - partial pattern match" }
    end

    trait :low_confidence do
      ml_confidence { 0.55 }
      ml_confidence_explanation { "Low confidence - weak pattern match" }
    end

    trait :very_low_confidence do
      ml_confidence { 0.30 }
      ml_confidence_explanation { "Very low confidence - no clear pattern" }
    end

    trait :with_suggestion do
      association :ml_suggested_category, factory: :category
      ml_confidence { 0.65 }
      ml_confidence_explanation { "Alternative category suggested based on patterns" }
    end

    trait :recently_corrected do
      ml_last_corrected_at { 30.minutes.ago }
      ml_correction_count { 1 }
      ml_confidence { 1.0 }
      ml_confidence_explanation { "Manually corrected by user" }
    end

    trait :frequently_corrected do
      ml_last_corrected_at { 1.day.ago }
      ml_correction_count { 5 }
      ml_confidence { 1.0 }
      ml_confidence_explanation { "Manually corrected by user" }
    end
  end
end
