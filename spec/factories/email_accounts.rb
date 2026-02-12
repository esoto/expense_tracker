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
      sequence(:email) { |n| "gmail_#{SecureRandom.hex(4)}@example.com" }
    end

    trait :outlook do
      provider { "outlook" }
      sequence(:email) { |n| "outlook_#{SecureRandom.hex(4)}@example.com" }
    end

    trait :custom do
      provider { "custom" }
      encrypted_settings { { imap: { server: "custom.imap.com", port: 993 } }.to_json }
    end

    # Integration test traits with fixed emails for predictability
    trait :integration_gmail do
      provider { "gmail" }
      email { "test@gmail.com" }
    end

    trait :integration_outlook do
      provider { "outlook" }
      email { "test@outlook.com" }
    end

    trait :integration_custom do
      provider { "custom" }
      email { "test@custom.com" }
      encrypted_settings { { imap: { server: "custom.imap.com", port: 993 } }.to_json }
    end

    trait :inactive do
      active { false }
      sequence(:email) { |n| "inactive_#{SecureRandom.hex(4)}@example.com" }
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
