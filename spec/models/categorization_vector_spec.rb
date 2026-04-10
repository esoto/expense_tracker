require "rails_helper"

RSpec.describe CategorizationVector, type: :model, unit: true do
  let(:category) { create(:category) }

  describe "validations" do
    it "requires merchant_normalized" do
      vector = CategorizationVector.new(category: category, merchant_normalized: nil)
      expect(vector).not_to be_valid
      expect(vector.errors[:merchant_normalized]).to be_present
    end

    it "requires category" do
      vector = CategorizationVector.new(merchant_normalized: "test merchant")
      expect(vector).not_to be_valid
      expect(vector.errors[:category]).to be_present
    end

    it "enforces uniqueness of merchant_normalized per category" do
      CategorizationVector.create!(merchant_normalized: "walmart", category: category)
      duplicate = CategorizationVector.new(merchant_normalized: "walmart", category: category)
      expect(duplicate).not_to be_valid
    end

    it "allows same merchant with different categories" do
      other_category = create(:category, name: "Other", i18n_key: "other_vec_test")
      CategorizationVector.create!(merchant_normalized: "walmart", category: category)
      different = CategorizationVector.new(merchant_normalized: "walmart", category: other_category)
      expect(different).to be_valid
    end
  end

  describe "defaults" do
    it "defaults occurrence_count to 1" do
      vector = CategorizationVector.create!(merchant_normalized: "test", category: category)
      expect(vector.occurrence_count).to eq(1)
    end

    it "defaults correction_count to 0" do
      vector = CategorizationVector.create!(merchant_normalized: "test", category: category)
      expect(vector.correction_count).to eq(0)
    end

    it "defaults confidence to 0.5" do
      vector = CategorizationVector.create!(merchant_normalized: "test", category: category)
      expect(vector.confidence).to eq(0.5)
    end

    it "defaults description_keywords to empty array" do
      vector = CategorizationVector.create!(merchant_normalized: "test", category: category)
      expect(vector.description_keywords).to eq([])
    end
  end

  describe ".for_merchant" do
    before do
      CategorizationVector.create!(merchant_normalized: "walmart supercenter", category: category)
      CategorizationVector.create!(merchant_normalized: "walgreens pharmacy", category: category)
    end

    it "finds similar merchants using pg_trgm" do
      results = CategorizationVector.for_merchant("walmart")
      expect(results.map(&:merchant_normalized)).to include("walmart supercenter")
    end

    it "limits results to 5" do
      6.times do |i|
        CategorizationVector.create!(
          merchant_normalized: "walmart store #{i}",
          category: create(:category, name: "Cat#{i}", i18n_key: "cat_#{i}")
        )
      end
      expect(CategorizationVector.for_merchant("walmart").count).to be <= 5
    end
  end

  describe ".stale" do
    it "finds vectors not seen in 6+ months" do
      old = CategorizationVector.create!(merchant_normalized: "old store", category: category, last_seen_at: 7.months.ago)
      recent = CategorizationVector.create!(merchant_normalized: "new store", category: category, last_seen_at: 1.day.ago)

      stale = CategorizationVector.stale
      expect(stale).to include(old)
      expect(stale).not_to include(recent)
    end
  end
end
