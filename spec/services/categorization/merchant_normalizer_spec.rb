# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::MerchantNormalizer, type: :service, unit: true do
  describe ".normalize" do
    it "downcases the name" do
      expect(described_class.normalize("WALMART")).to eq("walmart")
    end

    it "strips leading and trailing whitespace" do
      expect(described_class.normalize("  walmart  ")).to eq("walmart")
    end

    it "removes special characters" do
      expect(described_class.normalize("Walmart® Super-Center!")).to eq("walmart supercenter")
    end

    it "preserves spaces between words" do
      expect(described_class.normalize("Walmart Super Center")).to eq("walmart super center")
    end

    it "collapses multiple spaces" do
      expect(described_class.normalize("walmart   super   center")).to eq("walmart super center")
    end

    it "handles nil by returning empty string" do
      expect(described_class.normalize(nil)).to eq("")
    end

    it "handles empty string" do
      expect(described_class.normalize("")).to eq("")
    end

    it "removes numbers' special chars but keeps digits" do
      expect(described_class.normalize("Store #123")).to eq("store 123")
    end
  end
end
