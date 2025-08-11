# frozen_string_literal: true

FactoryBot.define do
  factory :composite_pattern do
    association :category

    name { "Composite Pattern #{SecureRandom.hex(4)}" }
    operator { "AND" }
    confidence_weight { 1.5 }
    active { true }
    user_created { false }
    usage_count { 0 }
    success_count { 0 }
    success_rate { 0.0 }
    conditions { {} }

    # Default pattern_ids - create them after category is set
    after(:build) do |composite|
      if composite.pattern_ids.blank?
        pattern = create(:categorization_pattern, category: composite.category)
        composite.pattern_ids = [ pattern.id ]
      end
    end

    trait :with_patterns do
      after(:build) do |composite|
        if composite.pattern_ids.empty?
          patterns = create_list(:categorization_pattern, 2, category: composite.category)
          composite.pattern_ids = patterns.map(&:id)
        end
      end
    end

    trait :or_operator do
      operator { "OR" }
    end

    trait :not_operator do
      operator { "NOT" }
    end

    trait :with_conditions do
      conditions do
        {
          "min_amount" => 10.0,
          "max_amount" => 100.0,
          "days_of_week" => [ "monday", "tuesday", "wednesday" ],
          "time_ranges" => [
            { "start" => "09:00", "end" => "17:00" }
          ]
        }
      end
    end

    trait :high_confidence do
      confidence_weight { 4.0 }
      success_rate { 0.90 }
      usage_count { 50 }
      success_count { 45 }
    end

    trait :inactive do
      active { false }
    end

    trait :user_created do
      user_created { true }
    end
  end
end
