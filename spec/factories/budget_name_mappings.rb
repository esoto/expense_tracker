# frozen_string_literal: true

FactoryBot.define do
  factory :budget_name_mapping do
    user
    category
    kind { :category }
    source { :fuzzy }
    confidence { 0.7 }
    sequence(:normalized_name) { |n| "budget name #{n}" }

    trait :allocation do
      kind { :allocation }
      category { nil }
      source { :llm }
    end

    trait :confirmed do
      source { :user }
      confidence { 1.0 }
      confirmed_at { Time.current }
    end
  end
end
