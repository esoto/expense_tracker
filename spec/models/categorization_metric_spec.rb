require "rails_helper"

RSpec.describe CategorizationMetric, type: :model, unit: true do
  let(:expense) { create(:expense) }
  let(:category) { create(:category) }

  describe "validations" do
    it "requires layer_used" do
      metric = CategorizationMetric.new(expense: expense, layer_used: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:layer_used]).to be_present
    end

    it "requires expense" do
      metric = CategorizationMetric.new(layer_used: "pattern")
      expect(metric).not_to be_valid
      expect(metric.errors[:expense]).to be_present
    end

    it "validates layer_used inclusion" do
      %w[pattern pg_trgm haiku manual].each do |layer|
        metric = CategorizationMetric.new(expense: expense, layer_used: layer)
        metric.valid?
        expect(metric.errors[:layer_used]).to be_empty
      end

      metric = CategorizationMetric.new(expense: expense, layer_used: "invalid")
      expect(metric).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to expense" do
      metric = CategorizationMetric.create!(expense: expense, layer_used: "pattern", category: category)
      expect(metric.expense).to eq(expense)
    end

    it "belongs to category (optional)" do
      metric = CategorizationMetric.create!(expense: expense, layer_used: "pattern")
      expect(metric.category).to be_nil
    end

    it "belongs to corrected_to_category (optional)" do
      other_category = create(:category, name: "Other", i18n_key: "other_test")
      metric = CategorizationMetric.create!(
        expense: expense, layer_used: "pattern",
        category: category, was_corrected: true,
        corrected_to_category: other_category
      )
      expect(metric.corrected_to_category).to eq(other_category)
    end
  end

  describe "scopes" do
    before do
      CategorizationMetric.create!(expense: expense, layer_used: "pattern", was_corrected: false)
      CategorizationMetric.create!(expense: create(:expense), layer_used: "haiku", was_corrected: true)
    end

    it ".corrected returns only corrected metrics" do
      expect(CategorizationMetric.corrected.count).to eq(1)
      expect(CategorizationMetric.corrected.first.layer_used).to eq("haiku")
    end

    it ".uncorrected returns only uncorrected metrics" do
      expect(CategorizationMetric.uncorrected.count).to eq(1)
      expect(CategorizationMetric.uncorrected.first.layer_used).to eq("pattern")
    end

    it ".for_layer filters by layer" do
      expect(CategorizationMetric.for_layer("pattern").count).to eq(1)
      expect(CategorizationMetric.for_layer("haiku").count).to eq(1)
      expect(CategorizationMetric.for_layer("pg_trgm").count).to eq(0)
    end

    it ".recent filters by period" do
      old = CategorizationMetric.create!(expense: create(:expense), layer_used: "manual")
      old.update_columns(created_at: 60.days.ago)

      expect(CategorizationMetric.recent(30.days).count).to eq(2)
    end
  end

  describe "defaults" do
    it "defaults was_corrected to false" do
      metric = CategorizationMetric.create!(expense: expense, layer_used: "pattern")
      expect(metric.was_corrected).to be false
    end

    it "defaults api_cost to 0" do
      metric = CategorizationMetric.create!(expense: expense, layer_used: "pattern")
      expect(metric.api_cost).to eq(0)
    end
  end
end
