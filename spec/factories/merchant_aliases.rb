# frozen_string_literal: true

FactoryBot.define do
  factory :merchant_alias do
    association :canonical_merchant
    sequence(:raw_name) { |n| "RAW MERCHANT NAME #{n}" }
    normalized_name { raw_name.downcase.strip }
    confidence { 0.85 }
    match_count { 1 }
    last_seen_at { Time.current }
    
    trait :high_confidence do
      confidence { 0.95 }
      match_count { 10 }
    end
    
    trait :low_confidence do
      confidence { 0.60 }
      match_count { 1 }
    end
    
    trait :frequently_matched do
      match_count { 50 }
      confidence { 0.98 }
    end
  end
end