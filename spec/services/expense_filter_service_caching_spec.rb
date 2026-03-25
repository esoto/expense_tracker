# frozen_string_literal: true

require "rails_helper"

# Tests for ExpenseFilterService caching behaviour (PER-128).
# Relies on the expense_filter_cache initializer setting
# Rails.application.config.expense_filter_cache_enabled = true.
RSpec.describe Services::ExpenseFilterService, :unit, type: :service do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category, name: "Food", color: "#FF0000") }

  let!(:expense1) do
    create(:expense,
           email_account: email_account,
           amount: 100.00,
           transaction_date: Date.current,
           merchant_name: "Test Store",
           category: category,
           status: "processed",
           currency: "crc")
  end

  let!(:expense2) do
    create(:expense,
           email_account: email_account,
           amount: 200.00,
           transaction_date: 1.week.ago,
           merchant_name: "Another Store",
           category: nil,
           status: "pending",
           currency: "crc")
  end

  let(:base_params) { { account_ids: [ email_account.id ] } }

  before { Rails.cache.clear }
  after  { Rails.cache.clear }

  describe "caching behaviour (cache enabled via initializer)" do
    it "stores result in cache after the first call" do
      service = described_class.new(base_params)

      expect(Rails.cache).to receive(:write).once.and_call_original

      service.call
    end

    it "returns cached result on second call with same params" do
      described_class.new(base_params).call # warm the cache

      # Second call with identical params should NOT hit the DB again
      expect(Rails.cache).not_to receive(:write)

      result = described_class.new(base_params).call
      expect(result).to be_success
      expect(result.expenses.count).to eq(2)
    end

    it "marks first result as not cached (database call)" do
      result = described_class.new(base_params).call
      expect(result.performance_metrics[:cached]).to eq(false)
    end

    it "uses different cache keys for different filter params" do
      key_all = described_class.new(base_params).send(:cache_key)
      key_cat = described_class.new(base_params.merge(category_ids: [ category.id ])).send(:cache_key)

      expect(key_all).not_to eq(key_cat)
    end

    it "invalidates cache when any expense updated_at advances" do
      key_before = described_class.new(base_params).send(:cache_key)

      travel 1.second do
        expense1.touch
      end

      key_after = described_class.new(base_params).send(:cache_key)

      expect(key_before).not_to eq(key_after)
    end

    it "uses different keys for different pages" do
      key_p1 = described_class.new(base_params.merge(page: 1, per_page: 10)).send(:cache_key)
      key_p2 = described_class.new(base_params.merge(page: 2, per_page: 10)).send(:cache_key)

      expect(key_p1).not_to eq(key_p2)
    end
  end

  describe "caching disabled at service level" do
    it "does not write to or read from cache when cache_enabled? returns false" do
      service = described_class.new(base_params)

      # Stub at the service instance level — avoids fighting with Rails.configuration
      allow(service).to receive(:cache_enabled?).and_return(false)

      expect(Rails.cache).not_to receive(:write)
      expect(Rails.cache).not_to receive(:read)

      service.call
    end
  end

  describe "#cache_key format" do
    it "matches expense_filter:<md5hash>:v<integer> pattern" do
      key = described_class.new(base_params).send(:cache_key)
      expect(key).to match(/\Aexpense_filter:[a-f0-9]{32}:v\d+\z/)
    end

    it "embeds the Expense version (maximum updated_at as integer)" do
      expected_version = Expense.maximum(:updated_at).to_i
      key = described_class.new(base_params).send(:cache_key)
      expect(key).to end_with(":v#{expected_version}")
    end
  end
end
