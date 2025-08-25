FactoryBot.define do
  factory :processed_email do
    sequence(:message_id) { |n| "message_#{n}@example.com" }
    association :email_account
    processed_at { 1.hour.ago }
    sequence(:uid) { |n| "uid_#{n}" }
    subject { "Test Email Subject" }
    from_address { "sender@example.com" }
  end
end
