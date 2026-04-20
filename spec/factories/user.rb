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
      locked_at { 1.hour.ago }
      failed_login_attempts { 5 }
    end

    trait :with_session do
      session_token { SecureRandom.urlsafe_base64(32) }
      session_expires_at { 2.hours.from_now }
    end
  end
end
