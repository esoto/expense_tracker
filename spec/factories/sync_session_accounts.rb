FactoryBot.define do
  factory :sync_session_account do
    sync_session
    email_account
    status { "pending" }
    total_emails { 0 }
    processed_emails { 0 }
    detected_expenses { 0 }

    trait :processing do
      status { "processing" }
      total_emails { 50 }
      processed_emails { 10 }
    end

    trait :completed do
      status { "completed" }
      total_emails { 50 }
      processed_emails { 50 }
      detected_expenses { 8 }
    end

    trait :failed do
      status { "failed" }
      last_error { "IMAP connection failed" }
      total_emails { 25 }
      processed_emails { 5 }
    end
  end
end

