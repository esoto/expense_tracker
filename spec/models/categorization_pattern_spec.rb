# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationPattern, type: :model do
  let(:category) { Category.create!(name: "Food & Dining") }
  
  describe "associations" do
    it { should belong_to(:category) }
    it { should have_many(:pattern_feedbacks).dependent(:destroy) }
    it { should have_many(:expenses).through(:pattern_feedbacks) }
  end

  describe "validations" do
    subject { described_class.new(category: category, pattern_type: "merchant", pattern_value: "test") }
    
    it { should validate_presence_of(:pattern_type) }
    it { should validate_presence_of(:pattern_value) }
    it { should validate_inclusion_of(:pattern_type).in_array(%w[merchant keyword description amount_range regex time]) }
    
    it { should validate_numericality_of(:confidence_weight).is_greater_than_or_equal_to(0.1).is_less_than_or_equal_to(5.0) }
    it { should validate_numericality_of(:usage_count).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:success_count).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:success_rate).is_greater_than_or_equal_to(0.0).is_less_than_or_equal_to(1.0) }
    
    context "pattern value format validations" do
      it "validates amount_range format" do
        pattern = described_class.new(category: category, pattern_type: "amount_range", pattern_value: "invalid")
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be in format 'min-max' (e.g., '10.00-50.00' or '-100--50')")
        
        pattern.pattern_value = "10.00-50.00"
        expect(pattern).to be_valid
      end
      
      it "validates amount_range min < max" do
        pattern = described_class.new(category: category, pattern_type: "amount_range", pattern_value: "50-10")
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("minimum must be less than maximum")
      end
      
      it "validates regex format" do
        pattern = described_class.new(category: category, pattern_type: "regex", pattern_value: "[invalid")
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be a valid regular expression")
        
        pattern.pattern_value = "^test.*"
        expect(pattern).to be_valid
      end
      
      it "validates time format" do
        pattern = described_class.new(category: category, pattern_type: "time", pattern_value: "invalid")
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("must be a valid time pattern")
        
        %w[morning afternoon evening night weekend weekday].each do |valid_time|
          pattern.pattern_value = valid_time
          expect(pattern).to be_valid
        end
        
        pattern.pattern_value = "09:00-17:00"
        expect(pattern).to be_valid
      end
    end
    
    it "validates success_count <= usage_count" do
      pattern = described_class.new(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        usage_count: 5,
        success_count: 10
      )
      expect(pattern).not_to be_valid
      expect(pattern.errors[:success_count]).to include("cannot be greater than usage count")
    end
    
    it "validates pattern uniqueness within category and type" do
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "unique_test"
      )
      
      duplicate = described_class.new(
        category: category,
        pattern_type: "merchant",
        pattern_value: "unique_test"
      )
      
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:pattern_value]).to include("already exists for this category and pattern type")
    end
    
    it "allows same pattern value for different categories" do
      other_category = Category.create!(name: "Entertainment")
      
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "same_value"
      )
      
      different_category_pattern = described_class.new(
        category: other_category,
        pattern_type: "merchant",
        pattern_value: "same_value"
      )
      
      expect(different_category_pattern).to be_valid
    end
    
    it "allows same pattern value for different types" do
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "same_value"
      )
      
      different_type_pattern = described_class.new(
        category: category,
        pattern_type: "keyword",
        pattern_value: "same_value"
      )
      
      expect(different_type_pattern).to be_valid
    end
  end

  describe "scopes" do
    let!(:active_pattern) { described_class.create!(category: category, pattern_type: "merchant", pattern_value: "active", active: true) }
    let!(:inactive_pattern) { described_class.create!(category: category, pattern_type: "merchant", pattern_value: "inactive", active: false) }
    let!(:user_pattern) { described_class.create!(category: category, pattern_type: "merchant", pattern_value: "user", user_created: true) }
    let!(:successful_pattern) do
      pattern = described_class.create!(category: category, pattern_type: "merchant", pattern_value: "success")
      pattern.update_columns(success_rate: 0.8) # Use update_columns to bypass callbacks
      pattern
    end
    
    it "filters active patterns" do
      expect(described_class.active).to include(active_pattern, user_pattern, successful_pattern)
      expect(described_class.active).not_to include(inactive_pattern)
    end
    
    it "filters user created patterns" do
      expect(described_class.user_created).to include(user_pattern)
      expect(described_class.user_created).not_to include(active_pattern)
    end
    
    it "filters successful patterns" do
      expect(described_class.successful).to include(successful_pattern)
      expect(described_class.successful).not_to include(active_pattern)
    end
  end

  describe "callbacks" do
    it "calculates success rate before save" do
      pattern = described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        usage_count: 10,
        success_count: 7
      )
      
      expect(pattern.success_rate).to eq(0.7)
    end
  end

  describe "#matches?" do
    let(:pattern) { described_class.new(category: category) }
    let(:email_account) { EmailAccount.create!(email: "test@example.com", provider: "gmail", bank_name: "Test Bank") }
    let(:expense) do
      Expense.new(
        email_account: email_account,
        merchant_name: "Test Merchant",
        description: "Test Description",
        amount: 25.00,
        transaction_date: DateTime.now,
        category: category
      )
    end
    
    context "with merchant/keyword/description pattern" do
      before do
        pattern.pattern_type = "merchant"
        pattern.pattern_value = "starbucks"
      end
      
      it "matches case-insensitively" do
        expect(pattern.matches?("STARBUCKS")).to be true
        expect(pattern.matches?("Starbucks Coffee")).to be true
      end
      
      it "does not match different text" do
        expect(pattern.matches?("McDonald's")).to be false
      end
      
      it "returns false for blank text" do
        expect(pattern.matches?("")).to be false
        expect(pattern.matches?(nil)).to be false
      end
      
      it "matches expense object with merchant name" do
        expense.merchant_name = "Starbucks Coffee"
        expect(pattern.matches?(expense)).to be true
      end
      
      it "matches hash with merchant_name key" do
        expect(pattern.matches?(merchant_name: "Starbucks")).to be true
        expect(pattern.matches?(merchant_name: "McDonald's")).to be false
      end
      
      it "uses description when pattern type is description" do
        pattern.pattern_type = "description"
        pattern.pattern_value = "coffee"
        expense.description = "Morning coffee"
        expect(pattern.matches?(expense)).to be true
      end
    end
    
    context "with regex pattern" do
      before do
        pattern.pattern_type = "regex"
        pattern.pattern_value = "uber|lyft"
      end
      
      it "matches regex pattern" do
        expect(pattern.matches?("UBER TRIP")).to be true
        expect(pattern.matches?("Lyft ride")).to be true
        expect(pattern.matches?("taxi")).to be false
      end
    end
    
    context "with amount_range pattern" do
      before do
        pattern.pattern_type = "amount_range"
        pattern.pattern_value = "10.00-50.00"
      end
      
      it "matches amounts in range" do
        expect(pattern.matches?(25.00)).to be true
        expect(pattern.matches?(10.00)).to be true
        expect(pattern.matches?(50.00)).to be true
      end
      
      it "does not match amounts outside range" do
        expect(pattern.matches?(9.99)).to be false
        expect(pattern.matches?(50.01)).to be false
      end
    end
    
    context "with time pattern" do
      before do
        pattern.pattern_type = "time"
      end
      
      it "matches morning times" do
        pattern.pattern_value = "morning"
        morning_time = DateTime.new(2024, 1, 1, 9, 0, 0)
        expect(pattern.matches?(morning_time)).to be true
        
        evening_time = DateTime.new(2024, 1, 1, 18, 0, 0)
        expect(pattern.matches?(evening_time)).to be false
      end
      
      it "matches weekend days" do
        pattern.pattern_value = "weekend"
        saturday = DateTime.new(2024, 1, 6, 12, 0, 0) # Saturday
        expect(pattern.matches?(saturday)).to be true
        
        monday = DateTime.new(2024, 1, 8, 12, 0, 0) # Monday
        expect(pattern.matches?(monday)).to be false
      end
      
      it "matches time ranges" do
        pattern.pattern_value = "09:00-17:00"
        work_hours = DateTime.new(2024, 1, 1, 14, 0, 0)
        expect(pattern.matches?(work_hours)).to be true
        
        after_hours = DateTime.new(2024, 1, 1, 20, 0, 0)
        expect(pattern.matches?(after_hours)).to be false
      end
    end
  end

  describe "#record_usage" do
    let(:pattern) do
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        usage_count: 5,
        success_count: 3
      )
    end
    
    it "increments usage count" do
      expect { pattern.record_usage(false) }.to change { pattern.usage_count }.from(5).to(6)
    end
    
    it "increments success count when successful" do
      expect { pattern.record_usage(true) }.to change { pattern.success_count }.from(3).to(4)
    end
    
    it "updates success rate" do
      pattern.record_usage(true)
      expect(pattern.success_rate).to eq(4.0 / 6.0)
    end
  end

  describe "#effective_confidence" do
    let(:pattern) do
      described_class.new(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        confidence_weight: 2.0
      )
    end
    
    it "reduces confidence for patterns with little data" do
      pattern.usage_count = 2
      expect(pattern.effective_confidence).to eq(2.0 * 0.7)
    end
    
    it "adjusts confidence based on success rate with enough data" do
      pattern.usage_count = 10
      pattern.success_rate = 0.8
      
      # (0.5 + (0.8 * 0.5)) = 0.9
      expect(pattern.effective_confidence).to eq(2.0 * 0.9)
    end
  end

  describe "#check_and_deactivate_if_poor_performance" do
    let(:pattern) do
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        active: true
      )
    end
    
    it "deactivates pattern with poor performance" do
      pattern.update!(usage_count: 25, success_rate: 0.2)
      pattern.check_and_deactivate_if_poor_performance
      
      expect(pattern.reload.active).to be false
    end
    
    it "does not deactivate pattern with good performance" do
      pattern.update_columns(usage_count: 25, success_count: 18, success_rate: 0.72)
      pattern.check_and_deactivate_if_poor_performance
      
      expect(pattern.reload.active).to be true
    end
    
    it "does not deactivate pattern with insufficient data" do
      pattern.update!(usage_count: 10, success_rate: 0.2)
      pattern.check_and_deactivate_if_poor_performance
      
      expect(pattern.reload.active).to be true
    end
    
    it "does not deactivate user-created patterns" do
      pattern.update!(usage_count: 25, success_rate: 0.2, user_created: true)
      pattern.check_and_deactivate_if_poor_performance
      
      expect(pattern.reload.active).to be true
    end
  end
  
  describe "metadata handling" do
    it "initializes metadata as empty hash if nil" do
      pattern = described_class.new(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test"
      )
      expect(pattern.metadata).to eq({})
    end
    
    it "preserves existing metadata" do
      pattern = described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test",
        metadata: { custom: "data" }
      )
      expect(pattern.metadata).to eq({ "custom" => "data" })
    end
  end
  
  describe "additional scopes" do
    before do
      # Create patterns with various characteristics
      described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "high_conf",
        confidence_weight: 3.0
      )
      
      described_class.create!(
        category: category,
        pattern_type: "keyword",
        pattern_value: "low_conf",
        confidence_weight: 0.5
      )
      
      frequently_used = described_class.create!(
        category: category,
        pattern_type: "regex",
        pattern_value: "frequent"
      )
      frequently_used.update_columns(usage_count: 15)
    end
    
    it "filters high confidence patterns" do
      high_conf_patterns = described_class.high_confidence
      expect(high_conf_patterns.count).to eq(1)
      expect(high_conf_patterns.first.pattern_value).to eq("high_conf")
    end
    
    it "filters frequently used patterns" do
      frequent_patterns = described_class.frequently_used
      expect(frequent_patterns.count).to eq(1)
      expect(frequent_patterns.first.pattern_value).to eq("frequent")
    end
    
    it "filters by pattern type" do
      merchant_patterns = described_class.by_type("merchant")
      expect(merchant_patterns.map(&:pattern_value)).to include("high_conf")
      expect(merchant_patterns.map(&:pattern_value)).not_to include("low_conf", "frequent")
    end
    
    it "orders by success rate and usage count" do
      p1 = described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "order1"
      )
      p1.update_columns(success_rate: 0.9, usage_count: 10)
      
      p2 = described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "order2"
      )
      p2.update_columns(success_rate: 0.9, usage_count: 20)
      
      p3 = described_class.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "order3"
      )
      p3.update_columns(success_rate: 0.95, usage_count: 5)
      
      ordered = described_class.ordered_by_success
      expect(ordered.first).to eq(p3) # Highest success rate
      expect(ordered.second).to eq(p2) # Same success rate as p1 but more usage
    end
  end
  
  describe "constants" do
    it "defines pattern types" do
      expect(described_class::PATTERN_TYPES).to eq(%w[merchant keyword description amount_range regex time])
    end
    
    it "defines confidence weight constants" do
      expect(described_class::DEFAULT_CONFIDENCE_WEIGHT).to eq(1.0)
      expect(described_class::MIN_CONFIDENCE_WEIGHT).to eq(0.1)
      expect(described_class::MAX_CONFIDENCE_WEIGHT).to eq(5.0)
    end
  end
end