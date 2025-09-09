# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::CategorizationResult, unit: true do
  let(:category) { build(:category, name: "Food & Dining") }
  let(:alternative_category) { build(:category, name: "Groceries") }

  # Test data for complex scenarios
  let(:patterns_used) { [ "merchant:Starbucks", "keyword:coffee" ] }
  let(:confidence_breakdown) do
    {
      merchant_match: { value: 0.8, contribution: 0.6 },
      historical_data: { value: 0.7, contribution: 0.4 }
    }
  end
  let(:alternative_categories) do
    [
      { category: alternative_category, confidence: 0.65 }
    ]
  end
  let(:metadata) { { source: "pattern_engine", version: "v2.1" } }

  describe "#initialize" do
    context "with default parameters" do
      subject { described_class.new }

      it "initializes with default values" do
        expect(subject.category).to be_nil
        expect(subject.confidence).to eq(0.0)
        expect(subject.patterns_used).to eq([])
        expect(subject.confidence_breakdown).to eq({})
        expect(subject.alternative_categories).to eq([])
        expect(subject.processing_time_ms).to eq(0.0)
        expect(subject.cache_hits).to eq(0)
        expect(subject.method).to be_nil
        expect(subject.error).to be_nil
        expect(subject.metadata).to eq({})
      end

      it "sets created_at timestamp" do
        freeze_time do
          result = described_class.new
          expect(result.instance_variable_get(:@created_at)).to eq(Time.current)
        end
      end
    end

    context "with all parameters provided" do
      subject do
        described_class.new(
          category: category,
          confidence: 0.85,
          patterns_used: patterns_used,
          confidence_breakdown: confidence_breakdown,
          alternative_categories: alternative_categories,
          processing_time_ms: 15.7,
          cache_hits: 3,
          method: "pattern_match",
          error: nil,
          metadata: metadata
        )
      end

      it "assigns all provided values" do
        expect(subject.category).to eq(category)
        expect(subject.confidence).to eq(0.85)
        expect(subject.patterns_used).to eq(patterns_used)
        expect(subject.confidence_breakdown).to eq(confidence_breakdown)
        expect(subject.alternative_categories).to eq(alternative_categories)
        expect(subject.processing_time_ms).to eq(15.7)
        expect(subject.cache_hits).to eq(3)
        expect(subject.method).to eq("pattern_match")
        expect(subject.error).to be_nil
        expect(subject.metadata).to eq(metadata)
      end
    end
  end

  # Factory methods tests - one method at a time
  describe ".no_match" do
    context "with default processing time" do
      subject { described_class.no_match }

      it "creates result with no_match method" do
        expect(subject.method).to eq("no_match")
      end

      it "sets zero processing time by default" do
        expect(subject.processing_time_ms).to eq(0.0)
      end

      it "includes reason in metadata" do
        expect(subject.metadata).to eq({ reason: "No matching patterns found" })
      end

      it "has no category" do
        expect(subject.category).to be_nil
      end

      it "has zero confidence" do
        expect(subject.confidence).to eq(0.0)
      end
    end

    context "with custom processing time" do
      subject { described_class.no_match(processing_time_ms: 5.3) }

      it "sets custom processing time" do
        expect(subject.processing_time_ms).to eq(5.3)
      end
    end
  end

  describe ".from_user_preference" do
    let(:confidence_value) { 1.0 }

    context "with all parameters" do
      subject { described_class.from_user_preference(category, confidence_value, processing_time_ms: 2.5) }

      it "creates result with user_preference method" do
        expect(subject.method).to eq("user_preference")
      end

      it "assigns category correctly" do
        expect(subject.category).to eq(category)
      end

      it "assigns confidence correctly" do
        expect(subject.confidence).to eq(confidence_value)
      end

      it "sets custom processing time" do
        expect(subject.processing_time_ms).to eq(2.5)
      end

      it "has no patterns used" do
        expect(subject.patterns_used).to eq([])
      end

      it "includes source in metadata" do
        expect(subject.metadata).to eq({ source: "user_preference" })
      end
    end

    context "with default processing time" do
      subject { described_class.from_user_preference(category, confidence_value) }

      it "sets zero processing time by default" do
        expect(subject.processing_time_ms).to eq(0.0)
      end
    end
  end

  describe ".from_pattern_match" do
    let(:confidence_score) do
      double("ConfidenceScore",
        score: 0.87,
        factor_breakdown: confidence_breakdown,
        metadata: { engine: "v2", threshold: 0.8 }
      )
    end
    let(:pattern1) { build(:categorization_pattern, pattern_type: "merchant", pattern_value: "Starbucks") }
    let(:pattern2) { build(:categorization_pattern, pattern_type: "keyword", pattern_value: "coffee") }
    let(:patterns) { [ pattern1, pattern2 ] }

    context "with all parameters" do
      subject { described_class.from_pattern_match(category, confidence_score, patterns, processing_time_ms: 12.4) }

      it "creates result with pattern_match method" do
        expect(subject.method).to eq("pattern_match")
      end

      it "assigns category correctly" do
        expect(subject.category).to eq(category)
      end

      it "extracts confidence from score object" do
        expect(subject.confidence).to eq(0.87)
      end

      it "converts patterns to descriptions" do
        expect(subject.patterns_used).to eq([
          "merchant:Starbucks",
          "keyword:coffee"
        ])
      end

      it "extracts confidence breakdown from score object" do
        expect(subject.confidence_breakdown).to eq(confidence_breakdown)
      end

      it "extracts metadata from score object" do
        expect(subject.metadata).to eq({ engine: "v2", threshold: 0.8 })
      end

      it "sets custom processing time" do
        expect(subject.processing_time_ms).to eq(12.4)
      end
    end

    context "with default processing time" do
      subject { described_class.from_pattern_match(category, confidence_score, patterns) }

      it "sets zero processing time by default" do
        expect(subject.processing_time_ms).to eq(0.0)
      end
    end
  end

  describe ".error" do
    let(:error_message) { "Pattern engine timeout" }

    context "with all parameters" do
      subject { described_class.error(error_message, processing_time_ms: 25.1) }

      it "creates result with error method" do
        expect(subject.method).to eq("error")
      end

      it "assigns error message correctly" do
        expect(subject.error).to eq(error_message)
      end

      it "sets custom processing time" do
        expect(subject.processing_time_ms).to eq(25.1)
      end

      it "includes error flag in metadata" do
        expect(subject.metadata).to eq({ error: true })
      end

      it "has no category" do
        expect(subject.category).to be_nil
      end

      it "has zero confidence" do
        expect(subject.confidence).to eq(0.0)
      end
    end

    context "with default processing time" do
      subject { described_class.error(error_message) }

      it "sets zero processing time by default" do
        expect(subject.processing_time_ms).to eq(0.0)
      end
    end
  end

  # Query methods tests - one method at a time
  describe "#successful?" do
    context "when result has category and no error" do
      subject { described_class.new(category: category) }

      it "returns true" do
        expect(subject.successful?).to be(true)
      end
    end

    context "when result has no category" do
      subject { described_class.new(error: nil) }

      it "returns false" do
        expect(subject.successful?).to be(false)
      end
    end

    context "when result has an error" do
      subject { described_class.new(category: category, error: "Something went wrong") }

      it "returns false" do
        expect(subject.successful?).to be(false)
      end
    end

    context "when result has both no category and error" do
      subject { described_class.new(error: "No category found") }

      it "returns false" do
        expect(subject.successful?).to be(false)
      end
    end
  end

  describe "#failed?" do
    context "when result is successful" do
      subject { described_class.new(category: category) }

      it "returns false" do
        expect(subject.failed?).to be(false)
      end
    end

    context "when result is not successful" do
      subject { described_class.new(error: "Processing failed") }

      it "returns true" do
        expect(subject.failed?).to be(true)
      end
    end
  end

  describe "#error?" do
    context "when error is present" do
      subject { described_class.new(error: "Timeout occurred") }

      it "returns true" do
        expect(subject.error?).to be(true)
      end
    end

    context "when error is nil" do
      subject { described_class.new(error: nil) }

      it "returns false" do
        expect(subject.error?).to be(false)
      end
    end

    context "when error is empty string" do
      subject { described_class.new(error: "") }

      it "returns false" do
        expect(subject.error?).to be(false)
      end
    end
  end

  describe "#high_confidence?" do
    context "when confidence is exactly 0.85" do
      subject { described_class.new(confidence: 0.85) }

      it "returns true" do
        expect(subject.high_confidence?).to be(true)
      end
    end

    context "when confidence is above 0.85" do
      subject { described_class.new(confidence: 0.95) }

      it "returns true" do
        expect(subject.high_confidence?).to be(true)
      end
    end

    context "when confidence is below 0.85" do
      subject { described_class.new(confidence: 0.84) }

      it "returns false" do
        expect(subject.high_confidence?).to be(false)
      end
    end

    context "when confidence is 1.0" do
      subject { described_class.new(confidence: 1.0) }

      it "returns true" do
        expect(subject.high_confidence?).to be(true)
      end
    end
  end

  describe "#medium_confidence?" do
    context "when confidence is exactly 0.70" do
      subject { described_class.new(confidence: 0.70) }

      it "returns true" do
        expect(subject.medium_confidence?).to be(true)
      end
    end

    context "when confidence is between 0.70 and 0.85" do
      subject { described_class.new(confidence: 0.78) }

      it "returns true" do
        expect(subject.medium_confidence?).to be(true)
      end
    end

    context "when confidence is exactly 0.84999" do
      subject { described_class.new(confidence: 0.84999) }

      it "returns true" do
        expect(subject.medium_confidence?).to be(true)
      end
    end

    context "when confidence is exactly 0.85" do
      subject { described_class.new(confidence: 0.85) }

      it "returns false (high confidence territory)" do
        expect(subject.medium_confidence?).to be(false)
      end
    end

    context "when confidence is below 0.70" do
      subject { described_class.new(confidence: 0.69) }

      it "returns false" do
        expect(subject.medium_confidence?).to be(false)
      end
    end
  end

  describe "#low_confidence?" do
    context "when confidence is below 0.70" do
      subject { described_class.new(confidence: 0.65) }

      it "returns true" do
        expect(subject.low_confidence?).to be(true)
      end
    end

    context "when confidence is exactly 0.70" do
      subject { described_class.new(confidence: 0.70) }

      it "returns false" do
        expect(subject.low_confidence?).to be(false)
      end
    end

    context "when confidence is above 0.70" do
      subject { described_class.new(confidence: 0.75) }

      it "returns false" do
        expect(subject.low_confidence?).to be(false)
      end
    end

    context "when confidence is 0" do
      subject { described_class.new(confidence: 0.0) }

      it "returns true" do
        expect(subject.low_confidence?).to be(true)
      end
    end
  end

  describe "#confidence_level" do
    context "when confidence is 1.0" do
      subject { described_class.new(confidence: 1.0) }

      it "returns very_high" do
        expect(subject.confidence_level).to eq(:very_high)
      end
    end

    context "when confidence is 0.95" do
      subject { described_class.new(confidence: 0.95) }

      it "returns very_high" do
        expect(subject.confidence_level).to eq(:very_high)
      end
    end

    context "when confidence is 0.94" do
      subject { described_class.new(confidence: 0.94) }

      it "returns high" do
        expect(subject.confidence_level).to eq(:high)
      end
    end

    context "when confidence is 0.85" do
      subject { described_class.new(confidence: 0.85) }

      it "returns high" do
        expect(subject.confidence_level).to eq(:high)
      end
    end

    context "when confidence is 0.84" do
      subject { described_class.new(confidence: 0.84) }

      it "returns medium" do
        expect(subject.confidence_level).to eq(:medium)
      end
    end

    context "when confidence is 0.70" do
      subject { described_class.new(confidence: 0.70) }

      it "returns medium" do
        expect(subject.confidence_level).to eq(:medium)
      end
    end

    context "when confidence is 0.69" do
      subject { described_class.new(confidence: 0.69) }

      it "returns low" do
        expect(subject.confidence_level).to eq(:low)
      end
    end

    context "when confidence is 0.50" do
      subject { described_class.new(confidence: 0.50) }

      it "returns low" do
        expect(subject.confidence_level).to eq(:low)
      end
    end

    context "when confidence is 0.49" do
      subject { described_class.new(confidence: 0.49) }

      it "returns very_low" do
        expect(subject.confidence_level).to eq(:very_low)
      end
    end

    context "when confidence is 0.0" do
      subject { described_class.new(confidence: 0.0) }

      it "returns very_low" do
        expect(subject.confidence_level).to eq(:very_low)
      end
    end
  end

  describe "#user_preference?" do
    context "when method is user_preference" do
      subject { described_class.new(method: "user_preference") }

      it "returns true" do
        expect(subject.user_preference?).to be(true)
      end
    end

    context "when method is pattern_match" do
      subject { described_class.new(method: "pattern_match") }

      it "returns false" do
        expect(subject.user_preference?).to be(false)
      end
    end

    context "when method is nil" do
      subject { described_class.new(method: nil) }

      it "returns false" do
        expect(subject.user_preference?).to be(false)
      end
    end
  end

  describe "#pattern_match?" do
    context "when method is pattern_match" do
      subject { described_class.new(method: "pattern_match") }

      it "returns true" do
        expect(subject.pattern_match?).to be(true)
      end
    end

    context "when method is user_preference" do
      subject { described_class.new(method: "user_preference") }

      it "returns false" do
        expect(subject.pattern_match?).to be(false)
      end
    end

    context "when method is nil" do
      subject { described_class.new(method: nil) }

      it "returns false" do
        expect(subject.pattern_match?).to be(false)
      end
    end
  end

  describe "#no_match?" do
    context "when method is no_match" do
      subject { described_class.new(method: "no_match") }

      it "returns true" do
        expect(subject.no_match?).to be(true)
      end
    end

    context "when method is pattern_match" do
      subject { described_class.new(method: "pattern_match") }

      it "returns false" do
        expect(subject.no_match?).to be(false)
      end
    end

    context "when method is nil" do
      subject { described_class.new(method: nil) }

      it "returns false" do
        expect(subject.no_match?).to be(false)
      end
    end
  end

  describe "#performance_within_target?" do
    context "with default target (10.0ms)" do
      context "when processing time is below target" do
        subject { described_class.new(processing_time_ms: 5.5) }

        it "returns true" do
          expect(subject.performance_within_target?).to be(true)
        end
      end

      context "when processing time equals target" do
        subject { described_class.new(processing_time_ms: 10.0) }

        it "returns true" do
          expect(subject.performance_within_target?).to be(true)
        end
      end

      context "when processing time exceeds target" do
        subject { described_class.new(processing_time_ms: 15.2) }

        it "returns false" do
          expect(subject.performance_within_target?).to be(false)
        end
      end
    end

    context "with custom target" do
      context "when processing time is within custom target" do
        subject { described_class.new(processing_time_ms: 3.8) }

        it "returns true for 5ms target" do
          expect(subject.performance_within_target?(5.0)).to be(true)
        end
      end

      context "when processing time exceeds custom target" do
        subject { described_class.new(processing_time_ms: 8.2) }

        it "returns false for 5ms target" do
          expect(subject.performance_within_target?(5.0)).to be(false)
        end
      end
    end
  end
end
