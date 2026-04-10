require "rails_helper"

RSpec.describe LlmCategorizationCacheEntry, type: :model, unit: true do
  let(:category) { create(:category) }

  describe "validations" do
    it "requires merchant_normalized" do
      entry = LlmCategorizationCacheEntry.new(category: category, merchant_normalized: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:merchant_normalized]).to be_present
    end

    it "requires category" do
      entry = LlmCategorizationCacheEntry.new(merchant_normalized: "test")
      expect(entry).not_to be_valid
      expect(entry.errors[:category]).to be_present
    end

    it "enforces uniqueness of merchant_normalized" do
      LlmCategorizationCacheEntry.create!(merchant_normalized: "uber eats", category: category, expires_at: 90.days.from_now)
      duplicate = LlmCategorizationCacheEntry.new(merchant_normalized: "uber eats", category: category)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults model_used to claude-haiku-4-5" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category, expires_at: 90.days.from_now)
      expect(entry.model_used).to eq("claude-haiku-4-5")
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is in the past" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category, expires_at: 1.day.ago)
      expect(entry).to be_expired
    end

    it "returns false when expires_at is in the future" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category, expires_at: 1.day.from_now)
      expect(entry).not_to be_expired
    end

    it "returns false when expires_at is nil" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category)
      expect(entry).not_to be_expired
    end
  end

  describe "#refresh_ttl!" do
    it "updates expires_at to 90 days from now" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category, expires_at: 10.days.from_now)
      entry.refresh_ttl!
      expect(entry.expires_at).to be_within(1.minute).of(90.days.from_now)
    end

    it "accepts custom TTL" do
      entry = LlmCategorizationCacheEntry.create!(merchant_normalized: "test", category: category, expires_at: 10.days.from_now)
      entry.refresh_ttl!(30.days)
      expect(entry.expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  describe "scopes" do
    before do
      LlmCategorizationCacheEntry.create!(merchant_normalized: "active", category: category, expires_at: 30.days.from_now)
      LlmCategorizationCacheEntry.create!(merchant_normalized: "expired", category: category, expires_at: 1.day.ago)
    end

    it ".active returns non-expired entries" do
      expect(LlmCategorizationCacheEntry.active.count).to eq(1)
      expect(LlmCategorizationCacheEntry.active.first.merchant_normalized).to eq("active")
    end

    it ".expired returns expired entries" do
      expect(LlmCategorizationCacheEntry.expired.count).to eq(1)
      expect(LlmCategorizationCacheEntry.expired.first.merchant_normalized).to eq("expired")
    end
  end
end
