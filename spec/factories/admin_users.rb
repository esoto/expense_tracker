FactoryBot.define do
  factory :admin_user do
    sequence(:email) { |n| "admin#{n}@expense-tracker.com" }
    password { "AdminPassword123!" }
    name { "Test Administrator" }
    role { :admin }
    failed_login_attempts { 0 }
    locked_at { nil }
    session_token { nil }
    session_expires_at { nil }
    two_factor_enabled { false }
    two_factor_secret { nil }

    trait :super_admin do
      role { :super_admin }
    end

    trait :moderator do
      role { :moderator }
    end

    trait :read_only do
      role { :read_only }
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
