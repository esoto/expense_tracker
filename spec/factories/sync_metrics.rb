FactoryBot.define do
  factory :sync_metric do
    association :sync_session
    email_account { nil } # Optional by default
    metric_type { SyncMetric::METRIC_TYPES[:email_fetch] }
    duration { rand(100..5000) }
    emails_processed { rand(0..100) }
    success { true }
    error_type { nil }
    error_message { nil }
    metadata { {} }
    started_at { Time.current }
    completed_at { started_at + (duration / 1000.0).seconds if duration }

    trait :with_account do
      association :email_account
    end

    trait :failed do
      success { false }
      error_type { ["ConnectionError", "ParseError", "TimeoutError"].sample }
      error_message { "An error occurred during sync operation" }
    end

    trait :session_overall do
      metric_type { SyncMetric::METRIC_TYPES[:session_overall] }
      email_account { nil }
    end

    trait :account_sync do
      metric_type { SyncMetric::METRIC_TYPES[:account_sync] }
      association :email_account
    end

    trait :email_fetch do
      metric_type { SyncMetric::METRIC_TYPES[:email_fetch] }
    end

    trait :email_parse do
      metric_type { SyncMetric::METRIC_TYPES[:email_parse] }
    end

    trait :expense_detection do
      metric_type { SyncMetric::METRIC_TYPES[:expense_detection] }
    end

    trait :conflict_detection do
      metric_type { SyncMetric::METRIC_TYPES[:conflict_detection] }
    end

    trait :database_write do
      metric_type { SyncMetric::METRIC_TYPES[:database_write] }
    end

    trait :broadcast do
      metric_type { SyncMetric::METRIC_TYPES[:broadcast] }
    end

    trait :long_running do
      duration { rand(10000..60000) }
    end

    trait :quick do
      duration { rand(10..100) }
    end

    trait :high_volume do
      emails_processed { rand(100..1000) }
    end
  end
end