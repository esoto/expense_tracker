FactoryBot.define do
  factory :email_account do
    sequence(:email) { |n| "user#{n}@example.com" }
    provider { "gmail" }
    bank_name { "BAC" }
    encrypted_password { "test_password" }
    active { true }
    encrypted_settings { nil }

    trait :gmail do
      provider { "gmail" }
      email { "test@gmail.com" }
    end

    trait :outlook do
      provider { "outlook" }
      email { "test@outlook.com" }
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