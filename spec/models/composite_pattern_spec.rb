# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositePattern, type: :model, integration: true do
  let(:category) { Category.create!(name: "Transportation") }
  let(:pattern1) { CategorizationPattern.create!(category: category, pattern_type: "merchant", pattern_value: "uber") }
  let(:pattern2) { CategorizationPattern.create!(category: category, pattern_type: "merchant", pattern_value: "lyft") }

  describe "associations", integration: true do
    it { should belong_to(:category) }
  end

  describe "validations", integration: true do
    subject do
      described_class.new(
        category: category,
        name: "Rideshare",
        operator: "OR",
        pattern_ids: [ pattern1.id ]
      )
    end

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:category_id) }
    it { should validate_presence_of(:operator) }
    it { should validate_inclusion_of(:operator).in_array(%w[AND OR NOT]) }
    it { should validate_presence_of(:pattern_ids) }

    it { should validate_numericality_of(:confidence_weight).is_greater_than_or_equal_to(0.1).is_less_than_or_equal_to(5.0) }
    it { should validate_numericality_of(:usage_count).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:success_count).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:success_rate).is_greater_than_or_equal_to(0.0).is_less_than_or_equal_to(1.0) }

    it "validates pattern_ids exist" do
      composite = described_class.new(
        category: category,
        name: "Test",
        operator: "AND",
        pattern_ids: [ 999999 ]
      )
      expect(composite).not_to be_valid
      expect(composite.errors[:pattern_ids]).to include("contains non-existent pattern IDs: 999999")
    end

    it "validates success_count <= usage_count" do
      composite = described_class.new(
        category: category,
        name: "Test",
        operator: "AND",
        pattern_ids: [ pattern1.id ],
        usage_count: 5,
        success_count: 10
      )
      expect(composite).not_to be_valid
      expect(composite.errors[:success_count]).to include("cannot be greater than usage count")
    end

    context "conditions validation" do
      it "validates amount conditions" do
        composite = described_class.new(
          category: category,
          name: "Test",
          operator: "AND",
          pattern_ids: [ pattern1.id ],
          conditions: { "min_amount" => -10 }
        )
        expect(composite).not_to be_valid
        expect(composite.errors[:conditions]).to include("min_amount must be a positive number")
      end

      it "validates min < max amount" do
        composite = described_class.new(
          category: category,
          name: "Test",
          operator: "AND",
          pattern_ids: [ pattern1.id ],
          conditions: { "min_amount" => 100, "max_amount" => 50 }
        )
        expect(composite).not_to be_valid
        expect(composite.errors[:conditions]).to include("min_amount must be less than max_amount")
      end

      it "validates days_of_week" do
        composite = described_class.new(
          category: category,
          name: "Test",
          operator: "AND",
          pattern_ids: [ pattern1.id ],
          conditions: { "days_of_week" => [ "invalid_day" ] }
        )
        expect(composite).not_to be_valid
        expect(composite.errors[:conditions]).to include("days_of_week must be an array of valid day names")
      end

      it "validates time_ranges format" do
        composite = described_class.new(
          category: category,
          name: "Test",
          operator: "AND",
          pattern_ids: [ pattern1.id ],
          conditions: { "time_ranges" => [ { "start" => "invalid", "end" => "10:00" } ] }
        )
        expect(composite).not_to be_valid
        expect(composite.errors[:conditions]).to include("time_ranges must be in HH:MM format")
      end
    end
  end

  describe "scopes", integration: true do
    let!(:active_composite) { described_class.create!(category: category, name: "Active", operator: "OR", pattern_ids: [ pattern1.id ], active: true) }
    let!(:inactive_composite) { described_class.create!(category: category, name: "Inactive", operator: "OR", pattern_ids: [ pattern1.id ], active: false) }
    let!(:user_composite) { described_class.create!(category: category, name: "User", operator: "OR", pattern_ids: [ pattern1.id ], user_created: true) }

    it "filters active composites" do
      expect(described_class.active).to include(active_composite, user_composite)
      expect(described_class.active).not_to include(inactive_composite)
    end

    it "filters user created composites" do
      expect(described_class.user_created).to include(user_composite)
      expect(described_class.user_created).not_to include(active_composite)
    end
  end

  describe "#component_patterns", integration: true do
    let(:composite) do
      described_class.create!(
        category: category,
        name: "Rideshare",
        operator: "OR",
        pattern_ids: [ pattern1.id, pattern2.id ]
      )
    end

    it "returns the component patterns" do
      patterns = composite.component_patterns
      expect(patterns).to include(pattern1, pattern2)
      expect(patterns.count).to eq(2)
    end

    it "returns empty array when no pattern_ids" do
      composite.pattern_ids = []
      expect(composite.component_patterns).to eq([])
    end
  end

  describe "#matches?", integration: true do
    let(:email_account) { EmailAccount.create!(email: "composite_pattern_test_#{SecureRandom.hex(4)}@example.com", provider: "gmail", bank_name: "Test Bank") }
    let(:expense) do
      Expense.new(
        email_account: email_account,
        merchant_name: "UBER TRIP",
        description: "Ride to airport",
        amount: 25.00,
        transaction_date: DateTime.new(2024, 1, 6, 14, 0, 0), # Saturday afternoon
        status: "processed",
        currency: "usd"
      )
    end

    context "with OR operator" do
      let(:composite) do
        described_class.create!(
          category: category,
          name: "Rideshare",
          operator: "OR",
          pattern_ids: [ pattern1.id, pattern2.id ]
        )
      end

      it "matches if any pattern matches" do
        expect(composite.matches?(expense)).to be true

        expense.merchant_name = "LYFT"
        expect(composite.matches?(expense)).to be true

        expense.merchant_name = "TAXI"
        expect(composite.matches?(expense)).to be false
      end
    end

    context "with AND operator" do
      let(:pattern3) { CategorizationPattern.create!(category: category, pattern_type: "amount_range", pattern_value: "20-50") }
      let(:composite) do
        described_class.create!(
          category: category,
          name: "Expensive Rideshare",
          operator: "AND",
          pattern_ids: [ pattern1.id, pattern3.id ]
        )
      end

      it "matches only if all patterns match" do
        expect(composite.matches?(expense)).to be true

        expense.amount = 10.00
        expect(composite.matches?(expense)).to be false

        expense.merchant_name = "TAXI"
        expense.amount = 25.00
        expect(composite.matches?(expense)).to be false
      end
    end

    context "with NOT operator" do
      let(:composite) do
        described_class.create!(
          category: category,
          name: "Not Rideshare",
          operator: "NOT",
          pattern_ids: [ pattern1.id, pattern2.id ]
        )
      end

      it "matches if none of the patterns match" do
        expense.merchant_name = "TAXI"
        expect(composite.matches?(expense)).to be true

        expense.merchant_name = "UBER"
        expect(composite.matches?(expense)).to be false
      end
    end

    context "with conditions" do
      let(:composite) do
        described_class.create!(
          category: category,
          name: "Weekend Rideshare",
          operator: "OR",
          pattern_ids: [ pattern1.id ],
          conditions: {
            "days_of_week" => [ "saturday", "sunday" ],
            "min_amount" => 20,
            "max_amount" => 100
          }
        )
      end

      it "checks conditions before patterns" do
        expect(composite.matches?(expense)).to be true

        # Wrong day
        expense.transaction_date = DateTime.new(2024, 1, 8, 14, 0, 0) # Monday
        expect(composite.matches?(expense)).to be false

        # Amount too low
        expense.transaction_date = DateTime.new(2024, 1, 6, 14, 0, 0) # Saturday
        expense.amount = 10.00
        expect(composite.matches?(expense)).to be false
      end
    end

    it "returns false if inactive" do
      composite = described_class.create!(
        category: category,
        name: "Inactive",
        operator: "OR",
        pattern_ids: [ pattern1.id ],
        active: false
      )

      expect(composite.matches?(expense)).to be false
    end
  end

  describe "#add_pattern", integration: true do
    let(:composite) do
      described_class.create!(
        category: category,
        name: "Test",
        operator: "OR",
        pattern_ids: [ pattern1.id ]
      )
    end

    it "adds a pattern by object" do
      composite.add_pattern(pattern2)
      expect(composite.reload.pattern_ids).to include(pattern2.id)
    end

    it "adds a pattern by ID" do
      composite.add_pattern(pattern2.id)
      expect(composite.reload.pattern_ids).to include(pattern2.id)
    end

    it "does not add duplicate patterns" do
      composite.add_pattern(pattern1)
      expect(composite.reload.pattern_ids).to eq([ pattern1.id ])
    end
  end

  describe "#remove_pattern", integration: true do
    let(:composite) do
      described_class.create!(
        category: category,
        name: "Test",
        operator: "OR",
        pattern_ids: [ pattern1.id, pattern2.id ]
      )
    end

    it "removes a pattern by object" do
      composite.remove_pattern(pattern2)
      expect(composite.reload.pattern_ids).not_to include(pattern2.id)
      expect(composite.reload.pattern_ids).to include(pattern1.id)
    end

    it "removes a pattern by ID" do
      composite.remove_pattern(pattern2.id)
      expect(composite.reload.pattern_ids).not_to include(pattern2.id)
    end
  end

  describe "#description", integration: true do
    let(:composite) do
      described_class.new(
        category: category,
        name: "Rideshare",
        operator: operator,
        pattern_ids: [ pattern1.id, pattern2.id ]
      )
    end

    context "with AND operator" do
      let(:operator) { "AND" }

      it "formats description correctly" do
        expect(composite.description).to eq("merchant:uber AND merchant:lyft")
      end
    end

    context "with OR operator" do
      let(:operator) { "OR" }

      it "formats description correctly" do
        expect(composite.description).to eq("merchant:uber OR merchant:lyft")
      end
    end

    context "with NOT operator" do
      let(:operator) { "NOT" }

      it "formats description correctly" do
        expect(composite.description).to eq("NOT (merchant:uber OR merchant:lyft)")
      end
    end
  end

  describe "#effective_confidence", integration: true do
    let(:composite) do
      described_class.create!(
        category: category,
        name: "Test",
        operator: "OR",
        pattern_ids: [ pattern1.id, pattern2.id ],
        confidence_weight: 2.0
      )
    end

    before do
      allow(pattern1).to receive(:effective_confidence).and_return(0.8)
      allow(pattern2).to receive(:effective_confidence).and_return(0.6)
      allow(composite).to receive(:component_patterns).and_return([ pattern1, pattern2 ])
    end

    it "calculates confidence based on component patterns" do
      composite.usage_count = 10
      composite.success_rate = 0.8

      # avg_component_confidence = (0.8 + 0.6) / 2 = 0.7
      # adjusted = 2.0 * (0.7 + (0.7 * 0.3)) = 2.0 * 0.91 = 1.82
      # final = 1.82 * (0.5 + (0.8 * 0.5)) = 1.82 * 0.9 = 1.638

      expect(composite.effective_confidence).to be_within(0.01).of(1.638)
    end

    it "returns 0 if no component patterns" do
      allow(composite).to receive(:component_patterns).and_return([])
      expect(composite.effective_confidence).to eq(0.0)
    end
  end
end
