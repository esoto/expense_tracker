# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PatternTestService, unit: true do
  describe "Pattern Matching" do
    let(:service) { described_class.new(params) }
    let(:params) do
      {
        description: "Coffee at Starbucks",
        merchant_name: "Starbucks",
        amount: "5.50",
        transaction_date: "2024-01-15"
      }
    end

    let(:mock_category) { instance_double("Category", name: "Food & Dining", id: 1) }
    let(:mock_pattern) do
      instance_double("CategorizationPattern",
        id: 1,
        matches?: true,
        effective_confidence: 0.9,
        category: mock_category,
        pattern_type: "description",
        created_at: Time.current
      )
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.cache).to receive(:fetch).and_return([])
    end

    describe "OpenStruct Test Expense Creation" do
      it "creates OpenStruct with description" do
        service.test_patterns
        expect(service.test_expense).to be_a(OpenStruct)
        expect(service.test_expense.description).to eq("Coffee at Starbucks")
      end

      it "creates OpenStruct with merchant_name" do
        service.test_patterns
        expect(service.test_expense.merchant_name).to eq("Starbucks")
      end

      it "creates OpenStruct with amount" do
        service.test_patterns
        expect(service.test_expense.amount).to eq(5.50)
      end

      it "creates OpenStruct with transaction_date" do
        service.test_patterns
        expect(service.test_expense.transaction_date).to be_a(DateTime)
      end

      it "creates OpenStruct with all nil values" do
        service = described_class.new({})
        service.test_patterns

        expect(service.test_expense.description).to be_nil
        expect(service.test_expense.merchant_name).to be_nil
        expect(service.test_expense.amount).to be_nil
        expect(service.test_expense.transaction_date).to be_a(DateTime)
      end

      it "does not persist to database" do
        expect { service.test_patterns }.not_to change { Expense.count }
      end

      it "creates new OpenStruct for each test" do
        service.test_patterns
        first_expense = service.test_expense

        service.test_patterns
        second_expense = service.test_expense

        expect(first_expense).not_to equal(second_expense)
      end

      it "allows OpenStruct to respond to expense methods" do
        service.test_patterns

        expect(service.test_expense).to respond_to(:description)
        expect(service.test_expense).to respond_to(:merchant_name)
        expect(service.test_expense).to respond_to(:amount)
        expect(service.test_expense).to respond_to(:transaction_date)
      end

      it "creates OpenStruct with sanitized values" do
        service = described_class.new(description: "Test'; DROP TABLE;")
        service.test_patterns

        expect(service.test_expense.description).to eq("Test DROP TABLE")
      end
    end

    describe "Pattern Test Logic" do
      before do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(Admin::PatternTestService::MAX_PATTERNS_TO_TEST).and_return(relation)
        allow(relation).to receive(:to_a).and_return([ mock_pattern ])
        allow(CategorizationPattern).to receive(:active).and_return(relation)
        allow(Rails.cache).to receive(:fetch).and_yield
      end

      it "calls matches? on each pattern" do
        expect(mock_pattern).to receive(:matches?).with(instance_of(OpenStruct))
        service.test_patterns
      end

      it "collects matching patterns" do
        service.test_patterns
        expect(service.matching_patterns).not_to be_empty
        expect(service.matching_patterns.first[:pattern]).to eq(mock_pattern)
      end

      it "includes pattern confidence in results" do
        service.test_patterns
        expect(service.matching_patterns.first[:confidence]).to eq(0.9)
      end

      it "includes category in results" do
        service.test_patterns
        expect(service.matching_patterns.first[:category]).to eq(mock_category)
      end

      it "includes pattern_type in results" do
        service.test_patterns
        expect(service.matching_patterns.first[:pattern_type]).to eq("description")
      end

      it "includes created_at in results" do
        service.test_patterns
        expect(service.matching_patterns.first[:created_at]).to be_a(Time)
      end

      it "handles non-matching patterns" do
        allow(mock_pattern).to receive(:matches?).and_return(false)

        service.test_patterns
        expect(service.matching_patterns).to be_empty
      end

      it "handles multiple matching patterns" do
        pattern1 = instance_double("CategorizationPattern",
          id: 1, matches?: true, effective_confidence: 0.9,
          category: mock_category, pattern_type: "description",
          created_at: 1.day.ago
        )
        pattern2 = instance_double("CategorizationPattern",
          id: 2, matches?: true, effective_confidence: 0.8,
          category: mock_category, pattern_type: "merchant",
          created_at: Time.current
        )

        allow(Rails.cache).to receive(:fetch).and_return([ pattern1, pattern2 ])

        service.test_patterns
        expect(service.matching_patterns.size).to eq(2)
      end

      it "sorts patterns by confidence descending" do
        pattern1 = instance_double("CategorizationPattern",
          id: 1, matches?: true, effective_confidence: 0.7,
          category: mock_category, pattern_type: "description",
          created_at: Time.current
        )
        pattern2 = instance_double("CategorizationPattern",
          id: 2, matches?: true, effective_confidence: 0.95,
          category: mock_category, pattern_type: "merchant",
          created_at: Time.current
        )

        allow(Rails.cache).to receive(:fetch).and_return([ pattern1, pattern2 ])

        service.test_patterns
        expect(service.matching_patterns.first[:confidence]).to eq(0.95)
        expect(service.matching_patterns.last[:confidence]).to eq(0.7)
      end

      it "continues testing after pattern error" do
        pattern1 = instance_double("CategorizationPattern",
          id: 1, matches?: true, effective_confidence: 0.9,
          category: mock_category, pattern_type: "description",
          created_at: Time.current
        )
        pattern2 = instance_double("CategorizationPattern",
          id: 2, matches?: true, effective_confidence: 0.8,
          category: mock_category, pattern_type: "merchant",
          created_at: Time.current
        )

        allow(pattern1).to receive(:matches?).and_raise(StandardError, "Pattern error")
        allow(pattern2).to receive(:matches?).and_return(true)
        allow(Rails.cache).to receive(:fetch).and_return([ pattern1, pattern2 ])

        service.test_patterns
        expect(service.matching_patterns.size).to eq(1)
        expect(service.matching_patterns.first[:pattern]).to eq(pattern2)
      end

      it "logs pattern test failures" do
        allow(mock_pattern).to receive(:matches?).and_raise(StandardError, "Test error")
        allow(Rails.cache).to receive(:fetch).and_return([ mock_pattern ])

        service.test_patterns
        expect(Rails.logger).to have_received(:warn).with(/Pattern 1 test failed/)
      end
    end

    describe "Single Pattern Testing" do
      it "tests a single pattern successfully" do
        allow(mock_pattern).to receive(:matches?).and_return(true)
        result = service.test_single_pattern(mock_pattern)
        expect(result).to be true
      end

      it "returns false for non-matching pattern" do
        allow(mock_pattern).to receive(:matches?).and_return(false)

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
      end

      it "validates inputs before testing" do
        # Create service with invalid data that will fail validation
        invalid_service = described_class.new(description: "test")
        # Bypass sanitization by setting invalid value directly
        invalid_service.description = "a" * 1001
        allow(mock_pattern).to receive(:matches?).and_return(true)
        result = invalid_service.test_single_pattern(mock_pattern)
        expect(result).to be false
      end

      it "handles pattern errors gracefully" do
        allow(mock_pattern).to receive(:matches?).and_raise(StandardError, "Pattern error")

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
        expect(service.errors[:base]).to include("Pattern test failed: Pattern error")
      end

      it "creates test expense for single pattern test" do
        expect(mock_pattern).to receive(:matches?).with(instance_of(OpenStruct))
        service.test_single_pattern(mock_pattern)
      end

      it "enforces timeout on single pattern test" do
        allow(mock_pattern).to receive(:matches?) do
          raise Timeout::Error, "execution expired"
        end

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
        expect(service.errors[:base]).to include("Pattern test timed out - pattern may be too complex")
      end

      it "logs timeout for single pattern test" do
        allow(mock_pattern).to receive(:matches?) do
          raise Timeout::Error, "execution expired"
        end

        service.test_single_pattern(mock_pattern)
        expect(Rails.logger).to have_received(:warn).with(/Pattern test timeout/)
      end

      it "does not modify matching_patterns for single test" do
        service.test_single_pattern(mock_pattern)
        expect(service.matching_patterns).to be_empty
      end
    end

    # Cache behavior tests moved to cache_behavior_spec.rb
  end
end
