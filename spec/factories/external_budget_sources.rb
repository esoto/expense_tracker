# frozen_string_literal: true

FactoryBot.define do
  factory :external_budget_source do
    association :email_account
    source_type { "salary_calculator" }
    base_url { "https://salary-calc.estebansoto.dev" }
    api_token { "fake-token-#{SecureRandom.hex(8)}" }
    active { true }
  end
end
