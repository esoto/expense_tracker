# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantAlias, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_merchant_alias(attributes = {})
    default_attributes = {
      raw_name: "AMAZON.COM",
      normalized_name: "amazon",
      confidence: 0.8,
      match_count: 0,
      last_seen_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:merchant_alias, default_attributes.merge(attributes))
  end

  describe "constants" do
    it "defines confidence constants" do
      expect(MerchantAlias::MIN_CONFIDENCE).to eq(0.0)
      expect(MerchantAlias::MAX_CONFIDENCE).to eq(1.0)
      expect(MerchantAlias::HIGH_CONFIDENCE_THRESHOLD).to eq(0.8)
    end
  end

  describe "associations" do
    it { should belong_to(:canonical_merchant) }
  end

  describe "validations" do
    describe "raw_name" do
      it "requires raw_name to be present" do
        alias_record = build_merchant_alias(raw_name: nil)
        expect(alias_record).not_to be_valid
        expect(alias_record.errors[:raw_name]).to include("can't be blank")
      end

      it "accepts non-empty raw_name" do
        alias_record = build_merchant_alias(raw_name: "UBER *TRIP")
        expect(alias_record).to be_valid
      end
    end

    describe "normalized_name" do
      it "accepts non-empty normalized_name" do
        alias_record = build_merchant_alias(normalized_name: "uber")
        expect(alias_record).to be_valid
      end
    end

    describe "confidence" do
      it "accepts confidence at minimum (0.0)" do
        alias_record = build_merchant_alias(confidence: 0.0)
        expect(alias_record).to be_valid
      end

      it "accepts confidence at maximum (1.0)" do
        alias_record = build_merchant_alias(confidence: 1.0)
        expect(alias_record).to be_valid
      end

      it "accepts confidence in range" do
        alias_record = build_merchant_alias(confidence: 0.75)
        expect(alias_record).to be_valid
      end

      it "rejects confidence below minimum" do
        alias_record = build_merchant_alias(confidence: -0.1)
        expect(alias_record).not_to be_valid
        expect(alias_record.errors[:confidence]).to include("must be greater than or equal to 0.0")
      end

      it "rejects confidence above maximum" do
        alias_record = build_merchant_alias(confidence: 1.1)
        expect(alias_record).not_to be_valid
        expect(alias_record.errors[:confidence]).to include("must be less than or equal to 1.0")
      end
    end

    describe "match_count" do
      it "accepts zero match_count" do
        alias_record = build_merchant_alias(match_count: 0)
        expect(alias_record).to be_valid
      end

      it "accepts positive match_count" do
        alias_record = build_merchant_alias(match_count: 100)
        expect(alias_record).to be_valid
      end

      it "rejects negative match_count" do
        alias_record = build_merchant_alias(match_count: -1)
        expect(alias_record).not_to be_valid
        expect(alias_record.errors[:match_count]).to include("must be greater than or equal to 0")
      end
    end
  end

  describe "scopes" do
    describe ".high_confidence" do
      it "filters aliases with confidence >= 0.8" do
        sql = MerchantAlias.high_confidence.to_sql
        expect(sql).to include("confidence >= 0.8")
      end
    end

    describe ".low_confidence" do
      it "filters aliases with confidence < 0.8" do
        sql = MerchantAlias.low_confidence.to_sql
        expect(sql).to include("confidence < 0.8")
      end
    end

    describe ".recent" do
    end

    describe ".frequently_matched" do
      it "filters aliases with match_count >= 5" do
        sql = MerchantAlias.frequently_matched.to_sql
        expect(sql).to include("match_count >= 5")
      end
    end

    describe ".for_merchant" do
      it "filters by canonical_merchant" do
        merchant = build_stubbed(:canonical_merchant, id: 123)
        result = MerchantAlias.for_merchant(merchant)
        expect(result.where_values_hash["canonical_merchant_id"]).to eq(123)
      end
    end
  end

  describe "callbacks" do
    describe "before_validation" do
      it "sets normalized_name from raw_name when blank" do
        alias_record = MerchantAlias.new(raw_name: "AMAZON *PRIME")
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON *PRIME").and_return("amazon prime")

        alias_record.send(:set_normalized_name)
        expect(alias_record.normalized_name).to eq("amazon prime")
      end

      it "preserves existing normalized_name" do
        alias_record = MerchantAlias.new(raw_name: "AMAZON", normalized_name: "custom_name")

        alias_record.send(:set_normalized_name)
        expect(alias_record.normalized_name).to eq("custom_name")
      end

      it "handles nil raw_name" do
        alias_record = MerchantAlias.new(raw_name: nil)

        alias_record.send(:set_normalized_name)
        expect(alias_record.normalized_name).to be_nil
      end
    end

    describe "after_create" do
      it "updates canonical merchant usage" do
        merchant = build_stubbed(:canonical_merchant)
        alias_record = build_merchant_alias(canonical_merchant: merchant)

        allow(merchant).to receive(:record_usage)
        alias_record.send(:update_canonical_usage)

        expect(merchant).to have_received(:record_usage)
      end

      it "handles nil canonical_merchant" do
        alias_record = build_merchant_alias
        allow(alias_record).to receive(:canonical_merchant).and_return(nil)

        expect { alias_record.send(:update_canonical_usage) }.not_to raise_error
      end
    end
  end

  describe ".find_best_match" do
    it "returns nil for blank input" do
      expect(MerchantAlias.find_best_match(nil)).to be_nil
      expect(MerchantAlias.find_best_match("")).to be_nil
    end

    it "finds exact match by raw_name" do
      exact_match = build_merchant_alias(raw_name: "AMAZON.COM")
      allow(MerchantAlias).to receive(:find_by).with(raw_name: "AMAZON.COM").and_return(exact_match)

      result = MerchantAlias.find_best_match("AMAZON.COM")
      expect(result).to eq(exact_match)
    end

    it "finds normalized match when no exact match" do
      normalized_match = build_merchant_alias(normalized_name: "amazon")
      allow(MerchantAlias).to receive(:find_by).with(raw_name: "AMAZON").and_return(nil)
      allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON").and_return("amazon")
      allow(MerchantAlias).to receive(:find_by).with(normalized_name: "amazon").and_return(normalized_match)

      result = MerchantAlias.find_best_match("AMAZON")
      expect(result).to eq(normalized_match)
    end

    it "attempts fuzzy match when no exact or normalized match" do
      allow(MerchantAlias).to receive(:find_by).and_return(nil)
      allow(CanonicalMerchant).to receive(:normalize_merchant_name).and_return("test")
      allow(MerchantAlias).to receive(:fuzzy_match).with("TEST").and_return("fuzzy_result")

      result = MerchantAlias.find_best_match("TEST")
      expect(result).to eq("fuzzy_result")
    end
  end

  describe ".fuzzy_match" do
    it "returns nil for blank input" do
      expect(MerchantAlias.fuzzy_match(nil)).to be_nil
      expect(MerchantAlias.fuzzy_match("")).to be_nil
    end

    context "with pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(true)
      end

      it "uses trigram similarity for matching" do
        connection = double("connection")
        allow(MerchantAlias).to receive(:connection).and_return(connection)
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("amazn").and_return("amazn")
        allow(MerchantAlias).to receive(:sanitize_sql_array).and_return("SQL")
        allow(connection).to receive(:execute).and_return([
          { "id" => 1, "normalized_name" => "amazon", "confidence" => 0.9, "sim" => 0.8 }
        ])
        allow(MerchantAlias).to receive(:find).with(1).and_return(build_merchant_alias)

        result = MerchantAlias.fuzzy_match("amazn")
        expect(result).not_to be_nil
      end

      it "returns nil when no match found" do
        connection = double("connection")
        allow(MerchantAlias).to receive(:connection).and_return(connection)
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).and_return("xyz")
        allow(MerchantAlias).to receive(:sanitize_sql_array).and_return("SQL")
        allow(connection).to receive(:execute).and_return([])

        expect(MerchantAlias.fuzzy_match("xyz")).to be_nil
      end
    end

    context "without pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(false)
      end

      it "returns nil" do
        expect(MerchantAlias.fuzzy_match("test")).to be_nil
      end
    end
  end

  describe ".record_alias" do
    let(:canonical_merchant) { build_stubbed(:canonical_merchant, id: 1) }

    it "returns nil for blank raw_name" do
      expect(MerchantAlias.record_alias(nil, canonical_merchant)).to be_nil
      expect(MerchantAlias.record_alias("", canonical_merchant)).to be_nil
    end

    it "returns nil for nil canonical_merchant" do
      expect(MerchantAlias.record_alias("AMAZON", nil)).to be_nil
    end

    context "when creating new alias" do
      let(:new_alias) { build_merchant_alias }

      before do
        allow(MerchantAlias).to receive(:find_or_initialize_by).and_return(new_alias)
        allow(new_alias).to receive(:new_record?).and_return(true)
        allow(new_alias).to receive(:save!)
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON").and_return("amazon")
      end

      it "creates new alias with correct attributes" do
        result = MerchantAlias.record_alias("AMAZON", canonical_merchant, confidence: 0.9)

        expect(new_alias.normalized_name).to eq("amazon")
        expect(new_alias.confidence).to eq(0.9)
        expect(new_alias.match_count).to eq(1)
        expect(new_alias.last_seen_at).not_to be_nil
      end
    end

    context "when updating existing alias" do
      let(:existing_alias) { build_merchant_alias(match_count: 5) }

      before do
        allow(MerchantAlias).to receive(:find_or_initialize_by).and_return(existing_alias)
        allow(existing_alias).to receive(:new_record?).and_return(false)
        allow(existing_alias).to receive(:record_match)
      end

      it "records match for existing alias" do
        expect(existing_alias).to receive(:record_match)
        MerchantAlias.record_alias("AMAZON", canonical_merchant)
      end
    end
  end

  describe "#record_match" do
    let(:alias_record) { build_merchant_alias(match_count: 5, confidence: 0.7) }

    before do
      allow(alias_record).to receive(:save!)
    end

    it "increments match_count" do
      alias_record.record_match
      expect(alias_record.match_count).to eq(6)
    end

    it "updates last_seen_at" do
      freeze_time do
        alias_record.record_match
        expect(alias_record.last_seen_at).to eq(Time.current)
      end
    end

    context "confidence adjustment" do
      it "increases confidence after many matches" do
        alias_record.match_count = 11
        alias_record.confidence = 0.8

        alias_record.record_match
        expect(alias_record.confidence).to be_within(0.01).of(0.84)
      end

      it "caps confidence at 0.95" do
        alias_record.match_count = 11
        alias_record.confidence = 0.94

        alias_record.record_match
        expect(alias_record.confidence).to eq(0.95)
      end

      it "doesn't increase confidence with few matches" do
        alias_record.match_count = 5
        alias_record.confidence = 0.7

        alias_record.record_match
        expect(alias_record.confidence).to eq(0.7)
      end

      it "doesn't increase confidence above 0.95" do
        alias_record.match_count = 11
        alias_record.confidence = 0.96

        alias_record.record_match
        expect(alias_record.confidence).to eq(0.96)
      end
    end
  end

  describe "#high_confidence?" do
    it "returns true for confidence >= 0.8" do
      alias_record = build_merchant_alias(confidence: 0.8)
      expect(alias_record.high_confidence?).to be true

      alias_record.confidence = 0.9
      expect(alias_record.high_confidence?).to be true

      alias_record.confidence = 1.0
      expect(alias_record.high_confidence?).to be true
    end

    it "returns false for confidence < 0.8" do
      alias_record = build_merchant_alias(confidence: 0.79)
      expect(alias_record.high_confidence?).to be false

      alias_record.confidence = 0.5
      expect(alias_record.high_confidence?).to be false

      alias_record.confidence = 0.0
      expect(alias_record.high_confidence?).to be false
    end
  end

  describe "#similarity_to" do
    let(:alias_record) { build_merchant_alias(normalized_name: "amazon") }

    it "returns 0.0 for blank input" do
      expect(alias_record.similarity_to(nil)).to eq(0.0)
      expect(alias_record.similarity_to("")).to eq(0.0)
    end

    it "calculates similarity using CanonicalMerchant method" do
      allow(CanonicalMerchant).to receive(:calculate_similarity_confidence).with("amazon", "amazn").and_return(0.85)

      expect(alias_record.similarity_to("amazn")).to eq(0.85)
    end
  end

  describe "#trustworthy?" do
    it "returns true for high confidence with sufficient matches" do
      alias_record = build_merchant_alias(confidence: 0.8, match_count: 3)
      expect(alias_record.trustworthy?).to be true

      alias_record.confidence = 0.9
      alias_record.match_count = 10
      expect(alias_record.trustworthy?).to be true
    end

    it "returns false for low confidence" do
      alias_record = build_merchant_alias(confidence: 0.7, match_count: 10)
      expect(alias_record.trustworthy?).to be false
    end

    it "returns false for insufficient matches" do
      alias_record = build_merchant_alias(confidence: 0.9, match_count: 2)
      expect(alias_record.trustworthy?).to be false
    end

    it "returns false for both low confidence and insufficient matches" do
      alias_record = build_merchant_alias(confidence: 0.5, match_count: 1)
      expect(alias_record.trustworthy?).to be false
    end
  end

  describe "#merge_with" do
    let(:alias1) { build_merchant_alias(id: 1, match_count: 10, confidence: 0.8) }
    let(:alias2) { build_merchant_alias(id: 2, match_count: 5, confidence: 0.9) }
    let(:canonical_merchant) { build_stubbed(:canonical_merchant, id: 1) }

    before do
      allow(alias1).to receive(:canonical_merchant_id).and_return(1)
      allow(alias2).to receive(:canonical_merchant_id).and_return(1)
      allow(alias1).to receive(:transaction).and_yield
      allow(alias1).to receive(:save!)
      allow(alias2).to receive(:destroy!)
    end

    it "does nothing when merging with self" do
      expect(alias1).not_to receive(:transaction)
      alias1.merge_with(alias1)
    end

    it "does nothing when canonical merchants differ" do
      allow(alias2).to receive(:canonical_merchant_id).and_return(2)
      expect(alias1).not_to receive(:transaction)
      alias1.merge_with(alias2)
    end

    context "when merging valid aliases" do
      it "combines match counts" do
        alias1.merge_with(alias2)
        expect(alias1.match_count).to eq(15)
      end

      it "takes higher confidence" do
        alias1.merge_with(alias2)
        expect(alias1.confidence).to eq(0.9)
      end

      it "updates last_seen_at to more recent" do
        alias1.last_seen_at = 2.days.ago
        alias2.last_seen_at = 1.day.ago

        alias1.merge_with(alias2)
        expect(alias1.last_seen_at).to eq(alias2.last_seen_at)
      end

      it "keeps existing last_seen_at when other is nil" do
        original_last_seen_at = 1.day.ago
        alias1.last_seen_at = original_last_seen_at
        alias2.last_seen_at = nil

        alias1.merge_with(alias2)
        expect(alias1.last_seen_at).to eq(original_last_seen_at)
      end

      it "destroys the other alias" do
        expect(alias2).to receive(:destroy!)
        alias1.merge_with(alias2)
      end
    end
  end

  describe "edge cases and business logic" do
    describe "confidence boundaries" do
      it "handles edge case confidence values" do
        expect(build_merchant_alias(confidence: 0.0)).to be_valid
        expect(build_merchant_alias(confidence: 1.0)).to be_valid
        expect(build_merchant_alias(confidence: 0.5)).to be_valid
      end
    end

    describe "match count progression" do
      it "handles large match counts" do
        alias_record = build_merchant_alias(match_count: 1_000_000)
        expect(alias_record).to be_valid
      end
    end

    describe "normalization consistency" do
      it "maintains consistency between raw and normalized names" do
        alias_record = MerchantAlias.new(raw_name: "PAYPAL *AMAZON")
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("PAYPAL *AMAZON").and_return("amazon")

        alias_record.send(:set_normalized_name)
        expect(alias_record.normalized_name).to eq("amazon")
      end
    end

    describe "trust evaluation" do
      it "requires both high confidence AND sufficient matches for trust" do
        # High confidence but low matches - not trustworthy
        alias1 = build_merchant_alias(confidence: 0.95, match_count: 1)
        expect(alias1.trustworthy?).to be false

        # Many matches but low confidence - not trustworthy
        alias2 = build_merchant_alias(confidence: 0.6, match_count: 100)
        expect(alias2.trustworthy?).to be false

        # Both criteria met - trustworthy
        alias3 = build_merchant_alias(confidence: 0.85, match_count: 5)
        expect(alias3.trustworthy?).to be true
      end
    end
  end
end
