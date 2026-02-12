# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Matchers::TextExtractor, :unit do
  subject(:extractor) { described_class.new }

  describe "#extract_from" do
    context "with String input" do
      it "returns the string directly" do
        expect(extractor.extract_from("test string")).to eq("test string")
      end

      it "returns empty string when given empty string" do
        expect(extractor.extract_from("")).to eq("")
      end
    end

    context "with Hash input" do
      context "with symbol keys" do
        it "extracts :text key first" do
          hash = { text: "text value", name: "name value", value: "value value" }
          expect(extractor.extract_from(hash)).to eq("text value")
        end

        it "extracts :name key when :text is missing" do
          hash = { name: "name value", value: "value value" }
          expect(extractor.extract_from(hash)).to eq("name value")
        end

        it "extracts :value key when :text and :name are missing" do
          hash = { value: "value value", description: "desc value" }
          expect(extractor.extract_from(hash)).to eq("value value")
        end

        it "extracts :merchant_name key" do
          hash = { merchant_name: "merchant value" }
          expect(extractor.extract_from(hash)).to eq("merchant value")
        end

        it "extracts :description key as last resort" do
          hash = { description: "desc value" }
          expect(extractor.extract_from(hash)).to eq("desc value")
        end
      end

      context "with string keys" do
        it "extracts 'text' key first" do
          hash = { "text" => "text value", "name" => "name value" }
          expect(extractor.extract_from(hash)).to eq("text value")
        end

        it "extracts 'name' key when 'text' is missing" do
          hash = { "name" => "name value", "value" => "value value" }
          expect(extractor.extract_from(hash)).to eq("name value")
        end

        it "extracts 'value' key when 'text' and 'name' are missing" do
          hash = { "value" => "value value" }
          expect(extractor.extract_from(hash)).to eq("value value")
        end

        it "extracts 'merchant_name' key" do
          hash = { "merchant_name" => "merchant value" }
          expect(extractor.extract_from(hash)).to eq("merchant value")
        end

        it "extracts 'description' key as last resort" do
          hash = { "description" => "desc value" }
          expect(extractor.extract_from(hash)).to eq("desc value")
        end
      end

      context "with mixed symbol and string keys" do
        it "prefers symbol :text over string 'text'" do
          hash = { text: "symbol text", "text" => "string text" }
          expect(extractor.extract_from(hash)).to eq("symbol text")
        end

        it "falls back to string 'text' when symbol :text is nil" do
          hash = { text: nil, "text" => "string text" }
          expect(extractor.extract_from(hash)).to eq("string text")
        end
      end

      context "with nil or false values" do
        it "skips nil values and continues to next key" do
          hash = { text: nil, name: "name value" }
          expect(extractor.extract_from(hash)).to eq("name value")
        end

        it "returns nil when value is false (falsy)" do
          hash = { text: false }
          # False is falsy, so || operator continues to next key
          expect(extractor.extract_from(hash)).to be_nil
        end

        it "returns nil when all values are nil" do
          hash = { text: nil, name: nil, value: nil }
          expect(extractor.extract_from(hash)).to be_nil
        end

        it "returns nil when hash has no matching keys" do
          hash = { unrelated: "value" }
          expect(extractor.extract_from(hash)).to be_nil
        end
      end
    end

    context "with CategorizationPattern object" do
      let(:pattern) { double("CategorizationPattern") }

      before do
        allow(pattern).to receive(:class).and_return(double(name: "CategorizationPattern"))
      end

      it "extracts pattern_value when available" do
        allow(pattern).to receive(:respond_to?).with(:pattern_value).and_return(true)
        allow(pattern).to receive(:pattern_value).and_return("pattern text")

        expect(extractor.extract_from(pattern)).to eq("pattern text")
      end

      it "returns nil when pattern_value is not available" do
        allow(pattern).to receive(:respond_to?).with(:pattern_value).and_return(false)

        expect(extractor.extract_from(pattern)).to be_nil
      end

      it "returns nil when pattern_value is nil" do
        allow(pattern).to receive(:respond_to?).with(:pattern_value).and_return(true)
        allow(pattern).to receive(:pattern_value).and_return(nil)

        expect(extractor.extract_from(pattern)).to be_nil
      end
    end

    context "with Expense object" do
      let(:expense) { double("Expense") }

      before do
        allow(expense).to receive(:class).and_return(double(name: "Expense"))
      end

      it "extracts merchant_name when available and present" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(expense).to receive(:merchant_name?).and_return(true)
        allow(expense).to receive(:merchant_name).and_return("Merchant Name")

        expect(extractor.extract_from(expense)).to eq("Merchant Name")
      end

      it "falls back to merchant_normalized when merchant_name is not present" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(expense).to receive(:merchant_name?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(true)
        allow(expense).to receive(:merchant_normalized?).and_return(true)
        allow(expense).to receive(:merchant_normalized).and_return("Normalized Name")

        expect(extractor.extract_from(expense)).to eq("Normalized Name")
      end

      it "falls back to description when merchant fields are not present" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(expense).to receive(:merchant_name?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(true)
        allow(expense).to receive(:merchant_normalized?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:description).and_return(true)
        allow(expense).to receive(:description?).and_return(true)
        allow(expense).to receive(:description).and_return("Expense Description")

        expect(extractor.extract_from(expense)).to eq("Expense Description")
      end

      it "uses read_attribute when direct methods are not available" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(false)
        allow(expense).to receive(:respond_to?).with(:description).and_return(false)
        allow(expense).to receive(:respond_to?).with(:read_attribute).and_return(true)
        allow(expense).to receive(:read_attribute).with(:merchant_name).and_return("Read Merchant")

        expect(extractor.extract_from(expense)).to eq("Read Merchant")
      end

      it "falls back through read_attribute calls" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(false)
        allow(expense).to receive(:respond_to?).with(:description).and_return(false)
        allow(expense).to receive(:respond_to?).with(:read_attribute).and_return(true)
        allow(expense).to receive(:read_attribute).with(:merchant_name).and_return(nil)
        allow(expense).to receive(:read_attribute).with(:merchant_normalized).and_return(nil)
        allow(expense).to receive(:read_attribute).with(:description).and_return("Read Description")

        expect(extractor.extract_from(expense)).to eq("Read Description")
      end

      it "returns nil when no methods are available" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(false)
        allow(expense).to receive(:respond_to?).with(:description).and_return(false)
        allow(expense).to receive(:respond_to?).with(:read_attribute).and_return(false)

        expect(extractor.extract_from(expense)).to be_nil
      end

      it "returns nil when all fields are empty" do
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(expense).to receive(:merchant_name?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(true)
        allow(expense).to receive(:merchant_normalized?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:description).and_return(true)
        allow(expense).to receive(:description?).and_return(false)
        allow(expense).to receive(:respond_to?).with(:read_attribute).and_return(true)
        allow(expense).to receive(:read_attribute).with(:merchant_name).and_return(nil)
        allow(expense).to receive(:read_attribute).with(:merchant_normalized).and_return(nil)
        allow(expense).to receive(:read_attribute).with(:description).and_return(nil)

        expect(extractor.extract_from(expense)).to be_nil
      end
    end

    context "with CanonicalMerchant object" do
      let(:merchant) { double("CanonicalMerchant") }

      before do
        allow(merchant).to receive(:class).and_return(double(name: "CanonicalMerchant"))
      end

      it "extracts name when available" do
        allow(merchant).to receive(:respond_to?).with(:name).and_return(true)
        allow(merchant).to receive(:name).and_return("Canonical Name")

        expect(extractor.extract_from(merchant)).to eq("Canonical Name")
      end

      it "returns nil when name method is not available" do
        allow(merchant).to receive(:respond_to?).with(:name).and_return(false)

        expect(extractor.extract_from(merchant)).to be_nil
      end

      it "returns nil when name is nil" do
        allow(merchant).to receive(:respond_to?).with(:name).and_return(true)
        allow(merchant).to receive(:name).and_return(nil)

        expect(extractor.extract_from(merchant)).to be_nil
      end
    end

    context "with MerchantAlias object" do
      let(:alias_obj) { double("MerchantAlias") }

      before do
        allow(alias_obj).to receive(:class).and_return(double(name: "MerchantAlias"))
      end

      it "prefers normalized_name when present" do
        # Create a double that acts like a string with present? method
        normalized_value = double("normalized_name_value")
        allow(normalized_value).to receive(:present?).and_return(true)

        allow(alias_obj).to receive(:respond_to?).with(:normalized_name).and_return(true)
        allow(alias_obj).to receive(:normalized_name).and_return(normalized_value)

        # The actual code returns the normalized_name value itself when present? is true
        expect(extractor.extract_from(alias_obj)).to eq(normalized_value)
      end

      it "falls back to raw_name when normalized_name is blank" do
        allow(alias_obj).to receive(:respond_to?).with(:normalized_name).and_return(true)

        # Create a double that acts like an empty string
        empty_value = double("empty_value")
        allow(empty_value).to receive(:present?).and_return(false)

        allow(alias_obj).to receive(:normalized_name).and_return(empty_value)
        allow(alias_obj).to receive(:respond_to?).with(:raw_name).and_return(true)
        allow(alias_obj).to receive(:raw_name).and_return("Raw Alias")

        expect(extractor.extract_from(alias_obj)).to eq("Raw Alias")
      end

      it "falls back to raw_name when normalized_name is not available" do
        allow(alias_obj).to receive(:respond_to?).with(:normalized_name).and_return(false)
        allow(alias_obj).to receive(:respond_to?).with(:raw_name).and_return(true)
        allow(alias_obj).to receive(:raw_name).and_return("Raw Alias")

        expect(extractor.extract_from(alias_obj)).to eq("Raw Alias")
      end

      it "returns nil when neither method is available" do
        allow(alias_obj).to receive(:respond_to?).with(:normalized_name).and_return(false)
        allow(alias_obj).to receive(:respond_to?).with(:raw_name).and_return(false)

        expect(extractor.extract_from(alias_obj)).to be_nil
      end

      it "returns nil when both fields are nil" do
        allow(alias_obj).to receive(:respond_to?).with(:normalized_name).and_return(true)
        allow(alias_obj).to receive(:normalized_name).and_return(nil)
        allow(alias_obj).to receive(:respond_to?).with(:raw_name).and_return(true)
        allow(alias_obj).to receive(:raw_name).and_return(nil)

        expect(extractor.extract_from(alias_obj)).to be_nil
      end
    end

    context "with generic object" do
      let(:generic_obj) { double("GenericObject") }

      before do
        allow(generic_obj).to receive(:class).and_return(double(name: "SomeOtherClass"))
      end

      it "extracts name when available" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(true)
        allow(generic_obj).to receive(:name).and_return("Generic Name")

        expect(extractor.extract_from(generic_obj)).to eq("Generic Name")
      end

      it "falls back to title when name is not available" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:title).and_return(true)
        allow(generic_obj).to receive(:title).and_return("Generic Title")

        expect(extractor.extract_from(generic_obj)).to eq("Generic Title")
      end

      it "falls back to value when name and title are not available" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:title).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:value).and_return(true)
        allow(generic_obj).to receive(:value).and_return("Generic Value")

        expect(extractor.extract_from(generic_obj)).to eq("Generic Value")
      end

      it "falls back to to_s for meaningful string representations" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:title).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:value).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:to_s).and_return(true)
        allow(generic_obj).to receive(:to_s).and_return("Meaningful String")

        expect(extractor.extract_from(generic_obj)).to eq("Meaningful String")
      end

      it "returns nil for inspection-style strings" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:title).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:value).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:to_s).and_return(true)
        allow(generic_obj).to receive(:to_s).and_return("#<Object:0x00007f8b9a0>")

        expect(extractor.extract_from(generic_obj)).to be_nil
      end

      it "returns nil when no methods are available" do
        allow(generic_obj).to receive(:respond_to?).with(:name).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:title).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:value).and_return(false)
        allow(generic_obj).to receive(:respond_to?).with(:to_s).and_return(false)

        expect(extractor.extract_from(generic_obj)).to be_nil
      end
    end

    context "with nil input" do
      it "returns nil" do
        expect(extractor.extract_from(nil)).to be_nil
      end
    end

    context "with nil expense object" do
      it "handles nil expense gracefully" do
        expense = nil
        allow(expense).to receive(:class).and_return(double(name: "Expense")) if expense

        expect(extractor.extract_from(nil)).to be_nil
      end
    end

    context "with nil alias object" do
      it "handles nil alias gracefully" do
        alias_obj = nil
        allow(alias_obj).to receive(:class).and_return(double(name: "MerchantAlias")) if alias_obj

        expect(extractor.extract_from(nil)).to be_nil
      end
    end
  end

  describe "#extract_from_many" do
    it "processes multiple objects of the same type" do
      objects = [ "string1", "string2", "string3" ]

      expect(extractor.extract_from_many(objects)).to eq([ "string1", "string2", "string3" ])
    end

    it "processes multiple objects of different types" do
      hash = { text: "hash text" }
      pattern = double("CategorizationPattern")
      allow(pattern).to receive(:class).and_return(double(name: "CategorizationPattern"))
      allow(pattern).to receive(:respond_to?).with(:pattern_value).and_return(true)
      allow(pattern).to receive(:pattern_value).and_return("pattern text")

      objects = [ "string", hash, pattern ]

      expect(extractor.extract_from_many(objects)).to eq([ "string", "hash text", "pattern text" ])
    end

    it "handles empty array" do
      expect(extractor.extract_from_many([])).to eq([])
    end

    it "handles array with nil values" do
      objects = [ "string", nil, { name: "hash" } ]

      expect(extractor.extract_from_many(objects)).to eq([ "string", nil, "hash" ])
    end

    it "processes mixed valid and invalid objects" do
      expense = double("Expense")
      allow(expense).to receive(:class).and_return(double(name: "Expense"))
      allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
      allow(expense).to receive(:merchant_name?).and_return(true)
      allow(expense).to receive(:merchant_name).and_return("Expense Merchant")

      merchant = double("CanonicalMerchant")
      allow(merchant).to receive(:class).and_return(double(name: "CanonicalMerchant"))
      allow(merchant).to receive(:respond_to?).with(:name).and_return(false)

      objects = [ expense, merchant, "plain text", nil ]

      expect(extractor.extract_from_many(objects)).to eq([ "Expense Merchant", nil, "plain text", nil ])
    end

    it "maintains order of input objects" do
      obj1 = { text: "first" }
      obj2 = { name: "second" }
      obj3 = "third"

      objects = [ obj1, obj2, obj3 ]

      expect(extractor.extract_from_many(objects)).to eq([ "first", "second", "third" ])
    end
  end

  describe "edge cases" do
    context "with complex nested scenarios" do
      it "handles objects with nil class names gracefully" do
        obj = double("Object")
        allow(obj).to receive(:class).and_return(double(name: nil))
        allow(obj).to receive(:respond_to?).with(:name).and_return(true)
        allow(obj).to receive(:name).and_return("Object Name")

        expect(extractor.extract_from(obj)).to eq("Object Name")
      end

      it "handles hash with all nil values correctly" do
        hash = {
          text: nil,
          "text" => nil,
          name: nil,
          "name" => nil,
          value: nil,
          "value" => nil,
          merchant_name: nil,
          "merchant_name" => nil,
          description: nil,
          "description" => nil
        }

        expect(extractor.extract_from(hash)).to be_nil
      end

      it "handles expense with partial method availability" do
        expense = double("Expense")
        allow(expense).to receive(:class).and_return(double(name: "Expense"))

        # merchant_name exists but returns false for presence check
        allow(expense).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(expense).to receive(:merchant_name?).and_return(false)

        # merchant_normalized doesn't exist
        allow(expense).to receive(:respond_to?).with(:merchant_normalized).and_return(false)

        # description exists and has value
        allow(expense).to receive(:respond_to?).with(:description).and_return(true)
        allow(expense).to receive(:description?).and_return(true)
        allow(expense).to receive(:description).and_return("Fallback Description")

        # read_attribute exists but not needed
        allow(expense).to receive(:respond_to?).with(:read_attribute).and_return(true)

        expect(extractor.extract_from(expense)).to eq("Fallback Description")
      end
    end

    context "with unusual but valid inputs" do
      it "handles numeric values in hashes" do
        hash = { value: 42 }
        expect(extractor.extract_from(hash)).to eq(42)
      end

      it "handles boolean true in hashes" do
        hash = { text: true }
        expect(extractor.extract_from(hash)).to eq(true)
      end

      it "handles empty arrays in hashes" do
        hash = { value: [] }
        expect(extractor.extract_from(hash)).to eq([])
      end

      it "handles objects in hashes" do
        obj = { nested: "value" }
        hash = { text: obj }
        expect(extractor.extract_from(hash)).to eq(obj)
      end
    end

    context "with performance considerations" do
      it "short-circuits hash extraction on first match" do
        # This hash has all keys, but we should only access :text
        hash = { text: "found", name: "not accessed", value: "not accessed" }

        # We can't directly test that other keys aren't accessed,
        # but we verify the correct value is returned
        expect(extractor.extract_from(hash)).to eq("found")
      end

      it "processes large batches efficiently" do
        objects = Array.new(1000) { |i| "string_#{i}" }
        results = extractor.extract_from_many(objects)

        expect(results.size).to eq(1000)
        expect(results.first).to eq("string_0")
        expect(results.last).to eq("string_999")
      end
    end
  end
end
