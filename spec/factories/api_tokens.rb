FactoryBot.define do
  factory :api_token do
    sequence(:name) { |n| "Test Token #{n}" }
    expires_at { 1.year.from_now }
    active { true }
    last_used_at { nil }

    trait :inactive do
      active { false }
    end

    trait :active do
      active { true }
    end

    trait :permanent do
      expires_at { nil }
    end

    trait :expired do
      expires_at { 1.year.from_now }
      after(:create) do |token|
        token.update_column(:expires_at, 1.day.ago)
      end
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end

    trait :iphone_shortcuts do
      name { "iPhone Shortcuts" }
      expires_at { 1.year.from_now }
    end

    trait :development do
      name { "Development Testing" }
      expires_at { 6.months.from_now }
    end

    # This trait is useful for testing authentication
    trait :with_known_token do
      after(:build) do |token|
        token.token = "test-token-123"
        token.token_digest = BCrypt::Password.create("test-token-123")
      end
    end
  end
end
