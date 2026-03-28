# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::LearningResult, type: :service do
  describe ".success" do
    it "creates a successful result with defaults", unit: true do
      result = described_class.success

      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.patterns_created).to eq(0)
      expect(result.patterns_updated).to eq(0)
      expect(result.message).to eq("Learning completed successfully")
      expect(result.metadata).to eq({})
      expect(result.processing_time_ms).to eq(0.0)
    end

    it "creates a successful result with patterns_created", unit: true do
      result = described_class.success(patterns_created: 3)

      expect(result.success?).to be true
      expect(result.patterns_created).to eq(3)
      expect(result.patterns_updated).to eq(0)
    end

    it "creates a successful result with patterns_updated", unit: true do
      result = described_class.success(patterns_updated: 5)

      expect(result.patterns_created).to eq(0)
      expect(result.patterns_updated).to eq(5)
    end

    it "accepts a custom message", unit: true do
      result = described_class.success(message: "Custom message")

      expect(result.message).to eq("Custom message")
    end

    it "accepts metadata", unit: true do
      result = described_class.success(metadata: { source: "test" })

      expect(result.metadata).to eq({ source: "test" })
    end

    it "uses default message when message is nil", unit: true do
      result = described_class.success(message: nil)

      expect(result.message).to eq("Learning completed successfully")
    end
  end

  describe ".error" do
    it "creates a failed result with the given message", unit: true do
      result = described_class.error("Something went wrong")

      expect(result.success?).to be false
      expect(result.failure?).to be true
      expect(result.message).to eq("Something went wrong")
    end

    it "merges error: true into metadata", unit: true do
      result = described_class.error("Failure", metadata: { context: "test" })

      expect(result.metadata).to include(error: true, context: "test")
    end

    it "sets patterns_created and patterns_updated to 0", unit: true do
      result = described_class.error("Failure")

      expect(result.patterns_created).to eq(0)
      expect(result.patterns_updated).to eq(0)
    end
  end

  describe "#initialize" do
    it "sets all attributes", unit: true do
      result = described_class.new(
        success: true,
        patterns_created: 2,
        patterns_updated: 1,
        message: "Done",
        metadata: { key: "val" },
        processing_time_ms: 12.5
      )

      expect(result.success).to be true
      expect(result.patterns_created).to eq(2)
      expect(result.patterns_updated).to eq(1)
      expect(result.message).to eq("Done")
      expect(result.metadata).to eq({ key: "val" })
      expect(result.processing_time_ms).to eq(12.5)
    end

    it "defaults processing_time_ms to 0.0", unit: true do
      result = described_class.new(success: true)

      expect(result.processing_time_ms).to eq(0.0)
    end

    it "defaults metadata to empty hash", unit: true do
      result = described_class.new(success: true)

      expect(result.metadata).to eq({})
    end
  end

  describe "#success?" do
    it "returns true when success", unit: true do
      expect(described_class.new(success: true).success?).to be true
    end

    it "returns false when failure", unit: true do
      expect(described_class.new(success: false).success?).to be false
    end
  end

  describe "#failure?" do
    it "returns true when not successful", unit: true do
      expect(described_class.new(success: false).failure?).to be true
    end

    it "returns false when successful", unit: true do
      expect(described_class.new(success: true).failure?).to be false
    end
  end

  describe "#error" do
    it "returns nil when successful", unit: true do
      result = described_class.success(message: "ok")

      expect(result.error).to be_nil
    end

    it "returns the message when failed", unit: true do
      result = described_class.error("Something broke")

      expect(result.error).to eq("Something broke")
    end
  end

  describe "#patterns_affected" do
    it "returns sum of patterns_created and patterns_updated", unit: true do
      result = described_class.success(patterns_created: 3, patterns_updated: 2)

      expect(result.patterns_affected).to eq(5)
    end

    it "returns 0 when no patterns were affected", unit: true do
      result = described_class.success

      expect(result.patterns_affected).to eq(0)
    end
  end

  describe "#any_patterns_created?" do
    it "returns true when patterns_created > 0", unit: true do
      result = described_class.success(patterns_created: 1)

      expect(result.any_patterns_created?).to be true
    end

    it "returns false when patterns_created is 0", unit: true do
      result = described_class.success(patterns_created: 0)

      expect(result.any_patterns_created?).to be false
    end
  end

  describe "#any_patterns_updated?" do
    it "returns true when patterns_updated > 0", unit: true do
      result = described_class.success(patterns_updated: 1)

      expect(result.any_patterns_updated?).to be true
    end

    it "returns false when patterns_updated is 0", unit: true do
      result = described_class.success(patterns_updated: 0)

      expect(result.any_patterns_updated?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash with all expected keys", unit: true do
      result = described_class.success(
        patterns_created: 2,
        patterns_updated: 1,
        message: "Done",
        metadata: { source: "test" }
      )

      hash = result.to_h

      expect(hash).to include(
        success: true,
        patterns_created: 2,
        patterns_updated: 1,
        patterns_affected: 3,
        message: "Done",
        metadata: { source: "test" }
      )
      expect(hash).to have_key(:processing_time_ms)
      expect(hash).to have_key(:created_at)
    end

    it "rounds processing_time_ms to 3 decimal places", unit: true do
      result = described_class.new(success: true, processing_time_ms: 12.12345)

      expect(result.to_h[:processing_time_ms]).to eq(12.123)
    end
  end

  describe "#to_json" do
    it "returns a JSON string", unit: true do
      result = described_class.success(message: "Done")

      json = result.to_json
      parsed = JSON.parse(json)

      expect(parsed["success"]).to be true
      expect(parsed["message"]).to eq("Done")
    end
  end

  describe "#to_s" do
    it "returns a success string when successful", unit: true do
      result = described_class.success(patterns_created: 2, patterns_updated: 1)

      expect(result.to_s).to include("Learning successful")
      expect(result.to_s).to include("3 patterns affected")
    end

    it "returns a failure string when failed", unit: true do
      result = described_class.error("Pattern mismatch")

      expect(result.to_s).to include("Learning failed")
      expect(result.to_s).to include("Pattern mismatch")
    end
  end

  describe "#inspect" do
    it "returns an inspect string with key attributes", unit: true do
      result = described_class.success(patterns_created: 1, patterns_updated: 2)

      inspect_str = result.inspect

      expect(inspect_str).to include("LearningResult")
      expect(inspect_str).to include("success=true")
      expect(inspect_str).to include("created=1")
      expect(inspect_str).to include("updated=2")
    end
  end
end
