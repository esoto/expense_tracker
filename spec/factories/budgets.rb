# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    association :email_account

    name { "Presupuesto #{period.humanize}" }
    description { "Presupuesto para controlar gastos" }
    period { 'monthly' }
    amount { 500000 }
    currency { 'CRC' }
    active { true }
    start_date { Date.current.beginning_of_month }
    end_date { nil }
    warning_threshold { 70 }
    critical_threshold { 90 }
    notify_on_warning { true }
    notify_on_critical { true }
    notify_on_exceeded { true }
    rollover_enabled { false }
    rollover_amount { 0 }
    current_spend { 0 }
    current_spend_updated_at { nil }
    times_exceeded { 0 }
    last_exceeded_at { nil }
    metadata { {} }

    trait :with_category do
      association :category
    end

    trait :daily do
      period { 'daily' }
      amount { 25000 }
      start_date { Date.current }
    end

    trait :weekly do
      period { 'weekly' }
      amount { 175000 }
      start_date { Date.current.beginning_of_week }
    end

    trait :yearly do
      period { 'yearly' }
      amount { 6000000 }
      start_date { Date.current.beginning_of_year }
    end

    trait :inactive do
      active { false }
    end

    trait :exceeded do
      current_spend { amount * 1.2 }
      times_exceeded { 1 }
      last_exceeded_at { Time.current }
    end

    trait :at_warning do
      current_spend { amount * 0.75 }
    end

    trait :at_critical do
      current_spend { amount * 0.92 }
    end

    trait :with_end_date do
      end_date { start_date + 3.months }
    end
  end
end
