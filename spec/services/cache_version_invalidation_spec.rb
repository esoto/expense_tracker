# frozen_string_literal: true

require "rails_helper"

# PER-125: Cache version key invalidation tests
# Ensures delete_matched (O(n) scan) is replaced with O(1) version key increments
RSpec.describe "Cache version key invalidation", type: :service do
  before { Rails.cache.clear }

  describe "Services::DashboardService cache version invalidation", :unit do
    describe ".cache_version" do
      it "returns a positive integer" do
        expect(Services::DashboardService.cache_version).to be_a(Integer)
        expect(Services::DashboardService.cache_version).to be >= 1
      end

      it "returns 1 when no version has been set yet" do
        Rails.cache.delete("dashboard_service:cache_version")
        expect(Services::DashboardService.cache_version).to eq(1)
      end
    end

    describe ".increment_cache_version!" do
      it "increments the cache version by 1" do
        original = Services::DashboardService.cache_version
        Services::DashboardService.increment_cache_version!
        expect(Services::DashboardService.cache_version).to eq(original + 1)
      end

      it "increments multiple times correctly" do
        Services::DashboardService.increment_cache_version!
        Services::DashboardService.increment_cache_version!
        Services::DashboardService.increment_cache_version!
        version_after = Services::DashboardService.cache_version
        Services::DashboardService.increment_cache_version!
        expect(Services::DashboardService.cache_version).to eq(version_after + 1)
      end
    end

    describe ".clear_cache" do
      it "does not call delete_matched on the cache" do
        expect(Rails.cache).not_to receive(:delete_matched)
        Services::DashboardService.clear_cache
      end

      it "increments the cache version instead of scanning keys" do
        version_before = Services::DashboardService.cache_version
        Services::DashboardService.clear_cache
        expect(Services::DashboardService.cache_version).to eq(version_before + 1)
      end
    end

    describe "cache key includes version" do
      it "uses versioned key for analytics cache" do
        version = Services::DashboardService.cache_version
        service = Services::DashboardService.new
        expect(service.send(:analytics_cache_key)).to include(version.to_s)
      end
    end
  end

  describe "Services::MetricsCalculator cache version invalidation", :unit do
    let(:email_account) { create(:email_account) }

    describe ".cache_version" do
      it "returns a positive integer" do
        expect(Services::MetricsCalculator.cache_version).to be_a(Integer)
        expect(Services::MetricsCalculator.cache_version).to be >= 1
      end

      it "returns 1 when no version has been set" do
        Rails.cache.delete("metrics_calculator:cache_version")
        expect(Services::MetricsCalculator.cache_version).to eq(1)
      end
    end

    describe ".cache_version_for_account" do
      it "returns a positive integer for a specific account" do
        expect(Services::MetricsCalculator.cache_version_for_account(email_account.id)).to be_a(Integer)
        expect(Services::MetricsCalculator.cache_version_for_account(email_account.id)).to be >= 1
      end

      it "returns 1 when no account version has been set" do
        Rails.cache.delete("metrics_calculator:account_#{email_account.id}:cache_version")
        expect(Services::MetricsCalculator.cache_version_for_account(email_account.id)).to eq(1)
      end
    end

    describe ".increment_cache_version!" do
      it "increments the global version by 1" do
        original = Services::MetricsCalculator.cache_version
        Services::MetricsCalculator.increment_cache_version!
        expect(Services::MetricsCalculator.cache_version).to eq(original + 1)
      end
    end

    describe ".increment_cache_version_for_account!" do
      it "increments the account-specific version by 1" do
        original = Services::MetricsCalculator.cache_version_for_account(email_account.id)
        Services::MetricsCalculator.increment_cache_version_for_account!(email_account.id)
        expect(Services::MetricsCalculator.cache_version_for_account(email_account.id)).to eq(original + 1)
      end

      it "does not affect the global version" do
        global_before = Services::MetricsCalculator.cache_version
        Services::MetricsCalculator.increment_cache_version_for_account!(email_account.id)
        expect(Services::MetricsCalculator.cache_version).to eq(global_before)
      end
    end

    describe ".clear_cache" do
      it "does not call delete_matched on the cache" do
        expect(Rails.cache).not_to receive(:delete_matched)
        Services::MetricsCalculator.clear_cache
      end

      it "increments global version when no email_account given" do
        version_before = Services::MetricsCalculator.cache_version
        Services::MetricsCalculator.clear_cache
        expect(Services::MetricsCalculator.cache_version).to eq(version_before + 1)
      end

      it "increments account version when email_account given" do
        account_version_before = Services::MetricsCalculator.cache_version_for_account(email_account.id)
        global_version_before = Services::MetricsCalculator.cache_version
        Services::MetricsCalculator.clear_cache(email_account: email_account)
        expect(Services::MetricsCalculator.cache_version_for_account(email_account.id)).to eq(account_version_before + 1)
        expect(Services::MetricsCalculator.cache_version).to eq(global_version_before)
      end
    end

    describe "instance cache key includes version" do
      it "uses versioned key that changes after invalidation" do
        calculator = Services::MetricsCalculator.new(email_account: email_account, period: :month)
        key_before = calculator.cache_key
        Services::MetricsCalculator.clear_cache(email_account: email_account)
        calculator_after = Services::MetricsCalculator.new(email_account: email_account, period: :month)
        expect(calculator_after.cache_key).not_to eq(key_before)
      end
    end
  end

  describe "PatternAnalytics cache version invalidation", :unit do
    describe "PatternAnalyticsCacheVersion.current" do
      it "returns a positive integer" do
        expect(PatternAnalyticsCacheVersion.current).to be_a(Integer)
        expect(PatternAnalyticsCacheVersion.current).to be >= 1
      end

      it "returns 1 when no version has been set" do
        Rails.cache.delete("pattern_analytics:cache_version")
        expect(PatternAnalyticsCacheVersion.current).to eq(1)
      end
    end

    describe "PatternAnalyticsCacheVersion.increment!" do
      it "increments the version by 1" do
        original = PatternAnalyticsCacheVersion.current
        PatternAnalyticsCacheVersion.increment!
        expect(PatternAnalyticsCacheVersion.current).to eq(original + 1)
      end
    end

    describe "CategorizationPattern#invalidate_cache" do
      let(:category) { create(:category) }
      let(:pattern) { create(:categorization_pattern, category: category) }

      it "does not call delete_matched on Rails.cache" do
        expect(Rails.cache).not_to receive(:delete_matched)
        pattern.send(:invalidate_cache)
      end

      it "increments the pattern analytics cache version" do
        # Record version after creation (creation itself may trigger invalidate_cache via callbacks)
        version_before = PatternAnalyticsCacheVersion.current
        pattern.send(:invalidate_cache)
        expect(PatternAnalyticsCacheVersion.current).to be > version_before
      end
    end

    describe "PatternFeedback#invalidate_analytics_cache" do
      let(:category) { create(:category) }
      let(:email_account) { create(:email_account) }
      let(:expense) { create(:expense, email_account: email_account, category: category) }
      let(:feedback) { build(:pattern_feedback, expense: expense, category: category, feedback_type: "accepted", was_correct: true) }

      it "does not call delete_matched on Rails.cache" do
        expect(Rails.cache).not_to receive(:delete_matched)
        feedback.send(:invalidate_analytics_cache)
      end

      it "increments the pattern analytics cache version" do
        version_before = PatternAnalyticsCacheVersion.current
        feedback.send(:invalidate_analytics_cache)
        expect(PatternAnalyticsCacheVersion.current).to eq(version_before + 1)
      end
    end

    describe "PatternLearningEvent#invalidate_analytics_cache" do
      let(:category) { create(:category) }
      let(:email_account) { create(:email_account) }
      let(:expense) { create(:expense, email_account: email_account, category: category) }
      let(:event) { build(:pattern_learning_event, expense: expense, category: category) }

      it "does not call delete_matched on Rails.cache" do
        expect(Rails.cache).not_to receive(:delete_matched)
        event.send(:invalidate_analytics_cache)
      end

      it "increments the pattern analytics cache version" do
        version_before = PatternAnalyticsCacheVersion.current
        event.send(:invalidate_analytics_cache)
        expect(PatternAnalyticsCacheVersion.current).to eq(version_before + 1)
      end
    end
  end

  describe "Services::Categorization::PatternCache version invalidation", :unit do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:pattern_cache) { Services::Categorization::PatternCache.new(warm_cache: false) }

    describe "#invalidate_category" do
      it "does not call delete_matched on memory_cache" do
        mc = pattern_cache.instance_variable_get(:@memory_cache)
        expect(mc).not_to receive(:delete_matched)
        pattern_cache.invalidate_category(1)
      end

      it "increments the memory cache version for patterns" do
        version_before = pattern_cache.send(:pattern_cache_version)
        pattern_cache.invalidate_category(1)
        expect(pattern_cache.send(:pattern_cache_version)).to eq(version_before + 1)
      end
    end
  end
end
