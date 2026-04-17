# frozen_string_literal: true

FactoryBot.define do
  factory :llm_categorization_cache_entry do
    sequence(:merchant_normalized) { |n| "merchant #{n}" }
    category
    confidence { 0.85 }
    model_used { "claude-haiku-4-5" }
    # Match the current PromptBuilder::PROMPT_VERSION so the strategy's cache
    # lookup finds factory-built rows by default.
    prompt_version { Services::Categorization::Llm::PromptBuilder::PROMPT_VERSION }
    expires_at { 90.days.from_now }
  end
end
