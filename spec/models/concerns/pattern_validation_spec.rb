# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatternValidation do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new(CategorizationPattern) do
      def self.name
        "TestPattern"
      end
    end
  end

  let(:category) { create(:category) }
  let(:pattern) { test_class.new(category: category) }

  describe "normalization" do
    context "text patterns" do
      it "normalizes merchant patterns to lowercase and strips whitespace" do
        pattern.pattern_type = "merchant"
        pattern.pattern_value = "  STARBUCKS  "
        pattern.valid?
        expect(pattern.pattern_value).to eq("starbucks")
      end

      it "normalizes keyword patterns" do
        pattern.pattern_type = "keyword"
        pattern.pattern_value = "  Coffee  Shop  "
        pattern.valid?
        expect(pattern.pattern_value).to eq("coffee shop")
      end

      it "removes excessive whitespace" do
        pattern.pattern_type = "description"
        pattern.pattern_value = "purchase   at    store"
        pattern.valid?
        expect(pattern.pattern_value).to eq("purchase at store")
      end
    end

    context "amount ranges" do
      it "normalizes amount format to two decimal places" do
        pattern.pattern_type = "amount_range"
        pattern.pattern_value = "10-50.5"
        pattern.valid?
        expect(pattern.pattern_value).to eq("10.00-50.50")
      end

      it "handles negative amounts" do
        pattern.pattern_type = "amount_range"
        pattern.pattern_value = "-100--50"
        pattern.valid?
        expect(pattern.pattern_value).to eq("-100.00--50.00")
      end
    end

    context "regex patterns" do
      it "does not normalize regex patterns" do
        pattern.pattern_type = "regex"
        pattern.pattern_value = "  \\b(Coffee|CAFE)\\b  "
        pattern.valid?
        expect(pattern.pattern_value).to eq("\\b(Coffee|CAFE)\\b")
      end
    end

    context "time patterns" do
      it "normalizes time patterns to lowercase" do
        pattern.pattern_type = "time"
        pattern.pattern_value = "MORNING"
        pattern.valid?
        expect(pattern.pattern_value).to eq("morning")
      end
    end
  end

  describe "validation" do
    context "text pattern validation" do
      before do
        pattern.pattern_type = "merchant"
      end

      it "requires minimum length" do
        pattern.pattern_value = "a"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be at least 2 characters long")
      end

      it "enforces maximum length" do
        pattern.pattern_value = "a" * 256
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be no more than 255 characters long")
      end

      it "rejects control characters" do
        # Use a control character that won't crash the database query
        pattern.pattern_value = "test\x01pattern"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("contains invalid control characters")
      end

      it "rejects overly generic patterns" do
        pattern.pattern_value = "the"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("is too generic to be useful for categorization")
      end

      it "accepts valid patterns" do
        pattern.pattern_value = "starbucks"
        expect(pattern).to be_valid
      end
    end

    context "amount range validation" do
      before do
        pattern.pattern_type = "amount_range"
      end

      it "validates format" do
        pattern.pattern_value = "invalid"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be in format 'min-max' (e.g., '10.00-50.00')")
      end

      it "ensures min is less than max" do
        pattern.pattern_value = "100.00-50.00"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("minimum amount must be less than maximum amount")
      end

      it "warns about extremely large ranges" do
        pattern.pattern_value = "0.00-15000.00"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("range is too broad (difference > 10,000)")
      end

      it "accepts valid ranges" do
        pattern.pattern_value = "10.00-50.00"
        expect(pattern).to be_valid
      end

      it "handles negative amounts and adds metadata" do
        pattern.pattern_value = "-100.00--10.00"
        expect(pattern).to be_valid
        expect(pattern.metadata["has_negative_amounts"]).to be true
      end
    end

    context "time pattern validation" do
      before do
        pattern.pattern_type = "time"
      end

      it "accepts predefined time patterns" do
        %w[morning afternoon evening night weekend weekday].each do |time_pattern|
          pattern.pattern_value = time_pattern
          expect(pattern).to be_valid
        end
      end

      it "accepts time range format" do
        pattern.pattern_value = "09:00-17:00"
        expect(pattern).to be_valid
      end

      it "validates hour range" do
        pattern.pattern_value = "25:00-26:00"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("hours must be between 0 and 23")
      end

      it "validates minute range" do
        pattern.pattern_value = "10:75-11:80"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("minutes must be between 0 and 59")
      end

      it "rejects invalid formats" do
        pattern.pattern_value = "invalid_time"
        expect(pattern).not_to be_valid
      end
    end

    context "regex pattern validation" do
      before do
        pattern.pattern_type = "regex"
      end

      it "validates regex syntax" do
        pattern.pattern_value = "[unclosed"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value].first).to match(/invalid regular expression/)
      end

      it "detects dangerous patterns (ReDoS)" do
        dangerous_patterns = [
          "(a+)+",
          "(a*)*",
          "(a+)*",
          "([a-z]+)*",
          "(.*)*"
        ]

        dangerous_patterns.each do |dangerous|
          pattern.pattern_value = dangerous
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("contains potentially dangerous regex pattern (ReDoS vulnerability)")
        end
      end

      it "enforces maximum length" do
        pattern.pattern_value = "a" * 101
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("regex pattern is too long (max 100 characters)")
      end

      it "accepts valid regex patterns" do
        valid_patterns = [
          "\\b(coffee|cafe)\\b",
          "\\d{4}-\\d{2}-\\d{2}",
          "[A-Z]+",
          "test.*pattern"
        ]

        valid_patterns.each do |valid|
          pattern.pattern_value = valid
          expect(pattern).to be_valid
        end
      end
    end

    context "pattern complexity" do
      it "calculates complexity score for regex patterns" do
        pattern.pattern_type = "regex"
        pattern.pattern_value = "(a|b)+(c|d)*[e-z]{2,5}"
        pattern.valid?
        expect(pattern.metadata["complexity_score"]).to be > 0
      end

      it "rejects overly complex patterns" do
        pattern.pattern_type = "regex"
        pattern.pattern_value = "((a+|b+)|(c+|d+))*((e+|f+)|(g+|h+))*"
        expect(pattern).not_to be_valid
        # This pattern triggers ReDoS detection, not complexity score
        expect(pattern.errors[:pattern_value].first).to match(/dangerous regex pattern/)
      end

      it "tracks high special character count" do
        pattern.pattern_type = "merchant"
        pattern.pattern_value = "test@#$%^&*()_+"
        pattern.valid?
        expect(pattern.metadata["high_special_chars"]).to be true
      end
    end

    context "duplicate detection" do
      let!(:existing_pattern) do
        create(:categorization_pattern,
               category: category,
               pattern_type: "merchant",
               pattern_value: "starbucks")
      end

      it "prevents exact duplicates" do
        pattern.pattern_type = "merchant"
        pattern.pattern_value = "starbucks"
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("already exists for this category and pattern type")
      end

      it "allows same value for different types" do
        pattern.pattern_type = "keyword"
        pattern.pattern_value = "starbucks"
        expect(pattern).to be_valid
      end

      it "allows same value for different categories" do
        other_category = create(:category)
        pattern.category = other_category
        pattern.pattern_type = "merchant"
        pattern.pattern_value = "starbucks"
        expect(pattern).to be_valid
      end
    end
  end

  describe "integration with CategorizationPattern" do
    let(:pattern) { build(:categorization_pattern, category: category) }

    it "includes the validation concern" do
      expect(CategorizationPattern.ancestors).to include(PatternValidation)
    end

    it "applies validations on save" do
      pattern.pattern_type = "merchant"
      pattern.pattern_value = "a" # Too short
      expect(pattern.save).to be false
      expect(pattern.errors[:pattern_value]).to be_present
    end

    it "normalizes before saving" do
      pattern.pattern_type = "merchant"
      pattern.pattern_value = "  WALMART  "
      pattern.save!
      expect(pattern.reload.pattern_value).to eq("walmart")
    end
  end
end
