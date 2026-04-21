# frozen_string_literal: true

FactoryBot.define do
  factory :categorization_metric do
    expense
    user { expense.user }
    category
    layer_used { "pattern" }
    confidence { 0.85 }
    was_corrected { false }
    processing_time_ms { 12.5 }
    api_cost { 0.0 }

    trait :corrected do
      was_corrected { true }
      association :corrected_to_category, factory: :category
      time_to_correction_hours { 2 }
    end

    trait :haiku_layer do
      layer_used { "haiku" }
      api_cost { 0.001 }
    end

    trait :pg_trgm_layer do
      layer_used { "pg_trgm" }
    end

    trait :manual_layer do
      layer_used { "manual" }
    end
  end
end
