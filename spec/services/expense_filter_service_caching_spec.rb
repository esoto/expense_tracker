# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::ExpenseFilterService, type: :service, unit: true do
  let(:email_account) do
    EmailAccount.create!(
      provider: "gmail",
      email: "caching_test@example.com",
      bank_name: "BAC",
      active: true
    )
  end

  let(:other_account) do
    EmailAccount.create!(
      provider: "gmail",
      email: "caching_other@example.com",
      bank_name: "BCR",
      active: true
    )
  end

  before do
    Rails.cache.clear

    Expense.create!(
      email_account: email_account,
      amount: 100.00,
      transaction_date: Date.current,
      merchant_name: "Cache Test Store",
      status: "processed",
      currency: "crc"
    )

    Expense.create!(
      email_account: email_account,
      amount: 250.00,
      transaction_date: 1.week.ago,
      merchant_name: "Cache Test Store 2",
      status: "pending",
      currency: "crc"
    )
  end

  after do
    Rails.cache.clear
  end

  describe "caching behaviour" do
    let(:service) { described_class.new(account_ids: [ email_account.id ]) }

    it "returns non-cached result on first call" do
      result = service.call
      expect(result.performance_metrics[:cached]).to be false
    end

    it "returns cached result on second call with cached: true in performance_metrics" do
      first_result = service.call
      expect(first_result.performance_metrics[:cached]).to be false

      second_result = service.call
      expect(second_result.performance_metrics[:cached]).to be true
    end

    it "cached result preserves total_count from original result" do
      first_result = service.call
      second_result = service.call

      expect(second_result.total_count).to eq(first_result.total_count)
    end

    it "uses different cache keys for different filter params" do
      service_a = described_class.new(account_ids: [ email_account.id ], min_amount: 50)
      service_b = described_class.new(account_ids: [ email_account.id ], min_amount: 150)

      expect(service_a.send(:cache_key)).not_to eq(service_b.send(:cache_key))
    end

    it "uses different cache keys for different pages" do
      service_p1 = described_class.new(account_ids: [ email_account.id ], page: 1, per_page: 1)
      service_p2 = described_class.new(account_ids: [ email_account.id ], page: 2, per_page: 1)

      expect(service_p1.send(:cache_key)).not_to eq(service_p2.send(:cache_key))
    end

    it "uses different cache keys for different per_page values" do
      service_10 = described_class.new(account_ids: [ email_account.id ], per_page: 10)
      service_50 = described_class.new(account_ids: [ email_account.id ], per_page: 50)

      expect(service_10.send(:cache_key)).not_to eq(service_50.send(:cache_key))
    end

    it "includes the expense_version in the cache key" do
      key = service.send(:cache_key)
      expect(key).to match(/expense_filter:.+:\d+:\d+:v\d+/)
    end

    it "invalidates cache when an expense in the scoped accounts is updated" do
      first_result = service.call
      expect(first_result.performance_metrics[:cached]).to be false

      # Ensure time moves forward so updated_at changes
      travel_to(1.second.from_now) do
        Expense.where(email_account_id: email_account.id).first.touch
      end

      post_update_result = service.call
      expect(post_update_result.performance_metrics[:cached]).to be false
    end

    it "does NOT invalidate cache when an expense from a different account is updated" do
      # Create an expense for a different account
      Expense.create!(
        email_account: other_account,
        amount: 999.00,
        transaction_date: Date.current,
        merchant_name: "Unrelated Store",
        status: "processed",
        currency: "crc"
      )

      first_result = service.call
      expect(first_result.performance_metrics[:cached]).to be false

      # Touch only the other account's expense — should not affect our cache key
      travel_to(1.second.from_now) do
        Expense.where(email_account_id: other_account.id).first.touch
      end

      second_result = service.call
      expect(second_result.performance_metrics[:cached]).to be true
    end

    it "scopes the version key to account_ids only — different accounts produce different keys" do
      service_a = described_class.new(account_ids: [ email_account.id ])
      service_b = described_class.new(account_ids: [ other_account.id ])

      expect(service_a.send(:cache_key)).not_to eq(service_b.send(:cache_key))
    end

    it "cache key uses generate_filters_hash (SHA256-based) not a separate MD5 hash" do
      key = service.send(:cache_key)
      filters_hash = service.send(:generate_filters_hash)

      expect(key).to include(filters_hash)
    end
  end
end
