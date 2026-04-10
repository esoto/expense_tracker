# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Strategies::SimilarityStrategy, type: :service, unit: true do
  subject(:strategy) { described_class.new }

  describe "#layer_name" do
    it "returns 'pg_trgm'" do
      expect(strategy.layer_name).to eq("pg_trgm")
    end
  end

  describe "#call" do
    let(:category) { create(:category, name: "Groceries") }
    let(:other_category) { create(:category, name: "Restaurants") }

    context "when expense has no merchant_name" do
      let(:expense) { build(:expense, merchant_name: nil) }

      it "returns no_match result" do
        result = strategy.call(expense)

        expect(result).to be_no_match
        expect(result.method).to eq("no_match")
      end
    end

    context "when expense has blank merchant_name" do
      let(:expense) { build(:expense, merchant_name: "  ") }

      it "returns no_match result" do
        result = strategy.call(expense)

        expect(result).to be_no_match
      end
    end

    context "when no similar vectors exist" do
      let(:expense) { build(:expense, merchant_name: "Completely Unknown Store") }

      it "returns no_match result" do
        result = strategy.call(expense)

        expect(result).to be_no_match
      end
    end

    context "when an exact merchant match exists with high occurrence" do
      let(:expense) { build(:expense, merchant_name: "walmart") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart",
               category: category,
               occurrence_count: 10,
               confidence: 0.9)
      end

      it "returns a successful result with high confidence" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.confidence).to be > 0.9
        expect(result.method).to eq("pg_trgm_similarity")
      end
    end

    context "when a similar merchant exists (e.g., 'walmart' matches 'walmart supercenter')" do
      let(:expense) { build(:expense, merchant_name: "walmart") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart supercenter",
               category: category,
               occurrence_count: 5,
               confidence: 0.8)
      end

      it "returns a successful result" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.method).to eq("pg_trgm_similarity")
      end
    end

    context "when multiple categories match with different scores" do
      let(:expense) { build(:expense, merchant_name: "walmart") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart",
               category: category,
               occurrence_count: 10,
               confidence: 0.9)
        create(:categorization_vector,
               merchant_normalized: "walmart pharmacy",
               category: other_category,
               occurrence_count: 3,
               confidence: 0.6)
      end

      it "returns the highest scoring category" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
      end
    end

    context "when occurrence_count is low (<=2) with moderate similarity" do
      let(:expense) { build(:expense, merchant_name: "walmart") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart",
               category: category,
               occurrence_count: 1,
               confidence: 0.5)
      end

      it "returns medium confidence instead of high" do
        result = strategy.call(expense)

        expect(result).to be_successful
        # similarity=1.0, but occurrence_count <= 2 so medium formula: 0.4 + 1.0 * 0.3 = 0.7
        expect(result.confidence).to be <= 0.75
      end
    end

    context "when similarity is low (between 0.3 and 0.4)" do
      let(:expense) { build(:expense, merchant_name: "wal") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart supercenter groceries",
               category: category,
               occurrence_count: 10,
               confidence: 0.9)
      end

      it "returns low confidence" do
        result = strategy.call(expense)

        # If similarity is below 0.4, low confidence: similarity * 0.5
        # If no vectors match at all (below 0.3 threshold), no_match
        if result.no_match?
          expect(result).to be_no_match
        else
          expect(result.confidence).to be < 0.4
        end
      end
    end

    context "when multiple categories have close similarity scores" do
      let(:expense) { build(:expense, merchant_name: "walmart supercenter", description: "groceries shopping") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart supercenter",
               category: category,
               occurrence_count: 5,
               description_keywords: %w[groceries food shopping],
               confidence: 0.8)
        create(:categorization_vector,
               merchant_normalized: "walmart supercenter",
               category: other_category,
               occurrence_count: 5,
               description_keywords: %w[pharmacy medicine],
               confidence: 0.8)
      end

      it "uses description_keywords as tiebreaker when scores are within 0.1" do
        result = strategy.call(expense)

        expect(result).to be_successful
        # Both vectors have identical merchant_normalized so identical similarity.
        # The category with matching description_keywords should win the tiebreak
        # (groceries + shopping overlap with the grocery category's keywords)
        expect(result.category).to eq(category)
      end
    end

    context "when merchant_name has special characters" do
      let(:expense) { build(:expense, merchant_name: "Walmart® Super-Center!") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart supercenter",
               category: category,
               occurrence_count: 10,
               confidence: 0.9)
      end

      it "normalizes the merchant name and still matches" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
      end
    end

    context "result metadata" do
      let(:expense) { build(:expense, merchant_name: "walmart") }

      before do
        create(:categorization_vector,
               merchant_normalized: "walmart",
               category: category,
               occurrence_count: 10,
               confidence: 0.9)
      end

      it "includes similarity score and vector info in metadata" do
        result = strategy.call(expense)

        expect(result.metadata).to include(:similarity_score, :vector_id)
      end

      it "tracks processing time" do
        result = strategy.call(expense)

        expect(result.processing_time_ms).to be >= 0
      end
    end
  end
end
