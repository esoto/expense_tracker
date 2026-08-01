FactoryBot.define do
  factory :queued_email_payload do
    association :email_account
    sync_session { nil }
    payload_data do
      {
        email_data: {
          body: "Transaction notification: $100.00 at Store ABC",
          subject: "Transaction Alert",
          from: "bank@example.com",
          message_id: 1,
          rfc_message_id: "<msg-1@example.com>",
          date: Time.current
        },
        pre_parsed: nil
      }
    end

    trait :processed do
      processed_at { Time.current }
    end
  end
end
