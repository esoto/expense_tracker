FactoryBot.define do
  factory :email_account do
    sequence(:email) { |n| "user#{n}_#{Time.current.to_i}@example.com" }
    provider { "gmail" }
    bank_name { "BAC" }
    encrypted_password { "test_password" }
    active { true }
    encrypted_settings { nil }

    trait :gmail do
      provider { "gmail" }
      sequence(:email) { |n| "test#{n}@gmail.com" }
    end

    trait :outlook do
      provider { "outlook" }
      sequence(:email) { |n| "test#{n}@outlook.com" }
    end

    trait :custom do
      provider { "custom" }
      encrypted_settings { { imap: { server: "custom.imap.com", port: 993 } }.to_json }
    end

    trait :inactive do
      active { false }
    end

    trait :bac do
      bank_name { "BAC" }
    end

    trait :bcr do
      bank_name { "BCR" }
    end

    trait :scotiabank do
      bank_name { "Scotiabank" }
    end

    trait :banco_nacional do
      bank_name { "Banco Nacional" }
    end
  end
end
