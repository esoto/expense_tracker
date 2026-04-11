# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Llm::ResponseParser, :unit do
  subject(:parser) { described_class.new }

  describe "#parse" do
    context "with an exact match" do
      let(:category) { create(:category, i18n_key: "food") }

      it "returns the matching category with fixed confidence" do
        allow(Category).to receive(:find_by).with(i18n_key: "food").and_return(category)

        result = parser.parse(response_text: "food")

        expect(result[:category]).to eq(category)
        expect(result[:confidence]).to eq(0.85)
        expect(result[:raw_response]).to eq("food")
      end
    end

    context "with leading/trailing whitespace" do
      let(:category) { create(:category, i18n_key: "restaurants") }

      it "strips whitespace and matches" do
        allow(Category).to receive(:find_by).with(i18n_key: "restaurants").and_return(category)

        result = parser.parse(response_text: "  restaurants  ")

        expect(result[:category]).to eq(category)
        expect(result[:confidence]).to eq(0.85)
      end
    end

    context "with newlines in the response" do
      let(:category) { create(:category, i18n_key: "transport") }

      it "strips newlines and matches" do
        allow(Category).to receive(:find_by).with(i18n_key: "transport").and_return(category)

        result = parser.parse(response_text: "\ntransport\n")

        expect(result[:category]).to eq(category)
        expect(result[:confidence]).to eq(0.85)
      end
    end

    context "with an unknown category key" do
      it "returns nil category with zero confidence" do
        allow(Category).to receive(:find_by).with(i18n_key: "nonexistent_category").and_return(nil)

        result = parser.parse(response_text: "nonexistent_category")

        expect(result[:category]).to be_nil
        expect(result[:confidence]).to eq(0.0)
        expect(result[:raw_response]).to eq("nonexistent_category")
      end
    end

    context "with an empty response" do
      it "returns nil category with zero confidence" do
        result = parser.parse(response_text: "")

        expect(result[:category]).to be_nil
        expect(result[:confidence]).to eq(0.0)
        expect(result[:raw_response]).to eq("")
      end
    end

    context "with a nil response" do
      it "returns nil category with zero confidence" do
        result = parser.parse(response_text: nil)

        expect(result[:category]).to be_nil
        expect(result[:confidence]).to eq(0.0)
        expect(result[:raw_response]).to be_nil
      end
    end

    context "with mixed case response" do
      let(:category) { create(:category, i18n_key: "food") }

      it "downcases and matches" do
        allow(Category).to receive(:find_by).with(i18n_key: "food").and_return(category)

        result = parser.parse(response_text: "Food")

        expect(result[:category]).to eq(category)
        expect(result[:confidence]).to eq(0.85)
      end
    end

    context "with response containing extra text" do
      it "extracts the first line as the category key" do
        allow(Category).to receive(:find_by).with(i18n_key: "food").and_return(nil)

        result = parser.parse(response_text: "food\nThis is an explanation")

        expect(result[:raw_response]).to eq("food\nThis is an explanation")
      end
    end
  end
end
