# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternExporter, type: :service, unit: true do
  subject(:service) { described_class.new }

  describe "#export_to_csv" do
    context "when there are no active patterns" do
      before do
        # Ensure only inactive patterns exist
        create(:categorization_pattern, :inactive)
      end

      it "returns a CSV string with only the header row" do
        csv = service.export_to_csv
        rows = CSV.parse(csv, headers: true)
        expect(rows.length).to eq(0)
      end

      it "includes all expected headers" do
        csv = service.export_to_csv
        headers = CSV.parse_line(csv)
        expect(headers).to eq(Services::Categorization::PatternExporter::CSV_HEADERS)
      end
    end

    context "when active patterns exist" do
      let(:category) { create(:category, name: "Restaurants") }
      let!(:active_pattern) do
        create(:categorization_pattern,
               pattern_type:      "merchant",
               pattern_value:     "Pizza Hut",
               category:          category,
               confidence_weight: 2.5,
               active:            true,
               usage_count:       100,
               success_count:     88,
               success_rate:      0.88)
      end
      let!(:inactive_pattern) { create(:categorization_pattern, :inactive, category: category) }

      it "includes active patterns in the output" do
        csv  = service.export_to_csv
        rows = CSV.parse(csv, headers: true)

        expect(rows.length).to eq(1)
        # pattern_value is downcased by PatternValidation concern
        expect(rows.first["pattern_value"]).to eq("pizza hut")
      end

      it "excludes inactive patterns" do
        csv  = service.export_to_csv
        rows = CSV.parse(csv, headers: true)
        pattern_values = rows.map { |r| r["pattern_value"] }
        expect(pattern_values).not_to include(inactive_pattern.pattern_value)
      end

      it "exports the correct column values" do
        csv  = service.export_to_csv
        row  = CSV.parse(csv, headers: true).first

        expect(row["pattern_type"]).to eq("merchant")
        # pattern_value is downcased by PatternValidation concern
        expect(row["pattern_value"]).to eq("pizza hut")
        expect(row["category_name"]).to eq("Restaurants")
        expect(row["confidence_weight"].to_f).to eq(2.5)
        expect(row["active"]).to eq("true")
        expect(row["usage_count"].to_i).to eq(100)
        expect(row["success_rate"].to_f).to eq(0.88)
      end
    end

    context "with multiple patterns" do
      let(:cat_a) { create(:category, name: "Transport") }
      let(:cat_b) { create(:category, name: "Food") }

      before do
        create(:categorization_pattern, pattern_type: "merchant", pattern_value: "Uber",    category: cat_a, active: true)
        create(:categorization_pattern, pattern_type: "keyword",  pattern_value: "coffee",  category: cat_b, active: true)
        create(:categorization_pattern, pattern_type: "merchant", pattern_value: "AirBnb",  category: cat_a, active: true)
        create(:categorization_pattern, :inactive, category: cat_a)
      end

      it "returns only active patterns" do
        rows = CSV.parse(service.export_to_csv, headers: true)
        expect(rows.length).to eq(3)
      end

      it "orders rows by pattern_type then pattern_value" do
        rows   = CSV.parse(service.export_to_csv, headers: true)
        values = rows.map { |r| [ r["pattern_type"], r["pattern_value"] ] }

        # pattern_value is downcased by PatternValidation concern
        expected_order = [
          [ "keyword", "coffee" ],
          [ "merchant", "airbnb" ],
          [ "merchant", "uber" ]
        ]

        expect(values).to eq(expected_order)
      end

      it "returns a valid CSV string that can be re-parsed" do
        csv = service.export_to_csv
        expect { CSV.parse(csv) }.not_to raise_error
      end
    end

    context "when a pattern has no category (edge case)" do
      it "exports an empty string for category_name without raising" do
        category = create(:category, name: "Misc")
        pattern  = create(:categorization_pattern, category: category, active: true)
        # Simulate missing category association by stubbing
        allow(pattern).to receive(:category).and_return(nil)
        allow(CategorizationPattern).to receive_message_chain(:active, :includes, :order).and_return([ pattern ])

        csv  = service.export_to_csv
        row  = CSV.parse(csv, headers: true).first
        expect(row["category_name"]).to be_nil.or eq("")
      end
    end
  end
end
