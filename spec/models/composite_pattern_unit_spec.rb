# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositePattern, type: :model, unit: true do
  # Test doubles setup
  let(:category) { build_stubbed(:category, id: 1, name: "Transportation") }
  let(:pattern1) { build_stubbed(:categorization_pattern, id: 1, category: category, pattern_type: "merchant", pattern_value: "Uber") }
  let(:pattern2) { build_stubbed(:categorization_pattern, id: 2, category: category, pattern_type: "merchant", pattern_value: "Lyft") }
  let(:pattern3) { build_stubbed(:categorization_pattern, id: 3, category: category, pattern_type: "amount", pattern_value: "> 50") }
  let(:expense) { build_stubbed(:expense, merchant_name: "Uber", amount: 25.00, transaction_date: Time.current) }

  let(:composite_pattern) do
    build_stubbed(:composite_pattern,
                  category: category,
                  name: "Ride Share",
                  operator: "OR",
                  pattern_ids: [pattern1.id, pattern2.id],
                  confidence_weight: 1.5,
                  usage_count: 10,
                  success_count: 8,
                  success_rate: 0.8,
                  active: true)
  end

  describe "constants" do
    it "defines correct operators" do
      expect(described_class::OPERATORS).to eq(%w[AND OR NOT])
    end

    it "defines confidence weight constants" do
      expect(described_class::DEFAULT_CONFIDENCE_WEIGHT).to eq(1.5)
      expect(described_class::MIN_CONFIDENCE_WEIGHT).to eq(0.1)
      expect(described_class::MAX_CONFIDENCE_WEIGHT).to eq(5.0)
    end
  end

  describe "validations" do
    subject { build(:composite_pattern, category: category) }







    describe "custom validations" do
      describe "#success_count_not_greater_than_usage_count" do
        it "is invalid when success_count > usage_count" do
          pattern = build(:composite_pattern, usage_count: 5, success_count: 10)
          expect(pattern).not_to be_valid
          expect(pattern.errors[:success_count]).to include("cannot be greater than usage count")
        end

        it "is valid when success_count <= usage_count" do
          pattern = build(:composite_pattern, usage_count: 10, success_count: 8)
          expect(pattern).to be_valid
        end
      end

      describe "#pattern_ids_exist" do
        before do
          allow(CategorizationPattern).to receive(:where).and_return(
            instance_double(ActiveRecord::Relation,
                            pluck: [pattern1.id],
                            any?: true,
                            "where.not" => instance_double(ActiveRecord::Relation, pluck: []))
          )
        end


      end

      describe "#validate_conditions_format" do
        it "allows blank conditions" do
          pattern = build(:composite_pattern, conditions: nil)
          expect(pattern).to be_valid
        end

        it "validates invalid keys in conditions" do
          pattern = build(:composite_pattern, conditions: { "invalid_key" => "value" })
          expect(pattern).not_to be_valid
          expect(pattern.errors[:conditions]).to include("contains invalid keys: invalid_key")
        end

        it "validates amount conditions" do
          pattern = build(:composite_pattern, conditions: { "min_amount" => -10 })
          expect(pattern).not_to be_valid
          expect(pattern.errors[:conditions]).to include("min_amount must be a positive number")
        end

        it "validates min_amount < max_amount" do
          pattern = build(:composite_pattern, conditions: { "min_amount" => 100, "max_amount" => 50 })
          expect(pattern).not_to be_valid
          expect(pattern.errors[:conditions]).to include("min_amount must be less than max_amount")
        end

        it "validates days_of_week format" do
          pattern = build(:composite_pattern, conditions: { "days_of_week" => ["invalid_day"] })
          expect(pattern).not_to be_valid
          expect(pattern.errors[:conditions]).to include("days_of_week must be an array of valid day names")
        end


        it "accepts valid conditions" do
          pattern = build(:composite_pattern, conditions: {
            "min_amount" => 10,
            "max_amount" => 100,
            "days_of_week" => ["monday", "friday"],
            "time_ranges" => [{ "start" => "09:00", "end" => "17:00" }],
            "merchant_blacklist" => ["BadMerchant"]
          })
          expect(pattern).to be_valid
        end
      end
    end
  end

  describe "scopes" do
    let(:active_pattern) { build_stubbed(:composite_pattern, active: true) }
    let(:inactive_pattern) { build_stubbed(:composite_pattern, active: false) }
    let(:user_pattern) { build_stubbed(:composite_pattern, user_created: true) }
    let(:system_pattern) { build_stubbed(:composite_pattern, user_created: false) }
    let(:successful_pattern) { build_stubbed(:composite_pattern, success_rate: 0.8) }
    let(:unsuccessful_pattern) { build_stubbed(:composite_pattern, success_rate: 0.3) }
    let(:frequent_pattern) { build_stubbed(:composite_pattern, usage_count: 20) }
    let(:infrequent_pattern) { build_stubbed(:composite_pattern, usage_count: 5) }

    before do
      allow(described_class).to receive(:where).and_call_original
      allow(described_class).to receive(:order).and_call_original
    end








  end

  describe "#component_patterns" do
    context "with pattern_ids" do
      before do
        allow(CategorizationPattern).to receive(:where).with(id: [pattern1.id, pattern2.id])
          .and_return([pattern1, pattern2])
      end

      it "returns the component patterns" do
        expect(composite_pattern.component_patterns).to eq([pattern1, pattern2])
      end
    end

    context "with blank pattern_ids" do
      it "returns empty array" do
        composite_pattern.pattern_ids = []
        expect(composite_pattern.component_patterns).to eq([])
      end
    end
  end

  describe "#matches?" do
    before do
      allow(composite_pattern).to receive(:component_patterns).and_return([pattern1, pattern2])
      allow(composite_pattern).to receive(:conditions_match?).and_return(true)
      allow(pattern1).to receive(:matches?).with(expense).and_return(true)
      allow(pattern2).to receive(:matches?).with(expense).and_return(false)
    end

    context "when inactive" do
      it "returns false" do
        composite_pattern.active = false
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "when no component patterns" do
      it "returns false" do
        allow(composite_pattern).to receive(:component_patterns).and_return([])
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "when conditions don't match" do
      it "returns false" do
        allow(composite_pattern).to receive(:conditions_match?).and_return(false)
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "with AND operator" do
      before { composite_pattern.operator = "AND" }

      it "returns true when all patterns match" do
        allow(pattern2).to receive(:matches?).with(expense).and_return(true)
        expect(composite_pattern.matches?(expense)).to be true
      end

      it "returns false when not all patterns match" do
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "with OR operator" do
      before { composite_pattern.operator = "OR" }

      it "returns true when any pattern matches" do
        expect(composite_pattern.matches?(expense)).to be true
      end

      it "returns false when no patterns match" do
        allow(pattern1).to receive(:matches?).with(expense).and_return(false)
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "with NOT operator" do
      before { composite_pattern.operator = "NOT" }

      it "returns true when no patterns match" do
        allow(pattern1).to receive(:matches?).with(expense).and_return(false)
        expect(composite_pattern.matches?(expense)).to be true
      end

      it "returns false when any pattern matches" do
        expect(composite_pattern.matches?(expense)).to be false
      end
    end

    context "with invalid operator" do
      it "returns false" do
        composite_pattern.operator = "INVALID"
        expect(composite_pattern.matches?(expense)).to be false
      end
    end
  end

  describe "#record_usage" do
    it "increments usage_count" do
      allow(composite_pattern).to receive(:save!)
      expect { composite_pattern.record_usage(true) }
        .to change { composite_pattern.usage_count }.by(1)
    end

    it "increments success_count when successful" do
      allow(composite_pattern).to receive(:save!)
      expect { composite_pattern.record_usage(true) }
        .to change { composite_pattern.success_count }.by(1)
    end

    it "does not increment success_count when unsuccessful" do
      allow(composite_pattern).to receive(:save!)
      expect { composite_pattern.record_usage(false) }
        .not_to change { composite_pattern.success_count }
    end

    it "recalculates success_rate" do
      allow(composite_pattern).to receive(:save!)
      composite_pattern.usage_count = 10
      composite_pattern.success_count = 5
      composite_pattern.record_usage(true)
      expect(composite_pattern.success_rate).to be_within(0.01).of(0.545)
    end

    it "saves the record" do
      expect(composite_pattern).to receive(:save!)
      composite_pattern.record_usage(true)
    end
  end

  describe "#effective_confidence" do
    before do
      allow(composite_pattern).to receive(:component_patterns).and_return([pattern1, pattern2])
      allow(pattern1).to receive(:effective_confidence).and_return(0.8)
      allow(pattern2).to receive(:effective_confidence).and_return(0.6)
    end

    context "with component patterns" do
      it "calculates weighted confidence" do
        composite_pattern.confidence_weight = 2.0
        composite_pattern.usage_count = 10
        composite_pattern.success_rate = 0.8
        
        # Base: 2.0
        # Avg component: 0.7
        # Adjusted: 2.0 * (0.7 + 0.7 * 0.3) = 2.0 * 0.91 = 1.82
        # With success rate: 1.82 * (0.5 + 0.8 * 0.5) = 1.82 * 0.9 = 1.638
        expect(composite_pattern.effective_confidence).to be_within(0.01).of(1.638)
      end

      it "applies lower confidence for patterns with little data" do
        composite_pattern.usage_count = 3
        composite_pattern.confidence_weight = 1.5
        
        # Base: 1.5
        # Avg component: 0.7
        # Adjusted: 1.5 * (0.7 + 0.7 * 0.3) = 1.5 * 0.91 = 1.365
        # Little data penalty: 1.365 * 0.8 = 1.092
        expect(composite_pattern.effective_confidence).to be_within(0.01).of(1.092)
      end
    end

    context "without component patterns" do
      it "returns 0.0" do
        allow(composite_pattern).to receive(:component_patterns).and_return([])
        expect(composite_pattern.effective_confidence).to eq(0.0)
      end
    end
  end

  describe "#check_and_deactivate_if_poor_performance" do
    it "deactivates when performance is poor with enough data" do
      composite_pattern.usage_count = 25
      composite_pattern.success_rate = 0.2
      expect(composite_pattern).to receive(:update!).with(active: false)
      composite_pattern.check_and_deactivate_if_poor_performance
    end

    it "does not deactivate with insufficient data" do
      composite_pattern.usage_count = 15
      composite_pattern.success_rate = 0.2
      expect(composite_pattern).not_to receive(:update!)
      composite_pattern.check_and_deactivate_if_poor_performance
    end

    it "does not deactivate with good performance" do
      composite_pattern.usage_count = 25
      composite_pattern.success_rate = 0.5
      expect(composite_pattern).not_to receive(:update!)
      composite_pattern.check_and_deactivate_if_poor_performance
    end
  end

  describe "#add_pattern" do
    context "with CategorizationPattern object" do
      it "adds pattern ID to pattern_ids" do
        composite_pattern.pattern_ids = [pattern1.id]
        expect(composite_pattern).to receive(:update!).with(pattern_ids: [pattern1.id, pattern2.id])
        composite_pattern.add_pattern(pattern2)
      end
    end

    context "with pattern ID" do
      it "adds pattern ID to pattern_ids" do
        composite_pattern.pattern_ids = [pattern1.id]
        expect(composite_pattern).to receive(:update!).with(pattern_ids: [pattern1.id, 3])
        composite_pattern.add_pattern(3)
      end
    end

    context "when pattern already exists" do
      it "does not duplicate pattern ID" do
        composite_pattern.pattern_ids = [pattern1.id, pattern2.id]
        expect(composite_pattern).not_to receive(:update!)
        composite_pattern.add_pattern(pattern1)
      end
    end
  end

  describe "#remove_pattern" do
    context "with CategorizationPattern object" do
      it "removes pattern ID from pattern_ids" do
        composite_pattern.pattern_ids = [pattern1.id, pattern2.id]
        expect(composite_pattern).to receive(:update!).with(pattern_ids: [pattern2.id])
        composite_pattern.remove_pattern(pattern1)
      end
    end

    context "with pattern ID" do
      it "removes pattern ID from pattern_ids" do
        composite_pattern.pattern_ids = [1, 2, 3]
        expect(composite_pattern).to receive(:update!).with(pattern_ids: [1, 3])
        composite_pattern.remove_pattern(2)
      end
    end

    context "when pattern doesn't exist" do
      it "does not update pattern_ids" do
        composite_pattern.pattern_ids = [pattern1.id]
        expect(composite_pattern).not_to receive(:update!)
        composite_pattern.remove_pattern(pattern2)
      end
    end
  end

  describe "#description" do
    before do
      allow(composite_pattern).to receive(:component_patterns).and_return([pattern1, pattern2])
    end

    context "with AND operator" do
      it "returns patterns joined with AND" do
        composite_pattern.operator = "AND"
        expect(composite_pattern.description).to eq("merchant:Uber AND merchant:Lyft")
      end
    end

    context "with OR operator" do
      it "returns patterns joined with OR" do
        composite_pattern.operator = "OR"
        expect(composite_pattern.description).to eq("merchant:Uber OR merchant:Lyft")
      end
    end

    context "with NOT operator" do
      it "returns patterns wrapped in NOT" do
        composite_pattern.operator = "NOT"
        expect(composite_pattern.description).to eq("NOT (merchant:Uber OR merchant:Lyft)")
      end
    end

    context "with invalid operator" do
      it "returns the name" do
        composite_pattern.operator = "INVALID"
        expect(composite_pattern.description).to eq("Ride Share")
      end
    end
  end

  describe "callbacks" do
    describe "before_save :calculate_success_rate" do
      it "calculates success rate before saving" do
        pattern = build(:composite_pattern, usage_count: 20, success_count: 15)
        pattern.run_callbacks(:save) { true }
        expect(pattern.success_rate).to eq(0.75)
      end

      it "sets success rate to 0 when usage_count is 0" do
        pattern = build(:composite_pattern, usage_count: 0, success_count: 0)
        pattern.run_callbacks(:save) { true }
        expect(pattern.success_rate).to eq(0.0)
      end
    end

    describe "after_commit :invalidate_cache" do
      it "invalidates cache after commit" do
        cache_instance = instance_double("Categorization::PatternCache")
        stub_const("Categorization::PatternCache", class_double("Categorization::PatternCache", instance: cache_instance))
        
        expect(cache_instance).to receive(:invalidate).with(composite_pattern)
        composite_pattern.run_callbacks(:commit) { true }
      end

      it "logs error if cache invalidation fails" do
        cache_instance = instance_double("Categorization::PatternCache")
        stub_const("Categorization::PatternCache", class_double("Categorization::PatternCache", instance: cache_instance))
        
        allow(cache_instance).to receive(:invalidate).and_raise(StandardError, "Cache error")
        expect(Rails.logger).to receive(:error).with(/Cache invalidation failed: Cache error/)
        
        composite_pattern.run_callbacks(:commit) { true }
      end
    end
  end

  describe "private methods" do
    describe "#conditions_match?" do
      let(:test_expense) do
        build_stubbed(:expense,
                      amount: 50.0,
                      merchant_name: "Test Merchant",
                      transaction_date: Time.parse("2024-01-15 14:30:00"))
      end

      context "with no conditions" do
        it "returns true" do
          composite_pattern.conditions = nil
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be true
        end
      end

      context "with amount conditions" do
        it "returns false when below min_amount" do
          composite_pattern.conditions = { "min_amount" => 100 }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end

        it "returns false when above max_amount" do
          composite_pattern.conditions = { "max_amount" => 25 }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end

        it "returns true when within range" do
          composite_pattern.conditions = { "min_amount" => 25, "max_amount" => 75 }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be true
        end
      end

      context "with day of week conditions" do
        it "returns true when day matches" do
          composite_pattern.conditions = { "days_of_week" => ["monday"] }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be true
        end

        it "returns false when day doesn't match" do
          composite_pattern.conditions = { "days_of_week" => ["sunday"] }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end
      end

      context "with time range conditions" do

        it "returns false when time is outside range" do
          composite_pattern.conditions = {
            "time_ranges" => [{ "start" => "09:00", "end" => "12:00" }]
          }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end

      end

      context "with merchant blacklist" do
        it "returns false when merchant is blacklisted" do
          composite_pattern.conditions = { "merchant_blacklist" => ["Test Merchant"] }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end

        it "returns true when merchant is not blacklisted" do
          composite_pattern.conditions = { "merchant_blacklist" => ["Other Merchant"] }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be true
        end

        it "handles case-insensitive matching" do
          composite_pattern.conditions = { "merchant_blacklist" => ["test merchant"] }
          expect(composite_pattern.send(:conditions_match?, test_expense)).to be false
        end
      end
    end

    describe "#time_in_range?" do
      it "returns true when time is in range" do
        result = composite_pattern.send(:time_in_range?, "14:30", "14:00", "15:00")
        expect(result).to be true
      end

      it "returns false when time is outside range" do
        result = composite_pattern.send(:time_in_range?, "16:00", "14:00", "15:00")
        expect(result).to be false
      end

      it "handles ranges crossing midnight" do
        result = composite_pattern.send(:time_in_range?, "23:30", "22:00", "02:00")
        expect(result).to be true
      end

      it "returns false for invalid time format" do
        result = composite_pattern.send(:time_in_range?, "invalid", "14:00", "15:00")
        expect(result).to be false
      end
    end
  end

  describe "error handling" do
    it "handles missing component patterns gracefully" do
      allow(CategorizationPattern).to receive(:where).and_return([])
      expect { composite_pattern.component_patterns }.not_to raise_error
    end

    it "handles nil expense in matches?" do
      expect { composite_pattern.matches?(nil) }.not_to raise_error
    end

    it "handles invalid pattern IDs gracefully" do
      composite_pattern.pattern_ids = nil
      expect(composite_pattern.component_patterns).to eq([])
    end
  end

  describe "performance considerations" do

    it "short-circuits matching when inactive" do
      composite_pattern.active = false
      expect(composite_pattern).not_to receive(:component_patterns)
      composite_pattern.matches?(expense)
    end

  end
end