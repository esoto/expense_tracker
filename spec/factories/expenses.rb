FactoryBot.define do
  factory :expense do
    sequence(:amount) { |n| 100.50 + n }
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
    # Derive user from email_account so FK consistency is maintained.
    # email_account factory defaults to an admin user so that the
    # ExpensesController#scoping_user fallback (User.admin.first) always
    # finds a matching User in specs that don't explicitly stub scoping_user.
    user { email_account&.user || association(:user, :admin) }
    category { nil }  # Don't auto-assign category by default

    trait :manual_entry do
      association :user, :admin
      email_account { nil }
      bank_name { "Manual" }
    end

    trait :with_category do
      association :category, factory: :category
    end

    trait :without_category do
      category { nil }
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
