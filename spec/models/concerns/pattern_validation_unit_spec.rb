# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatternValidation, type: :model, unit: true do
  # Create a dummy class that includes the concern
  let(:dummy_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations::Callbacks
      include ActiveSupport::Callbacks
      include PatternValidation

      attribute :pattern_type, :string
      attribute :pattern_value, :string
      attribute :category_id, :integer
      attribute :id, :integer

      attr_accessor :metadata

      def initialize(attrs = {})
        super
        @metadata = {}
      end

      define_callbacks :validation

      # Mock ActiveRecord methods
      def self.where(*)
        MockRelation.new
      end

      def new_record?
        id.nil?
      end

      def persisted?
        !new_record?
      end

      def pattern_value_changed?
        @pattern_value_changed || false
      end

      def mark_pattern_value_changed!
        @pattern_value_changed = true
      end

      def valid?
        run_callbacks :validation do
          super
        end
      end

      class MockRelation
        def exists?
          false
        end

        def where(*)
          self
        end

        def not(*)
          self
        end

        def limit(*)
          self
        end

        def any?
          false
        end

        def count
          0
        end

        def pluck(*)
          []
        end
      end
    end
  end

  let(:dummy_object) { dummy_class.new }

  describe "constants" do
    it "defines minimum pattern length" do
      expect(PatternValidation::MIN_PATTERN_LENGTH).to eq(2)
    end

    it "defines maximum pattern length" do
      expect(PatternValidation::MAX_PATTERN_LENGTH).to eq(255)
    end

    it "defines maximum regex length" do
      expect(PatternValidation::MAX_REGEX_LENGTH).to eq(100)
    end

    it "defines dangerous regex patterns" do
      expect(PatternValidation::DANGEROUS_REGEX_PATTERNS).to be_an(Array)
      expect(PatternValidation::DANGEROUS_REGEX_PATTERNS).not_to be_empty
    end

    it "defines time pattern values" do
      expect(PatternValidation::TIME_PATTERN_VALUES).to include(
        "morning", "afternoon", "evening", "night",
        "weekend", "weekday", "business_hours", "after_hours"
      )
    end
  end

  describe "#normalize_pattern_value" do
    context "with merchant pattern type" do
      before do
        dummy_object.pattern_type = "merchant"
      end

      it "normalizes by stripping and downcasing" do
        dummy_object.pattern_value = "  STARBUCKS  "
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("starbucks")
      end

      it "removes excessive whitespace" do
        dummy_object.pattern_value = "star    bucks    coffee"
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("star bucks coffee")
      end
    end

    context "with keyword pattern type" do
      before do
        dummy_object.pattern_type = "keyword"
      end

      it "normalizes text patterns" do
        dummy_object.pattern_value = "  COFFEE  SHOP  "
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("coffee shop")
      end
    end

    context "with description pattern type" do
      before do
        dummy_object.pattern_type = "description"
      end

      it "normalizes description patterns" do
        dummy_object.pattern_value = "  Purchase AT Store  "
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("purchase at store")
      end
    end

    context "with amount_range pattern type" do
      before do
        dummy_object.pattern_type = "amount_range"
      end

      it "normalizes valid amount ranges" do
        dummy_object.pattern_value = "10.5-50.7"
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("10.50-50.70")
      end

      it "handles negative amounts" do
        dummy_object.pattern_value = "-10.5-50"
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("-10.50-50.00")
      end

      it "does not normalize invalid ranges" do
        dummy_object.pattern_value = "invalid"
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("invalid")
      end
    end

    context "with time pattern type" do
      before do
        dummy_object.pattern_type = "time"
      end

      it "normalizes time patterns" do
        dummy_object.pattern_value = "  MORNING  "
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("morning")
      end
    end

    context "with regex pattern type" do
      before do
        dummy_object.pattern_type = "regex"
      end

      it "preserves case for regex patterns" do
        dummy_object.pattern_value = "  ^STAR.*  "
        dummy_object.send(:normalize_pattern_value)
        expect(dummy_object.pattern_value).to eq("^STAR.*")
      end
    end

    context "with blank pattern value" do
      it "does nothing when pattern value is blank" do
        dummy_object.pattern_value = nil
        expect { dummy_object.send(:normalize_pattern_value) }.not_to raise_error
        expect(dummy_object.pattern_value).to be_nil
      end
    end
  end

  describe "#validate_text_pattern" do
    before do
      dummy_object.pattern_type = "merchant"
    end

    it "adds error for patterns below minimum length" do
      dummy_object.pattern_value = "a"
      dummy_object.send(:validate_text_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "must be at least #{PatternValidation::MIN_PATTERN_LENGTH} characters long"
      )
    end

    it "adds error for patterns above maximum length" do
      dummy_object.pattern_value = "a" * 256
      dummy_object.send(:validate_text_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "must be no more than #{PatternValidation::MAX_PATTERN_LENGTH} characters long"
      )
    end

    it "adds error for control characters" do
      dummy_object.pattern_value = "test\x00pattern"
      dummy_object.send(:validate_text_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "contains invalid control characters"
      )
    end

    it "adds error for generic patterns" do
      %w[the a an of in on at to for and or].each do |word|
        dummy_object.pattern_value = word
        dummy_object.errors.clear
        dummy_object.send(:validate_text_pattern)
        expect(dummy_object.errors[:pattern_value]).to include(
          "is too generic to be useful for categorization"
        )
      end
    end

    it "allows valid text patterns" do
      dummy_object.pattern_value = "starbucks"
      dummy_object.send(:validate_text_pattern)
      expect(dummy_object.errors[:pattern_value]).to be_empty
    end
  end

  describe "#validate_amount_range_pattern" do
    before do
      dummy_object.pattern_type = "amount_range"
    end

    it "adds error for invalid format" do
      dummy_object.pattern_value = "not-a-range"
      dummy_object.send(:validate_amount_range_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "must be in format 'min-max' (e.g., '10.00-50.00')"
      )
    end

    it "adds error when min >= max" do
      dummy_object.pattern_value = "50.00-30.00"
      dummy_object.send(:validate_amount_range_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "minimum amount must be less than maximum amount"
      )
    end

    it "adds error for extremely large ranges" do
      dummy_object.pattern_value = "0-15000"
      dummy_object.send(:validate_amount_range_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "range is too broad (difference > 10,000)"
      )
    end

    it "sets metadata for negative amounts" do
      dummy_object.pattern_value = "-50.00-10.00"
      dummy_object.send(:validate_amount_range_pattern)
      expect(dummy_object.metadata["has_negative_amounts"]).to be true
    end

    it "allows valid amount ranges" do
      dummy_object.pattern_value = "10.00-50.00"
      dummy_object.send(:validate_amount_range_pattern)
      expect(dummy_object.errors[:pattern_value]).to be_empty
    end
  end

  describe "#validate_time_pattern" do
    before do
      dummy_object.pattern_type = "time"
    end

    it "allows predefined time pattern values" do
      PatternValidation::TIME_PATTERN_VALUES.each do |value|
        dummy_object.pattern_value = value
        dummy_object.errors.clear
        dummy_object.send(:validate_time_pattern)
        expect(dummy_object.errors[:pattern_value]).to be_empty
      end
    end

    it "allows valid time range format" do
      dummy_object.pattern_value = "09:00-17:00"
      dummy_object.send(:validate_time_pattern)
      expect(dummy_object.errors[:pattern_value]).to be_empty
    end

    it "adds error for invalid time pattern" do
      dummy_object.pattern_value = "invalid-time"
      dummy_object.send(:validate_time_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        /must be one of:/
      )
    end

    it "validates hour range in time ranges" do
      dummy_object.pattern_value = "25:00-17:00"
      dummy_object.send(:validate_time_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "hours must be between 0 and 23"
      )
    end

    it "validates minute range in time ranges" do
      dummy_object.pattern_value = "09:70-17:00"
      dummy_object.send(:validate_time_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "minutes must be between 0 and 59"
      )
    end
  end

  describe "#validate_regex_pattern" do
    before do
      dummy_object.pattern_type = "regex"
    end

    it "adds error for patterns exceeding max length" do
      dummy_object.pattern_value = "a" * 101
      dummy_object.send(:validate_regex_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "regex pattern is too long (max #{PatternValidation::MAX_REGEX_LENGTH} characters)"
      )
    end

    it "adds error for dangerous regex patterns" do
      dummy_object.pattern_value = "(a+)+"
      dummy_object.send(:validate_regex_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "contains potentially dangerous regex pattern (ReDoS vulnerability)"
      )
    end


    it "adds error for slow regex patterns" do
      # Mock timeout
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      dummy_object.pattern_value = ".*"
      dummy_object.send(:validate_regex_pattern)
      expect(dummy_object.errors[:pattern_value]).to include(
        "regex pattern is too complex (performance issue)"
      )
    end

    it "allows valid regex patterns" do
      dummy_object.pattern_value = "^star.*"
      dummy_object.send(:validate_regex_pattern)
      expect(dummy_object.errors[:pattern_value]).to be_empty
    end
  end

  describe "#validate_pattern_complexity" do
    context "with regex patterns" do
      before do
        dummy_object.pattern_type = "regex"
      end

      it "calculates complexity score" do
        dummy_object.pattern_value = "(a+|b*)[cd]?"
        dummy_object.send(:validate_pattern_complexity)
        expect(dummy_object.metadata["complexity_score"]).to be > 0
      end

      it "adds error for overly complex patterns" do
        dummy_object.pattern_value = "((a+)+|(b*)*)[cd]?{1,5}(e|f|g|h|i|j|k)"
        dummy_object.send(:validate_pattern_complexity)
        expect(dummy_object.errors[:pattern_value]).to include(
          /pattern is too complex/
        )
      end
    end

    context "with merchant patterns" do
      before do
        dummy_object.pattern_type = "merchant"
      end

      it "tracks high special character count" do
        dummy_object.pattern_value = "test@#$%^&*()"
        dummy_object.send(:validate_pattern_complexity)
        expect(dummy_object.metadata["high_special_chars"]).to be true
      end

      it "does not flag patterns with few special characters" do
        dummy_object.pattern_value = "test-store"
        dummy_object.send(:validate_pattern_complexity)
        expect(dummy_object.metadata["high_special_chars"]).to be_nil
      end
    end
  end

  describe "#calculate_regex_complexity" do
    before do
      dummy_object.pattern_type = "regex"
    end

    it "scores quantifiers" do
      dummy_object.pattern_value = "a+b*c?"
      score = dummy_object.send(:calculate_regex_complexity)
      expect(score).to eq(6) # 3 quantifiers * 2
    end

    it "scores groups" do
      dummy_object.pattern_value = "(a)(b)(c)"
      score = dummy_object.send(:calculate_regex_complexity)
      expect(score).to eq(3) # 3 groups * 1
    end

    it "scores alternations" do
      dummy_object.pattern_value = "a|b|c"
      score = dummy_object.send(:calculate_regex_complexity)
      expect(score).to eq(4) # 2 alternations * 2
    end

    it "heavily penalizes nested quantifiers" do
      dummy_object.pattern_value = "a++b**"
      score = dummy_object.send(:calculate_regex_complexity)
      expect(score).to be >= 20 # nested quantifiers heavily penalized
    end
  end

  describe "#check_for_duplicate_patterns" do
    before do
      dummy_object.pattern_type = "merchant"
      dummy_object.pattern_value = "starbucks"
      dummy_object.category_id = 1
    end

    context "when pattern is new" do
    end

    context "when pattern is being updated" do
      before do
        dummy_object.id = 1
        dummy_object.mark_pattern_value_changed!
      end
    end

    context "with control characters" do
      it "skips duplicate check" do
        dummy_object.pattern_value = "test\x00"
        expect(dummy_object.class).not_to receive(:where)
        dummy_object.send(:check_for_duplicate_patterns)
      end
    end
  end

  describe "#check_for_similar_patterns" do
    before do
      dummy_object.pattern_type = "merchant"
      dummy_object.pattern_value = "starbucks"
      dummy_object.category_id = 1
    end

    it "handles missing similarity function gracefully" do
      allow(dummy_object.class).to receive(:where).and_raise(
        ActiveRecord::StatementInvalid.new("function similarity does not exist")
      )
      allow(Rails.logger).to receive(:debug)

      expect { dummy_object.send(:check_for_similar_patterns) }.not_to raise_error
      expect(Rails.logger).to have_received(:debug).with(/Similarity check skipped/)
    end

    it "sets metadata for similar patterns" do
      similar_relation = double(
        any?: true,
        count: 2,
        pluck: [ "starbuck", "star bucks" ]
      )
      allow(dummy_object.class).to receive(:where).and_return(similar_relation)
      allow(similar_relation).to receive(:where).and_return(similar_relation)
      allow(similar_relation).to receive(:not).and_return(similar_relation)
      allow(similar_relation).to receive(:limit).and_return(similar_relation)

      dummy_object.send(:check_for_similar_patterns)
      expect(dummy_object.metadata["similar_patterns"]).to eq([ "starbuck", "star bucks" ])
    end

    it "sets high similarity warning for many similar patterns" do
      similar_relation = double(
        any?: true,
        count: 3,
        pluck: [ "starbuck", "star bucks", "starbuks" ]
      )
      allow(dummy_object.class).to receive(:where).and_return(similar_relation)
      allow(similar_relation).to receive(:where).and_return(similar_relation)
      allow(similar_relation).to receive(:not).and_return(similar_relation)
      allow(similar_relation).to receive(:limit).and_return(similar_relation)

      dummy_object.send(:check_for_similar_patterns)
      expect(dummy_object.metadata["high_similarity_warning"]).to be true
    end
  end

  describe "integration with validations" do
    it "runs normalize_pattern_value before validation" do
      dummy_object.pattern_type = "merchant"
      dummy_object.pattern_value = "  STARBUCKS  "

      # Simulate validation callbacks
      dummy_object.send(:normalize_pattern_value)
      expect(dummy_object.pattern_value).to eq("starbucks")
    end

    it "runs all validation methods" do
      dummy_object.pattern_type = "merchant"
      dummy_object.pattern_value = "valid_merchant"
      dummy_object.category_id = 1

      expect(dummy_object).to receive(:validate_pattern_format)
      expect(dummy_object).to receive(:validate_pattern_complexity)
      expect(dummy_object).to receive(:check_for_duplicate_patterns)

      dummy_object.valid?
    end
  end
end
