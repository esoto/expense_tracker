# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternImporter, type: :service, unit: true do
  subject(:service) { described_class.new }

  let(:category) { create(:category, name: "Food & Dining") }

  # Helper: build a Tempfile with CSV content
  def csv_tempfile(content)
    tmp = Tempfile.new([ "patterns", ".csv" ])
    tmp.write(content)
    tmp.rewind
    tmp
  end

  describe "#import" do
    context "when file is nil" do
      it "returns a failure result" do
        result = service.import(nil)
        expect(result).to eq({ success: false, error: "No file provided" })
      end
    end

    context "when file is missing required headers" do
      it "returns an error listing the missing headers" do
        file = csv_tempfile("pattern_type,pattern_value\nmerchant,Starbucks\n")
        result = service.import(file)

        expect(result[:success]).to be false
        expect(result[:error]).to include("category_name")
      end
    end

    context "when CSV is malformed" do
      it "returns an invalid CSV format error" do
        file = csv_tempfile("pattern_type,pattern_value,category_name\n\"unclosed quote,foo,bar\n")
        result = service.import(file)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Invalid CSV format|import failed/i)
      end
    end

    context "with a valid CSV" do
      before { category }

      it "creates patterns and returns the imported count" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,Starbucks,Food & Dining\n"
        )

        expect { service.import(file) }
          .to change(CategorizationPattern, :count).by(1)

        result = service.import(csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,BurgerKing,Food & Dining\n"
        ))

        expect(result[:success]).to be true
        expect(result[:imported_count]).to eq(1)
      end

      it "sets user_created to true on imported patterns" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "keyword,coffee,Food & Dining\n"
        )
        service.import(file)

        pattern = CategorizationPattern.find_by(pattern_value: "coffee")
        expect(pattern.user_created).to be true
      end

      it "uses the provided confidence_weight column" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name,confidence_weight\n" \
          "keyword,juice,Food & Dining,3.0\n"
        )
        service.import(file)

        pattern = CategorizationPattern.find_by(pattern_value: "juice")
        expect(pattern.confidence_weight).to eq(3.0)
      end

      it "defaults confidence_weight to DEFAULT_CONFIDENCE_WEIGHT when blank" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name,confidence_weight\n" \
          "keyword,tea,Food & Dining,\n"
        )
        service.import(file)

        pattern = CategorizationPattern.find_by(pattern_value: "tea")
        expect(pattern.confidence_weight).to eq(CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT)
      end

      it "clamps confidence_weight to allowed range" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name,confidence_weight\n" \
          "keyword,espresso,Food & Dining,999\n"
        )
        service.import(file)

        pattern = CategorizationPattern.find_by(pattern_value: "espresso")
        expect(pattern.confidence_weight).to eq(CategorizationPattern::MAX_CONFIDENCE_WEIGHT)
      end

      it "parses the active column" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name,active\n" \
          "keyword,inactive_drink,Food & Dining,false\n"
        )
        service.import(file)

        pattern = CategorizationPattern.find_by(pattern_value: "inactive_drink")
        expect(pattern.active).to be false
      end
    end

    context "when category does not exist" do
      it "returns a failure result with a descriptive error" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,Nowhere,Nonexistent Category\n"
        )

        result = service.import(file)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end

      it "does not persist any patterns (transaction rollback)" do
        category # ensure category exists for first row
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,Starbucks,Food & Dining\n" \
          "merchant,BurgerKing,Nonexistent Category\n"
        )

        expect { service.import(file) }
          .not_to change(CategorizationPattern, :count)
      end
    end

    context "when a pattern is a duplicate" do
      before do
        category
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "Starbucks",
               category: category)
      end

      it "skips the duplicate and does not count it as imported" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,Starbucks,Food & Dining\n"
        )

        result = service.import(file)
        # Duplicate skips without error, so whole transaction commits with 0 imports
        expect(result[:success]).to be true
        expect(result[:imported_count]).to eq(0)
      end
    end

    context "when a row has invalid data" do
      before { category }

      it "returns a failure result for invalid pattern type" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "invalid_type,value,Food & Dining\n"
        )

        result = service.import(file)
        expect(result[:success]).to be false
      end

      it "returns failure when required fields are blank" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          ",,Food & Dining\n"
        )

        result = service.import(file)
        expect(result[:success]).to be false
        expect(result[:error]).to include("required")
      end
    end

    context "with multiple valid rows" do
      before { category }

      it "imports all rows and returns total count" do
        file = csv_tempfile(
          "pattern_type,pattern_value,category_name\n" \
          "merchant,McDonald's,Food & Dining\n" \
          "keyword,burger,Food & Dining\n" \
          "description,fast food,Food & Dining\n"
        )

        result = service.import(file)
        expect(result[:success]).to be true
        expect(result[:imported_count]).to eq(3)
      end
    end
  end
end
