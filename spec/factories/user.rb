# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "TestPass123!" }
    name { "Test User" }
    role { :user }

    trait :admin do
      role { :admin }
    end

    trait :locked do
      locked_at { Time.current }
    end
  end
end
