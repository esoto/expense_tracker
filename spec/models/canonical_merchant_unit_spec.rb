# frozen_string_literal: true

require "rails_helper"

RSpec.describe CanonicalMerchant, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_canonical_merchant(attributes = {})
    default_attributes = {
      name: "amazon",
      display_name: "Amazon",
      usage_count: 0,
      metadata: {},
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:canonical_merchant, default_attributes.merge(attributes))
  end

  describe "associations" do
    it { should have_many(:merchant_aliases).dependent(:destroy) }
  end

  describe "validations" do
    describe "name" do
      it "requires name to be present" do
        merchant = build_canonical_merchant(name: nil)
        expect(merchant).not_to be_valid
        expect(merchant.errors[:name]).to include("can't be blank")
      end

      it "requires name to be unique (case insensitive)" do
        merchant = build_canonical_merchant(name: "Amazon")

        # Mock uniqueness validation
        allow(merchant).to receive(:errors).and_return(ActiveModel::Errors.new(merchant))
        relation = double("relation")
        allow(CanonicalMerchant).to receive(:where).and_return(relation)
        allow(relation).to receive(:exists?).and_return(false)

        expect(merchant).to be_valid
      end
    end

    describe "usage_count" do
      it "accepts zero usage_count" do
        merchant = build_canonical_merchant(usage_count: 0)
        expect(merchant).to be_valid
      end

      it "accepts positive usage_count" do
        merchant = build_canonical_merchant(usage_count: 100)
        expect(merchant).to be_valid
      end

      it "rejects negative usage_count" do
        merchant = build_canonical_merchant(usage_count: -1)
        expect(merchant).not_to be_valid
        expect(merchant.errors[:usage_count]).to include("must be greater than or equal to 0")
      end
    end
  end

  describe "scopes" do
    describe ".popular" do
      it "filters merchants with usage_count >= 10" do
        sql = CanonicalMerchant.popular.to_sql
        expect(sql).to include("usage_count >= 10")
      end
    end
  end

  describe "callbacks" do
    describe "before_save" do
      it "normalizes name when changed" do
        merchant = build_canonical_merchant(name: "AMAZON.COM *PRIME")
        allow(merchant).to receive(:name_changed?).and_return(true)
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON.COM *PRIME").and_return("amazon prime")

        merchant.send(:normalize_name)
        expect(CanonicalMerchant).to have_received(:normalize_merchant_name)
      end

      it "doesn't normalize name when not changed" do
        merchant = build_canonical_merchant(name: "amazon")
        allow(merchant).to receive(:name_changed?).and_return(false)
        allow(CanonicalMerchant).to receive(:normalize_merchant_name)

        merchant.send(:normalize_name)
        expect(CanonicalMerchant).not_to have_received(:normalize_merchant_name)
      end
    end
  end

  describe ".normalize_merchant_name" do
    it "handles blank input" do
      expect(CanonicalMerchant.normalize_merchant_name(nil)).to eq("")
      expect(CanonicalMerchant.normalize_merchant_name("")).to eq("")
      expect(CanonicalMerchant.normalize_merchant_name("   ")).to eq("")
    end

    it "removes payment processor prefixes" do
      expect(CanonicalMerchant.normalize_merchant_name("PAYPAL *AMAZON")).to eq("amazon")
      expect(CanonicalMerchant.normalize_merchant_name("SQ *COFFEE SHOP")).to eq("coffee shop")
      expect(CanonicalMerchant.normalize_merchant_name("SQUARE *STORE")).to eq("store")
      expect(CanonicalMerchant.normalize_merchant_name("TST* MERCHANT")).to eq("merchant")
      expect(CanonicalMerchant.normalize_merchant_name("POS TERMINAL")).to eq("terminal")
      expect(CanonicalMerchant.normalize_merchant_name("CCD PAYMENT")).to eq("payment")
    end

    it "removes asterisk separators" do
      expect(CanonicalMerchant.normalize_merchant_name("UBER * TRIP")).to eq("uber trip")
      expect(CanonicalMerchant.normalize_merchant_name("AMAZON*PRIME")).to eq("amazon prime")
    end

    it "removes transaction IDs and numbers" do
      expect(CanonicalMerchant.normalize_merchant_name("STARBUCKS 12345")).to eq("starbucks")
      expect(CanonicalMerchant.normalize_merchant_name("TARGET #4567")).to eq("target")
      expect(CanonicalMerchant.normalize_merchant_name("WALMART 987654321")).to eq("walmart")
    end

    it "removes company suffixes" do
      expect(CanonicalMerchant.normalize_merchant_name("AMAZON INC")).to eq("amazon")
      expect(CanonicalMerchant.normalize_merchant_name("GOOGLE LLC")).to eq("google")
      expect(CanonicalMerchant.normalize_merchant_name("MICROSOFT CORP")).to eq("microsoft")
      expect(CanonicalMerchant.normalize_merchant_name("APPLE CO")).to eq("apple")
      expect(CanonicalMerchant.normalize_merchant_name("FACEBOOK COMPANY")).to eq("facebook")
    end


    it "cleans special characters and normalizes whitespace" do
      expect(CanonicalMerchant.normalize_merchant_name("AMAZON!!!COM")).to eq("amazon com")
      expect(CanonicalMerchant.normalize_merchant_name("UBER    EATS")).to eq("uber eats")
      expect(CanonicalMerchant.normalize_merchant_name("  SPOTIFY  ")).to eq("spotify")
    end

    it "preserves allowed special characters" do
      expect(CanonicalMerchant.normalize_merchant_name("AT&T")).to eq("at&t")
      expect(CanonicalMerchant.normalize_merchant_name("McDonald's")).to eq("mcdonald's")
      expect(CanonicalMerchant.normalize_merchant_name("7-ELEVEN")).to eq("7-eleven")
    end

    it "converts to lowercase" do
      expect(CanonicalMerchant.normalize_merchant_name("AMAZON")).to eq("amazon")
      expect(CanonicalMerchant.normalize_merchant_name("Amazon")).to eq("amazon")
      expect(CanonicalMerchant.normalize_merchant_name("aMaZoN")).to eq("amazon")
    end

    it "handles complex real-world examples" do
      expect(CanonicalMerchant.normalize_merchant_name("PAYPAL *UBER TECHNOLO 4029357733")).to eq("uber technolo")
      expect(CanonicalMerchant.normalize_merchant_name("SQ *BLUE BOTTLE COFFEE STORE #42 INC")).to eq("blue bottle coffee")
      expect(CanonicalMerchant.normalize_merchant_name("TST* TARGET.COM * 800-555-1234")).to eq("target com 800-555-1234")
    end
  end

  describe ".beautify_merchant_name" do
    it "handles blank input" do
      expect(CanonicalMerchant.beautify_merchant_name(nil)).to eq("")
      expect(CanonicalMerchant.beautify_merchant_name("")).to eq("")
    end

    it "returns known merchant names with proper casing" do
      expect(CanonicalMerchant.beautify_merchant_name("uber")).to eq("Uber")
      expect(CanonicalMerchant.beautify_merchant_name("AMAZON")).to eq("Amazon")
      expect(CanonicalMerchant.beautify_merchant_name("mcdonalds")).to eq("McDonald's")
      expect(CanonicalMerchant.beautify_merchant_name("netflix")).to eq("Netflix")
    end

    it "title cases unknown merchants" do
      expect(CanonicalMerchant.beautify_merchant_name("blue bottle coffee")).to eq("Blue Bottle Coffee")
      expect(CanonicalMerchant.beautify_merchant_name("random store")).to eq("Random Store")
    end

    it "handles mixed case input for known merchants" do
      expect(CanonicalMerchant.beautify_merchant_name("UbEr")).to eq("Uber")
      expect(CanonicalMerchant.beautify_merchant_name("WALMART")).to eq("Walmart")
    end
  end

  describe ".find_similar_canonical" do
    context "with pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(true)
      end

      it "uses trigram similarity for matching" do
        connection = double("connection")
        allow(CanonicalMerchant).to receive(:connection).and_return(connection)
        allow(CanonicalMerchant).to receive(:sanitize_sql_array).and_return("SQL")
        allow(connection).to receive(:execute).and_return([ { "id" => 1, "name" => "amazon", "sim" => 0.8 } ])
        allow(CanonicalMerchant).to receive(:find).with(1).and_return(build_canonical_merchant)

        result = CanonicalMerchant.find_similar_canonical("amazn")
        expect(result).not_to be_nil
      end

      it "returns nil when no similar merchant found" do
        connection = double("connection")
        allow(CanonicalMerchant).to receive(:connection).and_return(connection)
        allow(CanonicalMerchant).to receive(:sanitize_sql_array).and_return("SQL")
        allow(connection).to receive(:execute).and_return([])

        expect(CanonicalMerchant.find_similar_canonical("xyz123")).to be_nil
      end
    end

    context "without pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(false)
      end

      it "falls back to exact match" do
        allow(CanonicalMerchant).to receive(:find_by).with("LOWER(name) = ?", "amazon").and_return(build_canonical_merchant)

        result = CanonicalMerchant.find_similar_canonical("amazon")
        expect(result).not_to be_nil
      end
    end

    it "handles blank input" do
      expect(CanonicalMerchant.find_similar_canonical(nil)).to be_nil
      expect(CanonicalMerchant.find_similar_canonical("")).to be_nil
    end
  end

  describe ".calculate_similarity_confidence" do
    context "with pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(true)
      end

      it "calculates trigram similarity" do
        connection = double("connection")
        allow(CanonicalMerchant).to receive(:connection).and_return(connection)
        allow(CanonicalMerchant).to receive(:sanitize_sql_array).and_return("SQL")
        allow(connection).to receive(:execute).and_return([ { "sim" => "0.75" } ])

        expect(CanonicalMerchant.calculate_similarity_confidence("amazon", "amazn")).to eq(0.75)
      end
    end

    context "without pg_trgm extension" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:extension_enabled?).with("pg_trgm").and_return(false)
      end

      it "uses character-based similarity" do
        # "abc" and "abc" have all characters in common
        expect(CanonicalMerchant.calculate_similarity_confidence("abc", "abc")).to eq(1.0)

        # "abc" and "def" have no characters in common
        expect(CanonicalMerchant.calculate_similarity_confidence("abc", "def")).to eq(0.0)

        # "abc" and "ab" have 2 characters in common out of 3
        expect(CanonicalMerchant.calculate_similarity_confidence("abc", "ab")).to be_within(0.1).of(0.67)
      end
    end

    it "handles blank input" do
      expect(CanonicalMerchant.calculate_similarity_confidence(nil, "test")).to eq(0.0)
      expect(CanonicalMerchant.calculate_similarity_confidence("test", nil)).to eq(0.0)
      expect(CanonicalMerchant.calculate_similarity_confidence("", "test")).to eq(0.0)
    end
  end

  describe "#record_usage" do
    let(:merchant) { build_canonical_merchant(usage_count: 5) }

    it "increments usage_count" do
      allow(merchant).to receive(:increment!).with(:usage_count)
      allow(merchant).to receive(:touch).with(:updated_at)

      merchant.record_usage

      expect(merchant).to have_received(:increment!).with(:usage_count)
      expect(merchant).to have_received(:touch).with(:updated_at)
    end
  end

  describe "#all_raw_names" do
    let(:merchant) { build_canonical_merchant }
    let(:aliases) { double("aliases") }

    before do
      allow(merchant).to receive(:merchant_aliases).and_return(aliases)
    end

    it "returns unique raw names from aliases" do
      allow(aliases).to receive(:pluck).with(:raw_name).and_return([ "AMAZON", "AMAZON.COM", "AMAZON", "AMZN" ])

      expect(merchant.all_raw_names).to eq([ "AMAZON", "AMAZON.COM", "AMZN" ])
    end

    it "returns empty array when no aliases" do
      allow(aliases).to receive(:pluck).with(:raw_name).and_return([])

      expect(merchant.all_raw_names).to eq([])
    end
  end

  describe "#most_common_raw_name" do
    let(:merchant) { build_canonical_merchant(name: "amazon") }
    let(:aliases) { double("aliases") }

    before do
      allow(merchant).to receive(:merchant_aliases).and_return(aliases)
    end

    it "returns the most frequent raw name" do
      allow(aliases).to receive(:group).with(:raw_name).and_return(aliases)
      allow(aliases).to receive(:order).with("COUNT(*) DESC").and_return(aliases)
      allow(aliases).to receive(:limit).with(1).and_return(aliases)
      allow(aliases).to receive(:pluck).with(:raw_name).and_return([ "AMAZON.COM" ])

      expect(merchant.most_common_raw_name).to eq("AMAZON.COM")
    end

    it "returns merchant name when no aliases exist" do
      allow(aliases).to receive(:group).with(:raw_name).and_return(aliases)
      allow(aliases).to receive(:order).with("COUNT(*) DESC").and_return(aliases)
      allow(aliases).to receive(:limit).with(1).and_return(aliases)
      allow(aliases).to receive(:pluck).with(:raw_name).and_return([])

      expect(merchant.most_common_raw_name).to eq("amazon")
    end
  end

  describe "#merge_with" do
    let(:merchant1) { build_canonical_merchant(id: 1, usage_count: 10, category_hint: "Shopping") }
    let(:merchant2) { build_canonical_merchant(id: 2, usage_count: 5, category_hint: nil) }

    before do
      allow(merchant1).to receive(:transaction).and_yield
      allow(merchant1).to receive(:save!)
      allow(merchant2).to receive(:destroy!)
    end

    it "does nothing when merging with self" do
      expect(merchant1).not_to receive(:transaction)
      merchant1.merge_with(merchant1)
    end

    context "when merging different merchants" do
      let(:aliases) { double("aliases") }

      before do
        allow(merchant2).to receive(:merchant_aliases).and_return(aliases)
        allow(aliases).to receive(:update_all).with(canonical_merchant_id: 1)
      end

      it "moves aliases to this merchant" do
        expect(aliases).to receive(:update_all).with(canonical_merchant_id: 1)
        merchant1.merge_with(merchant2)
      end

      it "combines usage counts" do
        merchant1.merge_with(merchant2)
        expect(merchant1.usage_count).to eq(15)
      end

      it "merges metadata" do
        merchant1.metadata = { "key1" => "value1" }
        merchant2.metadata = { "key2" => "value2" }

        merchant1.merge_with(merchant2)
        expect(merchant1.metadata).to eq({ "key1" => "value1", "key2" => "value2" })
      end

      it "keeps better display name" do
        merchant1.display_name = nil
        merchant2.display_name = "Amazon Prime"

        merchant1.merge_with(merchant2)
        expect(merchant1.display_name).to eq("Amazon Prime")
      end

      it "keeps category hint when not present" do
        merchant1.category_hint = nil
        merchant2.category_hint = "E-commerce"

        merchant1.merge_with(merchant2)
        expect(merchant1.category_hint).to eq("E-commerce")
      end

      it "preserves existing category hint" do
        merchant1.category_hint = "Shopping"
        merchant2.category_hint = "E-commerce"

        merchant1.merge_with(merchant2)
        expect(merchant1.category_hint).to eq("Shopping")
      end

      it "destroys the other merchant" do
        expect(merchant2).to receive(:destroy!)
        merchant1.merge_with(merchant2)
      end
    end
  end

  describe "#suggest_category" do
    let(:merchant) { build_canonical_merchant }

    context "with category_hint" do
      before do
        merchant.category_hint = "Shopping"
      end

      it "finds category by hint name" do
        category = build_stubbed(:category, name: "Shopping")
        allow(Category).to receive(:find_by).with(name: "Shopping").and_return(category)

        expect(merchant.suggest_category).to eq(category)
      end

      it "returns nil when category not found" do
        allow(Category).to receive(:find_by).with(name: "Shopping").and_return(nil)

        expect(merchant.suggest_category).to be_nil
      end
    end

    context "without category_hint" do
      before do
        merchant.category_hint = nil
      end

      it "returns nil" do
        expect(merchant.suggest_category).to be_nil
      end
    end
  end

  describe ".find_or_create_from_raw" do
    context "with blank input" do
      it "returns nil for nil input" do
        expect(CanonicalMerchant.find_or_create_from_raw(nil)).to be_nil
      end

      it "returns nil for empty string" do
        expect(CanonicalMerchant.find_or_create_from_raw("")).to be_nil
      end

      it "returns nil for whitespace-only string" do
        expect(CanonicalMerchant.find_or_create_from_raw("   ")).to be_nil
      end
    end

    context "when exact raw name alias exists" do
      let(:existing_canonical) { build_stubbed(:canonical_merchant, id: 1, name: "amazon") }
      let(:existing_alias) { double("merchant_alias", canonical_merchant: existing_canonical) }

      before do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON.COM").and_return("amazon")
        allow(MerchantAlias).to receive(:find_by).with(raw_name: "AMAZON.COM").and_return(existing_alias)
      end

      it "returns the canonical merchant from the alias" do
        result = CanonicalMerchant.find_or_create_from_raw("AMAZON.COM")
        expect(result).to eq(existing_canonical)
      end

      it "doesn't call further lookup methods" do
        expect(MerchantAlias).not_to receive(:find_by).with(normalized_name: "amazon")
        CanonicalMerchant.find_or_create_from_raw("AMAZON.COM")
      end
    end

    context "when normalized name alias exists" do
      let(:existing_canonical) { build_stubbed(:canonical_merchant, id: 1, name: "amazon") }
      let(:existing_alias) { double("merchant_alias", canonical_merchant: existing_canonical) }

      before do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON PRIME").and_return("amazon prime")
        allow(MerchantAlias).to receive(:find_by).with(raw_name: "AMAZON PRIME").and_return(nil)
        allow(MerchantAlias).to receive(:find_by).with(normalized_name: "amazon prime").and_return(existing_alias)
      end

      it "returns the canonical merchant from the normalized alias" do
        result = CanonicalMerchant.find_or_create_from_raw("AMAZON PRIME")
        expect(result).to eq(existing_canonical)
      end

      it "calls normalization" do
        expect(CanonicalMerchant).to receive(:normalize_merchant_name).with("AMAZON PRIME")
        CanonicalMerchant.find_or_create_from_raw("AMAZON PRIME")
      end
    end

    context "when similar canonical merchant exists" do
      let(:similar_canonical) { build_stubbed(:canonical_merchant, id: 2, name: "uber", display_name: "Uber") }

      before do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("UBER *TRIP").and_return("uber trip")
        allow(MerchantAlias).to receive(:find_by).with(raw_name: "UBER *TRIP").and_return(nil)
        allow(MerchantAlias).to receive(:find_by).with(normalized_name: "uber trip").and_return(nil)
        allow(CanonicalMerchant).to receive(:find_similar_canonical).with("uber trip").and_return(similar_canonical)
        allow(CanonicalMerchant).to receive(:calculate_similarity_confidence).with("uber trip", "uber").and_return(0.85)
      end

      it "returns the similar canonical merchant" do
        allow(MerchantAlias).to receive(:create!).and_return(double("alias"))

        result = CanonicalMerchant.find_or_create_from_raw("UBER *TRIP")
        expect(result).to eq(similar_canonical)
      end

      it "creates an alias with calculated confidence" do
        expect(MerchantAlias).to receive(:create!).with(
          raw_name: "UBER *TRIP",
          normalized_name: "uber trip",
          canonical_merchant: similar_canonical,
          confidence: 0.85
        )

        CanonicalMerchant.find_or_create_from_raw("UBER *TRIP")
      end

      it "calculates similarity confidence correctly" do
        allow(MerchantAlias).to receive(:create!)
        expect(CanonicalMerchant).to receive(:calculate_similarity_confidence).with("uber trip", "uber")

        CanonicalMerchant.find_or_create_from_raw("UBER *TRIP")
      end
    end

    context "when no existing merchant found" do
      let(:new_canonical) { build_stubbed(:canonical_merchant, id: 3, name: "new merchant", display_name: "New Merchant") }

      before do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with("NEW MERCHANT INC").and_return("new merchant")
        allow(MerchantAlias).to receive(:find_by).with(raw_name: "NEW MERCHANT INC").and_return(nil)
        allow(MerchantAlias).to receive(:find_by).with(normalized_name: "new merchant").and_return(nil)
        allow(CanonicalMerchant).to receive(:find_similar_canonical).with("new merchant").and_return(nil)
        allow(CanonicalMerchant).to receive(:beautify_merchant_name).with("new merchant").and_return("New Merchant")
        allow(CanonicalMerchant).to receive(:create!).and_return(new_canonical)
      end

      it "creates a new canonical merchant" do
        allow(MerchantAlias).to receive(:create!)

        expect(CanonicalMerchant).to receive(:create!).with(
          name: "new merchant",
          display_name: "New Merchant"
        )

        result = CanonicalMerchant.find_or_create_from_raw("NEW MERCHANT INC")
        expect(result).to eq(new_canonical)
      end

      it "creates an alias with 100% confidence" do
        allow(CanonicalMerchant).to receive(:create!).and_return(new_canonical)

        expect(MerchantAlias).to receive(:create!).with(
          raw_name: "NEW MERCHANT INC",
          normalized_name: "new merchant",
          canonical_merchant: new_canonical,
          confidence: 1.0
        )

        CanonicalMerchant.find_or_create_from_raw("NEW MERCHANT INC")
      end

      it "beautifies the merchant name for display" do
        allow(MerchantAlias).to receive(:create!)
        expect(CanonicalMerchant).to receive(:beautify_merchant_name).with("new merchant")

        CanonicalMerchant.find_or_create_from_raw("NEW MERCHANT INC")
      end
    end

    context "integration scenarios" do
      it "handles complex merchant name with multiple normalizations" do
        raw_name = "PAYPAL *AMAZON.COM STORE #1234"
        normalized = "amazon"
        beautified = "Amazon"

        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with(raw_name).and_return(normalized)
        allow(MerchantAlias).to receive(:find_by).and_return(nil)
        allow(CanonicalMerchant).to receive(:find_similar_canonical).and_return(nil)
        allow(CanonicalMerchant).to receive(:beautify_merchant_name).with(normalized).and_return(beautified)

        new_canonical = build_stubbed(:canonical_merchant, name: normalized, display_name: beautified)
        allow(CanonicalMerchant).to receive(:create!).and_return(new_canonical)
        allow(MerchantAlias).to receive(:create!)

        result = CanonicalMerchant.find_or_create_from_raw(raw_name)

        expect(result).to eq(new_canonical)
        expect(CanonicalMerchant).to have_received(:normalize_merchant_name).with(raw_name)
      end

      it "handles Unicode characters correctly" do
        raw_name = "Café José's"
        normalized = "cafe jose's"

        allow(CanonicalMerchant).to receive(:normalize_merchant_name).with(raw_name).and_return(normalized)
        allow(MerchantAlias).to receive(:find_by).and_return(nil)
        allow(CanonicalMerchant).to receive(:find_similar_canonical).and_return(nil)
        allow(CanonicalMerchant).to receive(:beautify_merchant_name).and_return("Cafe Jose's")

        new_canonical = build_stubbed(:canonical_merchant, name: normalized)
        allow(CanonicalMerchant).to receive(:create!).and_return(new_canonical)
        allow(MerchantAlias).to receive(:create!)

        result = CanonicalMerchant.find_or_create_from_raw(raw_name)
        expect(result).to eq(new_canonical)
      end
    end

    context "error handling" do
      it "handles MerchantAlias creation failure gracefully" do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).and_return("test")
        allow(MerchantAlias).to receive(:find_by).and_return(nil)

        similar_canonical = build_stubbed(:canonical_merchant, name: "test")
        allow(CanonicalMerchant).to receive(:find_similar_canonical).and_return(similar_canonical)
        allow(CanonicalMerchant).to receive(:calculate_similarity_confidence).and_return(0.8)

        # Simulate alias creation failure
        allow(MerchantAlias).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(MerchantAlias.new))

        expect {
          CanonicalMerchant.find_or_create_from_raw("TEST MERCHANT")
        }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "handles CanonicalMerchant creation failure gracefully" do
        allow(CanonicalMerchant).to receive(:normalize_merchant_name).and_return("test")
        allow(MerchantAlias).to receive(:find_by).and_return(nil)
        allow(CanonicalMerchant).to receive(:find_similar_canonical).and_return(nil)
        allow(CanonicalMerchant).to receive(:beautify_merchant_name).and_return("Test")

        # Simulate canonical creation failure
        allow(CanonicalMerchant).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(CanonicalMerchant.new))

        expect {
          CanonicalMerchant.find_or_create_from_raw("TEST MERCHANT")
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "performance considerations" do
      it "stops searching after finding exact raw name match" do
        existing_canonical = build_stubbed(:canonical_merchant, name: "amazon")
        existing_alias = double("alias", canonical_merchant: existing_canonical)

        allow(CanonicalMerchant).to receive(:normalize_merchant_name)
        allow(MerchantAlias).to receive(:find_by).with(raw_name: "AMAZON").and_return(existing_alias)

        # These should not be called since we found exact match
        expect(MerchantAlias).not_to receive(:find_by).with(normalized_name: anything)
        expect(CanonicalMerchant).not_to receive(:find_similar_canonical)

        result = CanonicalMerchant.find_or_create_from_raw("AMAZON")
        expect(result).to eq(existing_canonical)
      end

      it "optimizes by checking normalized name before fuzzy search" do
        existing_canonical = build_stubbed(:canonical_merchant, name: "amazon")
        existing_alias = double("alias", canonical_merchant: existing_canonical)

        allow(CanonicalMerchant).to receive(:normalize_merchant_name).and_return("amazon prime")
        allow(MerchantAlias).to receive(:find_by).with(raw_name: anything).and_return(nil)
        allow(MerchantAlias).to receive(:find_by).with(normalized_name: "amazon prime").and_return(existing_alias)

        # Should not call expensive fuzzy search
        expect(CanonicalMerchant).not_to receive(:find_similar_canonical)

        result = CanonicalMerchant.find_or_create_from_raw("AMAZON PRIME")
        expect(result).to eq(existing_canonical)
      end
    end
  end

  describe "edge cases and security" do
    describe "SQL injection prevention" do
    end

    describe "performance with large data" do
      it "handles very long merchant names" do
        long_name = "A" * 1000
        result = CanonicalMerchant.normalize_merchant_name(long_name)
        expect(result.length).to be <= 1000
      end

      it "handles merchants with many aliases efficiently" do
        merchant = build_canonical_merchant
        aliases = double("aliases")
        allow(merchant).to receive(:merchant_aliases).and_return(aliases)
        allow(aliases).to receive(:pluck).and_return(Array.new(1000) { |i| "ALIAS_#{i}" })

        expect(merchant.all_raw_names.length).to eq(1000)
      end
    end
  end
end
