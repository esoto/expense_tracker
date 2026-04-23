# frozen_string_literal: true

FactoryBot.define do
  factory :budget_category do
    association :budget
    association :category
  end
end
