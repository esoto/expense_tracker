# frozen_string_literal: true

require "rails_helper"

RSpec.describe Expense, "#clear_dashboard_cache conditional invalidation", type: :model, unit: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:expense) do
    create(:expense,
      email_account: email_account,
      amount: 100.0,
      transaction_date: Date.current,
      status: :pending,
      description: "Original description",
      merchant_name: "Original Merchant")
  end

  before do
    # Allow MetricsRefreshJob to be called freely so it doesn't interfere
    allow(MetricsRefreshJob).to receive(:enqueue_debounced)
    # Ensure expense record exists before each test
    expense
  end

  describe "cache-relevant attribute changes — cache IS cleared" do
    it "clears cache when amount changes" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(amount: 250.0)
    end

    it "clears cache when category_id changes" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(category: category)
    end

    it "clears cache when transaction_date changes" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(transaction_date: 1.week.ago.to_date)
    end

    it "clears cache when status changes" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(status: :processed)
    end

    it "clears cache when email_account_id changes" do
      new_account = create(:email_account, email: "other_#{SecureRandom.hex(4)}@example.com")
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(email_account: new_account)
    end

    it "clears cache when deleted_at changes (soft delete)" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      expense.update!(deleted_at: Time.current)
    end

    it "clears cache on create" do
      expect(Services::DashboardService).to receive(:clear_cache).once
      create(:expense, email_account: email_account)
    end
  end

  describe "non-relevant attribute changes — cache is NOT cleared" do
    it "does not clear cache when only description changes" do
      expect(Services::DashboardService).not_to receive(:clear_cache)
      expense.update!(description: "Updated description only")
    end

    it "does not clear cache when only merchant_name changes" do
      expect(Services::DashboardService).not_to receive(:clear_cache)
      expense.update!(merchant_name: "New Merchant Name")
    end

    it "does not clear cache when both description and merchant_name change" do
      expect(Services::DashboardService).not_to receive(:clear_cache)
      expense.update!(description: "New desc", merchant_name: "New merchant")
    end
  end

  context "when expense is destroyed" do
    it "clears cache on destroy" do
      expect(Services::DashboardService).to receive(:clear_cache).at_least(:once)
      expense.destroy!
    end
  end
end
