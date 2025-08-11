FactoryBot.define do
  factory :failed_broadcast_store do
    channel_name { "SyncStatusChannel" }
    target_type { "SyncSession" }
    target_id { 1 }
    data { { status: 'processing', processed: 10, total: 100 } }
    priority { "medium" }
    error_type { "connection_timeout" }
    error_message { "Connection timed out after 5 seconds" }
    failed_at { 1.hour.ago }
    retry_count { 0 }
    sequence(:sidekiq_job_id) { |n| "job_#{n}_#{SecureRandom.hex(6)}" }
    recovered_at { nil }
    recovery_notes { nil }

    trait :recovered do
      recovered_at { 30.minutes.ago }
      recovery_notes { "Successfully retried after connection issue resolved" }
    end

    trait :critical_priority do
      priority { "critical" }
      error_type { "job_death" }
      error_message { "Worker process died unexpectedly" }
    end

    trait :record_not_found do
      error_type { "record_not_found" }
      error_message { "Couldn't find SyncSession with 'id'=999" }
      target_id { 999 }
    end

    trait :max_retries_reached do
      retry_count { 3 }
      failed_at { 2.hours.ago }
    end

    trait :with_sync_session do
      association :target, factory: :sync_session, strategy: :build
      target_type { "SyncSession" }
      target_id { target.id }
    end
  end
end
