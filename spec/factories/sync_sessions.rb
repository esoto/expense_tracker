FactoryBot.define do
  factory :sync_session do
    status { "pending" }
    total_emails { 0 }
    processed_emails { 0 }
    detected_expenses { 0 }

    trait :running do
      status { "running" }
      started_at { 1.minute.ago }
      total_emails { 100 }
      processed_emails { 25 }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      total_emails { 100 }
      processed_emails { 100 }
      detected_expenses { 15 }
    end

    trait :failed do
      status { "failed" }
      started_at { 3.minutes.ago }
      completed_at { 1.minute.ago }
      error_details { "Connection timeout while processing emails" }
      total_emails { 50 }
      processed_emails { 10 }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 2.minutes.ago }
      completed_at { 30.seconds.ago }
      total_emails { 75 }
      processed_emails { 40 }
    end
  end
end
