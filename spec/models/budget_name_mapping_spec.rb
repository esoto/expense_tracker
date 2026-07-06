# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetNameMapping, :unit do
  describe ".normalize" do
    it "downcases, strips accents, and squishes whitespace" do
      expect(described_class.normalize("  Alimentación  Extra ")).to eq("alimentacion extra")
      expect(described_class.normalize("Condominio")).to eq("condominio")
      expect(described_class.normalize(nil)).to eq("")
    end
  end

  describe "validations" do
    it "enforces uniqueness of normalized_name per user" do
      existing = create(:budget_name_mapping)
      dup = build(:budget_name_mapping, user: existing.user, normalized_name: existing.normalized_name)
      expect(dup).not_to be_valid
    end

    it "requires a category when kind is category" do
      mapping = build(:budget_name_mapping, kind: :category, category: nil)
      expect(mapping).not_to be_valid
    end

    it "allows a nil category when kind is allocation" do
      mapping = build(:budget_name_mapping, kind: :allocation, category: nil, source: :llm)
      expect(mapping).to be_valid
    end
  end

  describe "#auto_applicable?" do
    it "is true for source user and source exact" do
      expect(build(:budget_name_mapping, source: :user).auto_applicable?).to be(true)
      expect(build(:budget_name_mapping, source: :exact).auto_applicable?).to be(true)
    end

    it "is false for fuzzy and llm suggestions" do
      expect(build(:budget_name_mapping, source: :fuzzy).auto_applicable?).to be(false)
      expect(build(:budget_name_mapping, source: :llm).auto_applicable?).to be(false)
    end
  end
end
