require "rails_helper"

RSpec.describe Services::EmailProcessing::DateParsingHelper, type: :module do
  # Use an anonymous class that includes the module so we can call parse_date directly
  let(:host_class) do
    Class.new do
      include Services::EmailProcessing::DateParsingHelper
      public :parse_date
    end
  end
  let(:helper) { host_class.new }

  describe "DATE_FORMATS constant", :unit do
    subject { described_class::DATE_FORMATS }

    it "is frozen" do
      expect(subject).to be_frozen
    end

    it "lists %d/%m/%Y as the first format (most common CR bank format)" do
      expect(subject.first).to eq("%d/%m/%Y")
    end

    it "includes the BAC abbreviated-month-with-time format" do
      expect(subject).to include("%b %d, %Y, %H:%M")
    end

    it "includes ISO 8601 format" do
      expect(subject).to include("%Y-%m-%d")
    end
  end

  describe "SPANISH_MONTHS constant", :unit do
    subject { described_class::SPANISH_MONTHS }

    it "is frozen" do
      expect(subject).to be_frozen
    end

    it "maps all twelve Spanish abbreviations" do
      expect(subject.keys).to match_array(%w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic])
    end

    it "maps Ago to Aug" do
      expect(subject["Ago"]).to eq("Aug")
    end

    it "maps Dic to Dec" do
      expect(subject["Dic"]).to eq("Dec")
    end
  end

  describe "#parse_date", :unit do
    context "with standard CR formats" do
      it "parses dd/mm/yyyy" do
        expect(helper.parse_date("03/08/2024")).to eq(Date.new(2024, 8, 3))
      end

      it "parses dd-mm-yyyy" do
        expect(helper.parse_date("03-08-2024")).to eq(Date.new(2024, 8, 3))
      end

      it "parses yyyy-mm-dd (ISO 8601)" do
        expect(helper.parse_date("2024-08-03")).to eq(Date.new(2024, 8, 3))
      end

      it "parses dd/mm/yyyy with time component" do
        expect(helper.parse_date("03/08/2024 14:30")).to eq(Date.new(2024, 8, 3))
      end

      it "parses dd-mm-yyyy with time component" do
        expect(helper.parse_date("03-08-2024 09:15")).to eq(Date.new(2024, 8, 3))
      end
    end

    context "with BAC abbreviated-month formats" do
      it "parses 'Aug 1, 2025, 14:16' (with time)" do
        expect(helper.parse_date("Aug 1, 2025, 14:16")).to eq(Date.new(2025, 8, 1))
      end

      it "parses 'Aug 1, 2025' (without time)" do
        expect(helper.parse_date("Aug 1, 2025")).to eq(Date.new(2025, 8, 1))
      end
    end

    context "with Spanish month abbreviations" do
      it "parses Ago (August)" do
        expect(helper.parse_date("Ago 1, 2025, 14:16")).to eq(Date.new(2025, 8, 1))
      end

      it "parses Ene (January)" do
        expect(helper.parse_date("Ene 15, 2025")).to eq(Date.new(2025, 1, 15))
      end

      it "parses Dic (December)" do
        expect(helper.parse_date("Dic 25, 2024")).to eq(Date.new(2024, 12, 25))
      end
    end

    context "with Chronic fallback" do
      it "returns nil when Chronic cannot parse the string" do
        allow(Chronic).to receive(:parse).and_return(nil)
        expect(helper.parse_date("some unrecognized text")).to be_nil
      end

      it "uses Chronic as fallback and converts result to Date" do
        tomorrow = Time.current + 1.day
        allow(Chronic).to receive(:parse).with("tomorrow").and_return(tomorrow)
        expect(helper.parse_date("tomorrow")).to eq(tomorrow.to_date)
      end

      it "returns nil when Chronic raises a StandardError" do
        allow(Chronic).to receive(:parse).and_raise(StandardError, "parse error")
        expect(helper.parse_date("bad input")).to be_nil
      end
    end

    context "with leading/trailing whitespace" do
      it "strips whitespace before parsing" do
        expect(helper.parse_date("  03/08/2024  ")).to eq(Date.new(2024, 8, 3))
      end
    end

    context "with empty or unparseable input" do
      it "returns nil for empty string" do
        expect(helper.parse_date("")).to be_nil
      end

      it "returns nil for a non-date string" do
        expect(helper.parse_date("not a date")).to be_nil
      end
    end
  end
end
