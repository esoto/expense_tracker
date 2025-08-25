# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationPattern, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_categorization_pattern(attributes = {})
    default_attributes = {
      pattern_type: "merchant",
      pattern_value: "amazon",
      confidence_weight: 1.0,
      usage_count: 0,
      success_count: 0,
      success_rate: 0.0,
      active: true,
      user_created: false,
      metadata: {},
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:categorization_pattern, default_attributes.merge(attributes))
  end

  describe "constants" do
    it "defines pattern types" do
      expect(CategorizationPattern::PATTERN_TYPES).to eq(%w[merchant keyword description amount_range regex time])
    end

    it "defines confidence weight constants" do
      expect(CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT).to eq(1.0)
      expect(CategorizationPattern::MIN_CONFIDENCE_WEIGHT).to eq(0.1)
      expect(CategorizationPattern::MAX_CONFIDENCE_WEIGHT).to eq(5.0)
    end
  end

  describe "included modules" do
    it "includes PatternValidation" do
      expect(CategorizationPattern.ancestors).to include(PatternValidation)
    end
  end

  describe "associations" do
    it { should belong_to(:category) }
    it { should have_many(:pattern_feedbacks).dependent(:destroy) }
    it { should have_many(:expenses).through(:pattern_feedbacks) }
  end

  describe "validations" do
    describe "pattern_type" do
      it "requires pattern_type to be present" do
        pattern = build_categorization_pattern(pattern_type: nil)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_type]).to include("can't be blank")
      end

      it "validates inclusion in PATTERN_TYPES" do
        pattern = build_categorization_pattern(pattern_type: "invalid")
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_type]).to include("is not included in the list")
      end

      it "accepts valid pattern types" do
        CategorizationPattern::PATTERN_TYPES.each do |type|
          # Use appropriate pattern_value for each type
          pattern_value = case type
          when "amount_range"
            "10.00-50.00"
          when "time"
            "morning"
          when "regex"
            "^test$"
          else
            "amazon"
          end
          
          pattern = build_categorization_pattern(pattern_type: type, pattern_value: pattern_value)
          expect(pattern).to be_valid
        end
      end
    end

    describe "pattern_value" do
      it "requires pattern_value to be present" do
        pattern = build_categorization_pattern(pattern_value: nil)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("can't be blank")
      end

      it "validates uniqueness scoped to category and pattern_type" do
        category = build_stubbed(:category, id: 1)
        pattern = build_categorization_pattern(
          category: category,
          pattern_type: "merchant",
          pattern_value: "amazon"
        )
        
        # Mock uniqueness validation
        allow(pattern).to receive(:errors).and_return(ActiveModel::Errors.new(pattern))
        relation = double("relation")
        allow(CategorizationPattern).to receive(:where).and_return(relation)
        allow(relation).to receive(:exists?).and_return(false)
        
        expect(pattern).to be_valid
      end
    end

    describe "confidence_weight" do
      it "accepts valid confidence weights" do
        pattern = build_categorization_pattern(confidence_weight: 2.5)
        expect(pattern).to be_valid
      end

      it "rejects confidence weight below minimum" do
        pattern = build_categorization_pattern(confidence_weight: 0.05)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:confidence_weight]).to include("must be greater than or equal to 0.1")
      end

      it "rejects confidence weight above maximum" do
        pattern = build_categorization_pattern(confidence_weight: 5.1)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:confidence_weight]).to include("must be less than or equal to 5.0")
      end
    end

    describe "usage and success counts" do
      it "accepts zero usage_count" do
        pattern = build_categorization_pattern(usage_count: 0)
        expect(pattern).to be_valid
      end

      it "rejects negative usage_count" do
        pattern = build_categorization_pattern(usage_count: -1)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:usage_count]).to include("must be greater than or equal to 0")
      end

      it "accepts zero success_count" do
        pattern = build_categorization_pattern(success_count: 0)
        expect(pattern).to be_valid
      end

      it "rejects negative success_count" do
        pattern = build_categorization_pattern(success_count: -1)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:success_count]).to include("must be greater than or equal to 0")
      end

      it "validates success_count not greater than usage_count" do
        pattern = build_categorization_pattern(usage_count: 10, success_count: 11)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:success_count]).to include("cannot be greater than usage count")
      end
    end

    describe "success_rate" do
      it "accepts valid success rates" do
        pattern = build_categorization_pattern(success_rate: 0.75)
        expect(pattern).to be_valid
      end

      it "rejects negative success_rate" do
        pattern = build_categorization_pattern(success_rate: -0.1)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:success_rate]).to include("must be greater than or equal to 0.0")
      end

      it "rejects success_rate above 1.0" do
        pattern = build_categorization_pattern(success_rate: 1.1)
        expect(pattern).not_to be_valid
        expect(pattern.errors[:success_rate]).to include("must be less than or equal to 1.0")
      end
    end

    describe "pattern value format validations" do
      context "amount_range pattern" do
        it "accepts valid amount range format" do
          pattern = build_categorization_pattern(
            pattern_type: "amount_range",
            pattern_value: "10.00-50.00"
          )
          expect(pattern).to be_valid
        end

        it "accepts negative amount ranges" do
          pattern = build_categorization_pattern(
            pattern_type: "amount_range",
            pattern_value: "-100--50"
          )
          expect(pattern).to be_valid
        end

        it "rejects invalid amount range format" do
          pattern = build_categorization_pattern(
            pattern_type: "amount_range",
            pattern_value: "invalid"
          )
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("must be in format 'min-max' (e.g., '10.00-50.00' or '-100--50')")
        end

        it "validates min is less than max" do
          pattern = build_categorization_pattern(
            pattern_type: "amount_range",
            pattern_value: "50.00-10.00"
          )
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("minimum must be less than maximum")
        end
      end

      context "regex pattern" do
        it "accepts valid regex" do
          pattern = build_categorization_pattern(
            pattern_type: "regex",
            pattern_value: "^UBER.*"
          )
          expect(pattern).to be_valid
        end

        it "rejects invalid regex" do
          pattern = build_categorization_pattern(
            pattern_type: "regex",
            pattern_value: "[invalid"
          )
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("must be a valid regular expression")
        end

        it "rejects dangerous ReDoS patterns" do
          pattern = build_categorization_pattern(
            pattern_type: "regex",
            pattern_value: "(a+)+"
          )
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("contains potentially dangerous regex pattern (ReDoS vulnerability)")
        end
      end

      context "time pattern" do
        it "accepts valid time keywords" do
          %w[morning afternoon evening night weekend weekday].each do |time_pattern|
            pattern = build_categorization_pattern(
              pattern_type: "time",
              pattern_value: time_pattern
            )
            expect(pattern).to be_valid
          end
        end

        it "accepts valid time range format" do
          pattern = build_categorization_pattern(
            pattern_type: "time",
            pattern_value: "09:00-17:00"
          )
          expect(pattern).to be_valid
        end

        it "rejects invalid time pattern" do
          pattern = build_categorization_pattern(
            pattern_type: "time",
            pattern_value: "invalid_time"
          )
          expect(pattern).not_to be_valid
          expect(pattern.errors[:pattern_value]).to include("must be a valid time pattern")
        end
      end
    end
  end

  describe "scopes" do
    describe ".active" do
      it "filters active patterns" do
        expect(CategorizationPattern.active.to_sql).to include('"active" = TRUE')
      end
    end

    describe ".inactive" do
      it "filters inactive patterns" do
        expect(CategorizationPattern.inactive.to_sql).to include('"active" = FALSE')
      end
    end

    describe ".user_created" do
      it "filters user created patterns" do
        expect(CategorizationPattern.user_created.to_sql).to include('"user_created" = TRUE')
      end
    end

    describe ".system_created" do
      it "filters system created patterns" do
        expect(CategorizationPattern.system_created.to_sql).to include('"user_created" = FALSE')
      end
    end

    describe ".by_type" do
      it "filters by pattern type" do
        result = CategorizationPattern.by_type("merchant")
        expect(result.to_sql).to include("pattern_type")
      end
    end

    describe ".high_confidence" do
      it "filters patterns with confidence weight >= 2.0" do
        expect(CategorizationPattern.high_confidence.to_sql).to include("confidence_weight >= 2.0")
      end
    end

    describe ".successful" do
      it "filters patterns with success rate >= 0.7" do
        expect(CategorizationPattern.successful.to_sql).to include("success_rate >= 0.7")
      end
    end

    describe ".frequently_used" do
      it "filters patterns with usage count >= 10" do
        expect(CategorizationPattern.frequently_used.to_sql).to include("usage_count >= 10")
      end
    end
  end

  describe "callbacks" do
    describe "after_initialize" do
      it "sets default metadata to empty hash" do
        pattern = CategorizationPattern.new
        expect(pattern.metadata).to eq({})
      end

      it "preserves existing metadata" do
        pattern = CategorizationPattern.new(metadata: { "key" => "value" })
        expect(pattern.metadata).to eq({ "key" => "value" })
      end
    end

    describe "before_save" do
      it "calculates success rate" do
        pattern = build_categorization_pattern(usage_count: 10, success_count: 7)
        pattern.send(:calculate_success_rate)
        expect(pattern.success_rate).to eq(0.7)
      end

      it "handles zero usage count" do
        pattern = build_categorization_pattern(usage_count: 0, success_count: 0)
        pattern.send(:calculate_success_rate)
        expect(pattern.success_rate).to eq(0.0)
      end
    end
  end

  describe "#record_usage" do
    let(:pattern) { build_categorization_pattern(id: 1, usage_count: 5, success_count: 3) }

    before do
      allow(CategorizationPattern).to receive(:update_counters)
      allow(pattern).to receive(:reload) do
        pattern.usage_count += 1
        pattern.success_count += 1 if @was_successful
      end
      allow(pattern).to receive(:save!)
    end

    context "when successful" do
      before { @was_successful = true }

      it "increments both usage and success counts" do
        expect(CategorizationPattern).to receive(:update_counters).with(1, { usage_count: 1, success_count: 1 })
        pattern.record_usage(true)
      end

      it "recalculates success rate" do
        pattern.record_usage(true)
        expect(pattern.success_rate).to be_within(0.001).of(0.667)
      end
    end

    context "when unsuccessful" do
      before { @was_successful = false }

      it "only increments usage count" do
        expect(CategorizationPattern).to receive(:update_counters).with(1, { usage_count: 1 })
        pattern.record_usage(false)
      end

      it "recalculates success rate" do
        pattern.record_usage(false)
        expect(pattern.success_rate).to eq(0.5)
      end
    end
  end

  describe "#matches?" do
    context "merchant pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon") }

      it "matches text containing pattern" do
        expect(pattern.matches?("Amazon Prime")).to be true
      end

      it "is case insensitive" do
        expect(pattern.matches?("AMAZON")).to be true
      end

      it "does not match unrelated text" do
        expect(pattern.matches?("Walmart")).to be false
      end

      it "handles nil text" do
        expect(pattern.matches?(nil)).to be false
      end
    end

    context "keyword pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "keyword", pattern_value: "grocery") }

      it "matches description field" do
        expect(pattern.matches?("grocery store")).to be true
      end

      it "matches merchant name field" do
        expect(pattern.matches?("SuperMarket Grocery")).to be true
      end

      it "handles blank text" do
        expect(pattern.matches?("")).to be false
      end
    end

    context "description pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "description", pattern_value: "payment") }

      it "matches description text" do
        expect(pattern.matches?("Monthly payment")).to be true
      end

      it "does not match when description is blank" do
        expect(pattern.matches?("")).to be false
      end
    end

    context "amount_range pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "amount_range", pattern_value: "10.00-50.00") }

      it "matches amounts within range" do
        expect(pattern.matches?(25.00)).to be true
      end

      it "does not match amounts outside range" do
        expect(pattern.matches?(5.00)).to be false
        expect(pattern.matches?(100.00)).to be false
      end

      it "matches boundary values" do
        expect(pattern.matches?(10.00)).to be true
        expect(pattern.matches?(50.00)).to be true
      end
    end

    context "regex pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "regex", pattern_value: "^UBER.*TRIP$") }

      it "matches text matching regex" do
        expect(pattern.matches?("UBER TRIP")).to be true
        expect(pattern.matches?("UBER POOL TRIP")).to be true
      end

      it "does not match non-matching text" do
        expect(pattern.matches?("UBER")).to be false
        expect(pattern.matches?("TRIP")).to be false
      end
    end

    context "time pattern" do
      let(:pattern) { build_categorization_pattern(pattern_type: "time", pattern_value: "morning") }

      it "matches morning times" do
        morning_time = DateTime.parse("2024-01-01 08:00:00")
        expect(pattern.matches?(morning_time)).to be true
      end

      it "does not match non-morning times" do
        afternoon_time = DateTime.parse("2024-01-01 14:00:00")
        expect(pattern.matches?(afternoon_time)).to be false
      end
    end

    context "with expense object" do
      let(:pattern) { build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon") }
      let(:expense) { build_stubbed(:expense) }

      before do
        allow(expense).to receive(:attributes).and_return({ "merchant_name" => "Amazon.com" })
      end

      it "extracts text from expense object" do
        expect(pattern.matches?(expense)).to be true
      end

      it "handles expense with keyword pattern" do
        keyword_pattern = build_categorization_pattern(pattern_type: "keyword", pattern_value: "grocery")
        allow(expense).to receive(:attributes).and_return({
          "description" => "grocery shopping",
          "merchant_name" => "Store"
        })
        expect(keyword_pattern.matches?(expense)).to be true
      end

      it "handles expense with description pattern" do
        desc_pattern = build_categorization_pattern(pattern_type: "description", pattern_value: "subscription")
        allow(expense).to receive(:attributes).and_return({
          "description" => "Monthly subscription fee",
          "merchant_name" => "Netflix"
        })
        expect(desc_pattern.matches?(expense)).to be true
      end

      it "handles expense with regex pattern" do
        regex_pattern = build_categorization_pattern(pattern_type: "regex", pattern_value: "^UBER.*")
        allow(expense).to receive(:attributes).and_return({
          "description" => "UBER TRIP",
          "merchant_name" => "Uber"
        })
        expect(regex_pattern.matches?(expense)).to be true
      end

      it "handles expense with amount_range pattern" do
        amount_pattern = build_categorization_pattern(pattern_type: "amount_range", pattern_value: "10.00-50.00")
        allow(expense).to receive(:amount).and_return(25.0)
        expect(amount_pattern.matches?(expense)).to be true
      end

      it "handles expense with time pattern" do
        time_pattern = build_categorization_pattern(pattern_type: "time", pattern_value: "morning")
        allow(expense).to receive(:transaction_date).and_return(DateTime.parse("2024-01-01 08:00:00"))
        expect(time_pattern.matches?(expense)).to be true
      end

      it "falls back to read_attribute when attributes fail" do
        allow(expense).to receive(:attributes).and_raise(StandardError)
        allow(expense).to receive(:read_attribute).with(:merchant_name).and_return("Amazon.com")
        expect(pattern.matches?(expense)).to be true
      end

      it "falls back to method when both attributes and read_attribute fail" do
        allow(expense).to receive(:attributes).and_raise(StandardError)
        allow(expense).to receive(:read_attribute).and_raise(StandardError)
        allow(expense).to receive(:merchant_name).and_return("Amazon.com")
        expect(pattern.matches?(expense)).to be true
      end
    end

    context "with hash input" do
      it "handles hash with expense key" do
        pattern = build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon")
        expense = build_stubbed(:expense)
        allow(expense).to receive(:attributes).and_return({ "merchant_name" => "Amazon.com" })
        
        expect(pattern.matches?(expense: expense)).to be true
      end

      it "handles hash with merchant_name" do
        pattern = build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon")
        expect(pattern.matches?(merchant_name: "Amazon Prime")).to be true
      end

      it "handles hash with description" do
        pattern = build_categorization_pattern(pattern_type: "description", pattern_value: "payment")
        expect(pattern.matches?(description: "Monthly payment")).to be true
      end
    end

    context "with duck-typed object" do
      let(:pattern) { build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon") }
      let(:duck_typed_object) { double("object") }

      it "uses merchant_name method when available" do
        allow(duck_typed_object).to receive(:respond_to?).and_return(false)
        allow(duck_typed_object).to receive(:respond_to?).with(:merchant_name).and_return(true)
        allow(duck_typed_object).to receive(:respond_to?).with(:description).and_return(false)
        allow(duck_typed_object).to receive(:merchant_name).and_return("Amazon.com")
        
        expect(pattern.matches?(duck_typed_object)).to be true
      end

      it "uses description method when available" do
        desc_pattern = build_categorization_pattern(pattern_type: "keyword", pattern_value: "grocery")
        allow(duck_typed_object).to receive(:respond_to?).and_return(false)
        allow(duck_typed_object).to receive(:respond_to?).with(:description).and_return(true)
        allow(duck_typed_object).to receive(:description).and_return("grocery store")
        allow(duck_typed_object).to receive(:description?).and_return(true)
        
        expect(desc_pattern.matches?(duck_typed_object)).to be true
      end
    end

    context "unsupported pattern type" do
      let(:pattern) { build_categorization_pattern(pattern_type: "merchant", pattern_value: "amazon") }

      before do
        allow(pattern).to receive(:pattern_type).and_return("unsupported_type")
      end

      it "returns false for unsupported pattern types" do
        expect(pattern.matches?("any text")).to be false
      end
    end
  end

  describe "#effective_confidence" do
    context "with no usage data" do
      let(:pattern) { build_categorization_pattern(usage_count: 0, confidence_weight: 2.0) }

      it "reduces confidence for patterns with no data" do
        confidence = pattern.effective_confidence
        expect(confidence).to be < 2.0
        expect(confidence).to be >= 0.3
      end
    end

    context "with sufficient usage data" do
      let(:pattern) do
        build_categorization_pattern(
          usage_count: 10,
          success_count: 8,
          success_rate: 0.8,
          confidence_weight: 2.0
        )
      end

      it "adjusts confidence based on success rate" do
        confidence = pattern.effective_confidence
        expect(confidence).to be > 0.5
        expect(confidence).to be <= 1.0
      end
    end

    context "with edge cases" do
      it "handles NaN values" do
        pattern = build_categorization_pattern(confidence_weight: Float::NAN)
        expect(pattern.effective_confidence).to be >= 0.3
      end

      it "handles infinite values" do
        pattern = build_categorization_pattern(confidence_weight: Float::INFINITY)
        expect(pattern.effective_confidence).to be >= 0.3
      end

      it "ensures minimum confidence of 0.3" do
        pattern = build_categorization_pattern(confidence_weight: 0.1, success_rate: 0.1)
        expect(pattern.effective_confidence).to be >= 0.3
      end
    end
  end

  describe "#check_and_deactivate_if_poor_performance" do
    let(:pattern) { build_categorization_pattern(active: true) }

    before do
      allow(pattern).to receive(:update!)
    end

    context "with poor performance" do
      before do
        pattern.usage_count = 25
        pattern.success_rate = 0.2
        pattern.user_created = false
      end

      it "deactivates the pattern" do
        expect(pattern).to receive(:update!).with(active: false)
        pattern.check_and_deactivate_if_poor_performance
      end
    end

    context "with good performance" do
      before do
        pattern.usage_count = 25
        pattern.success_rate = 0.8
      end

      it "does not deactivate" do
        expect(pattern).not_to receive(:update!)
        pattern.check_and_deactivate_if_poor_performance
      end
    end

    context "with insufficient data" do
      before do
        pattern.usage_count = 15
        pattern.success_rate = 0.2
      end

      it "does not deactivate" do
        expect(pattern).not_to receive(:update!)
        pattern.check_and_deactivate_if_poor_performance
      end
    end

    context "when user created" do
      before do
        pattern.usage_count = 25
        pattern.success_rate = 0.2
        pattern.user_created = true
      end

      it "does not deactivate user patterns" do
        expect(pattern).not_to receive(:update!)
        pattern.check_and_deactivate_if_poor_performance
      end
    end
  end

  describe "private methods" do
    describe "#matches_text_pattern?" do
      let(:pattern) { build_categorization_pattern(pattern_value: "test") }

      it "handles text matching and edge cases" do
        text_tests = [
          ["Test String", true],
          ["testing", true], 
          ["other", false],
          [nil, false],
          [123, false]
        ]

        text_tests.each do |input, expected|
          expect(pattern.send(:matches_text_pattern?, input)).to be expected
        end
      end
    end

    describe "#matches_regex_pattern?" do
      let(:pattern) { build_categorization_pattern(pattern_value: "^test.*") }

      it "handles regex matching and edge cases" do
        regex_tests = [
          ["test string", true],
          ["other", false],
          [nil, false],
          [123, false]
        ]

        regex_tests.each do |input, expected|
          expect(pattern.send(:matches_regex_pattern?, input)).to be expected
        end
      end

      it "handles invalid regex gracefully" do
        allow(pattern).to receive(:pattern_value).and_return("[invalid")
        expect(pattern.send(:matches_regex_pattern?, "test")).to be false
      end
    end

    describe "#matches_amount_range?" do
      it "handles amount range matching with various inputs" do
        amount_tests = [
          # [pattern_value, input, expected]
          ["10.00-50.00", 25.0, true],
          ["10.00-50.00", 10.0, true], 
          ["10.00-50.00", 50.0, true],
          ["10.00-50.00", 5.0, false],
          ["10.00-50.00", 60.0, false],
          ["10.00-50.00", "25.0", true],
          ["10.00-50.00", "5.0", false],
          ["-100--50", -75.0, true],
          ["-100--50", -25.0, false],
          ["invalid", 25.0, false],
          ["10.00-50.00", "not_a_number", false]
        ]

        amount_tests.each do |pattern_value, input, expected|
          pattern = build_categorization_pattern(pattern_value: pattern_value)
          expect(pattern.send(:matches_amount_range?, input)).to be expected
        end
      end
    end

    describe "#matches_time_pattern?" do
      let(:pattern) { build_categorization_pattern(pattern_value: "morning") }

      it "handles blank input" do
        expect(pattern.send(:matches_time_pattern?, nil)).to be false
        expect(pattern.send(:matches_time_pattern?, "")).to be false
      end

      it "matches time keywords correctly" do
        morning_time = DateTime.parse("2024-01-01 08:00:00")
        expect(pattern.send(:matches_time_pattern?, morning_time)).to be true

        afternoon_pattern = build_categorization_pattern(pattern_value: "afternoon")
        afternoon_time = DateTime.parse("2024-01-01 14:00:00")
        expect(afternoon_pattern.send(:matches_time_pattern?, afternoon_time)).to be true

        evening_pattern = build_categorization_pattern(pattern_value: "evening")
        evening_time = DateTime.parse("2024-01-01 19:00:00")
        expect(evening_pattern.send(:matches_time_pattern?, evening_time)).to be true

        night_pattern = build_categorization_pattern(pattern_value: "night")
        night_time = DateTime.parse("2024-01-01 23:00:00")
        expect(night_pattern.send(:matches_time_pattern?, night_time)).to be true
      end

      it "handles weekend and weekday patterns" do
        weekend_pattern = build_categorization_pattern(pattern_value: "weekend")
        saturday = DateTime.parse("2024-01-06 12:00:00") # Saturday
        sunday = DateTime.parse("2024-01-07 12:00:00") # Sunday
        monday = DateTime.parse("2024-01-01 12:00:00") # Monday

        expect(weekend_pattern.send(:matches_time_pattern?, saturday)).to be true
        expect(weekend_pattern.send(:matches_time_pattern?, sunday)).to be true
        expect(weekend_pattern.send(:matches_time_pattern?, monday)).to be false

        weekday_pattern = build_categorization_pattern(pattern_value: "weekday")
        expect(weekday_pattern.send(:matches_time_pattern?, monday)).to be true
        expect(weekday_pattern.send(:matches_time_pattern?, saturday)).to be false
      end

      it "returns false when parse_datetime fails" do
        expect(pattern.send(:matches_time_pattern?, "invalid_date")).to be false
      end
    end

    describe "#matches_time_range?" do
      let(:pattern) { build_categorization_pattern(pattern_value: "09:00-17:00") }

      it "matches times within range" do
        datetime = DateTime.parse("2024-01-01 12:00:00")
        expect(pattern.send(:matches_time_range?, datetime)).to be true
      end

      it "handles time ranges crossing midnight" do
        pattern = build_categorization_pattern(pattern_value: "22:00-06:00")
        late_night = DateTime.parse("2024-01-01 23:00:00")
        early_morning = DateTime.parse("2024-01-01 05:00:00")
        midday = DateTime.parse("2024-01-01 12:00:00")

        expect(pattern.send(:matches_time_range?, late_night)).to be true
        expect(pattern.send(:matches_time_range?, early_morning)).to be true
        expect(pattern.send(:matches_time_range?, midday)).to be false
      end

      it "returns false for invalid pattern value" do
        pattern = build_categorization_pattern(pattern_value: "invalid")
        datetime = DateTime.parse("2024-01-01 12:00:00")
        expect(pattern.send(:matches_time_range?, datetime)).to be false
      end

      it "handles parsing errors gracefully" do
        datetime = DateTime.parse("2024-01-01 12:00:00")
        allow(pattern).to receive(:pattern_value).and_return("25:70-30:80") # Invalid hour/minute values
        expect(pattern.send(:matches_time_range?, datetime)).to be false
      end
    end

    describe "#parse_datetime" do
      let(:pattern) { build_categorization_pattern }

      it "handles DateTime objects" do
        dt = DateTime.now
        expect(pattern.send(:parse_datetime, dt)).to eq(dt)
      end

      it "handles Time objects" do
        time = Time.now
        expect(pattern.send(:parse_datetime, time)).to eq(time)
      end

      it "handles Date objects" do
        date = Date.today
        expect(pattern.send(:parse_datetime, date)).to eq(date.to_datetime)
      end

      it "parses string dates" do
        result = pattern.send(:parse_datetime, "2024-01-01 12:00:00")
        expect(result).to be_a(DateTime)
      end

      it "returns nil for invalid input" do
        expect(pattern.send(:parse_datetime, "invalid")).to be_nil
        expect(pattern.send(:parse_datetime, 123)).to be_nil
      end
    end

    describe "#invalidate_cache" do
      let(:pattern) { build_categorization_pattern }

      it "handles cache invalidation errors gracefully" do
        allow(Rails.logger).to receive(:error)
        allow(Rails.cache).to receive(:delete_matched).and_raise(StandardError.new("Cache error"))
        
        expect { pattern.send(:invalidate_cache) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/Cache invalidation failed/)
      end

      it "skips pattern cache when not defined" do
        expect { pattern.send(:invalidate_cache) }.not_to raise_error
      end

      it "skips Rails cache operations when delete_matched not available" do
        cache_double = double("cache")
        allow(Rails).to receive(:cache).and_return(cache_double)
        allow(cache_double).to receive(:respond_to?).with(:delete_matched).and_return(false)
        
        expect { pattern.send(:invalidate_cache) }.not_to raise_error
      end
    end
  end
end