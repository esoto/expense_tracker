FactoryBot.define do
  factory :expense do
    amount { 100.50 }
    description { "Test expense" }
    transaction_date { Time.current }
    merchant_name { "Test Merchant" }
    merchant_normalized { "Test Merchant" }
    status { :pending }
    currency { "crc" }
    raw_email_content { nil }
    parsed_data { nil }
    bank_name { "BAC" }

    association :email_account
    category { nil }  # Don't auto-assign category by default

    trait :with_category do
      association :category, factory: :category
    end

    trait :processed do
      status { :processed }
    end

    trait :failed do
      status { :failed }
    end

    trait :duplicate do
      status { :duplicate }
    end

    trait :usd do
      currency { "usd" }
      amount { 20.50 }
    end

    trait :eur do
      currency { "eur" }
      amount { 15.75 }
    end

    trait :large_amount do
      amount { 95000.00 }
    end

    trait :recent do
      transaction_date { 1.day.ago }
    end

    trait :old do
      transaction_date { 1.week.ago }
    end

    trait :with_raw_email do
      raw_email_content { "Original email content here" }
      parsed_data { { amount: "100.50", merchant: "Test Merchant" }.to_json }
    end
  end
end
