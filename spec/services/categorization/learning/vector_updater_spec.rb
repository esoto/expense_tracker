# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Learning::VectorUpdater, type: :service, unit: true do
  let(:category) { create(:category) }
  let(:other_category) { create(:category) }
  let(:updater) { described_class.new }

  describe "#upsert" do
    context "when vector does not exist" do
      it "creates a new categorization vector" do
        expect {
          updater.upsert(merchant: "Walmart Escazú", category: category)
        }.to change(CategorizationVector, :count).by(1)
      end

      it "normalizes the merchant name" do
        vector = updater.upsert(merchant: "Walmart Escazú!!", category: category)

        expect(vector.merchant_normalized).to eq("walmart escaz")
      end

      it "sets default values on new vector" do
        vector = updater.upsert(merchant: "Walmart", category: category)

        expect(vector.occurrence_count).to eq(1)
        expect(vector.confidence).to eq(0.5)
        expect(vector.last_seen_at).to be_within(2.seconds).of(Time.current)
        expect(vector.correction_count).to eq(0)
      end

      it "stores description keywords" do
        vector = updater.upsert(
          merchant: "Walmart",
          category: category,
          description_keywords: %w[groceries food weekly]
        )

        expect(vector.description_keywords).to eq(%w[groceries food weekly])
      end

      it "returns the vector record" do
        result = updater.upsert(merchant: "Walmart", category: category)

        expect(result).to be_a(CategorizationVector)
        expect(result).to be_persisted
      end
    end

    context "when vector already exists" do
      let!(:existing_vector) do
        CategorizationVector.create!(
          merchant_normalized: "walmart",
          category: category,
          occurrence_count: 3,
          correction_count: 1,
          confidence: 0.5,
          description_keywords: %w[groceries food],
          last_seen_at: 1.week.ago
        )
      end

      it "increments occurrence_count" do
        updater.upsert(merchant: "Walmart", category: category)

        expect(existing_vector.reload.occurrence_count).to eq(4)
      end

      it "updates last_seen_at" do
        updater.upsert(merchant: "Walmart", category: category)

        expect(existing_vector.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
      end

      it "merges description keywords without duplicates" do
        updater.upsert(
          merchant: "Walmart",
          category: category,
          description_keywords: %w[food snacks beverages]
        )

        expect(existing_vector.reload.description_keywords).to match_array(
          %w[groceries food snacks beverages]
        )
      end

      it "does not create a new record" do
        expect {
          updater.upsert(merchant: "Walmart", category: category)
        }.not_to change(CategorizationVector, :count)
      end
    end

    context "keyword cap at 20" do
      let!(:existing_vector) do
        CategorizationVector.create!(
          merchant_normalized: "walmart",
          category: category,
          occurrence_count: 1,
          confidence: 0.5,
          description_keywords: (1..18).map { |i| "keyword#{i}" },
          last_seen_at: 1.day.ago
        )
      end

      it "caps keywords at 20" do
        updater.upsert(
          merchant: "Walmart",
          category: category,
          description_keywords: %w[new1 new2 new3 new4 new5]
        )

        expect(existing_vector.reload.description_keywords.size).to eq(20)
      end
    end

    context "with nil or blank merchant" do
      it "returns nil for nil merchant" do
        result = updater.upsert(merchant: nil, category: category)

        expect(result).to be_nil
      end

      it "returns nil for blank merchant" do
        result = updater.upsert(merchant: "   ", category: category)

        expect(result).to be_nil
      end

      it "does not create a vector for blank merchant" do
        expect {
          updater.upsert(merchant: "", category: category)
        }.not_to change(CategorizationVector, :count)
      end
    end

    context "with nil category" do
      it "returns nil" do
        result = updater.upsert(merchant: "Walmart", category: nil)

        expect(result).to be_nil
      end
    end
  end

  describe "#record_correction" do
    context "when old vector exists" do
      let!(:old_vector) do
        CategorizationVector.create!(
          merchant_normalized: "walmart",
          category: category,
          occurrence_count: 5,
          correction_count: 1,
          confidence: 0.5,
          description_keywords: [],
          last_seen_at: 1.day.ago
        )
      end

      it "increments correction_count on the old vector" do
        updater.record_correction(
          merchant: "Walmart",
          old_category: category,
          new_category: other_category
        )

        expect(old_vector.reload.correction_count).to eq(2)
      end

      it "creates a new vector for the new category" do
        expect {
          updater.record_correction(
            merchant: "Walmart",
            old_category: category,
            new_category: other_category
          )
        }.to change(CategorizationVector, :count).by(1)
      end

      it "returns old_vector and new_vector" do
        result = updater.record_correction(
          merchant: "Walmart",
          old_category: category,
          new_category: other_category
        )

        expect(result[:old_vector]).to eq(old_vector)
        expect(result[:new_vector]).to be_a(CategorizationVector)
        expect(result[:new_vector].category).to eq(other_category)
      end
    end

    context "when old vector does not exist" do
      it "still creates the new vector" do
        expect {
          updater.record_correction(
            merchant: "Walmart",
            old_category: category,
            new_category: other_category
          )
        }.to change(CategorizationVector, :count).by(1)
      end

      it "returns nil for old_vector" do
        result = updater.record_correction(
          merchant: "Walmart",
          old_category: category,
          new_category: other_category
        )

        expect(result[:old_vector]).to be_nil
        expect(result[:new_vector]).to be_a(CategorizationVector)
      end
    end

    context "when new vector already exists" do
      let!(:old_vector) do
        CategorizationVector.create!(
          merchant_normalized: "walmart",
          category: category,
          occurrence_count: 5,
          correction_count: 0,
          confidence: 0.5,
          description_keywords: [],
          last_seen_at: 1.day.ago
        )
      end

      let!(:existing_new_vector) do
        CategorizationVector.create!(
          merchant_normalized: "walmart",
          category: other_category,
          occurrence_count: 2,
          correction_count: 0,
          confidence: 0.5,
          description_keywords: [],
          last_seen_at: 2.days.ago
        )
      end

      it "increments the existing new vector instead of creating" do
        expect {
          updater.record_correction(
            merchant: "Walmart",
            old_category: category,
            new_category: other_category
          )
        }.not_to change(CategorizationVector, :count)

        expect(existing_new_vector.reload.occurrence_count).to eq(3)
      end
    end

    context "with nil or blank merchant" do
      it "returns nil for nil merchant" do
        result = updater.record_correction(
          merchant: nil,
          old_category: category,
          new_category: other_category
        )

        expect(result).to be_nil
      end
    end
  end
end
