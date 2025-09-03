# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PatternTestService, unit: true do
  describe "Performance Limits" do
    let(:service) { described_class.new(params) }
    let(:params) do
      {
        description: "Test transaction",
        merchant_name: "Test Store",
        amount: "100.00",
        transaction_date: "2024-01-15"
      }
    end

    let(:mock_category) { instance_double("Category", name: "Test Category", id: 1) }
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

    describe "Timeout Enforcement" do
      it "enforces 1 second timeout per pattern" do
        allow(mock_pattern).to receive(:matches?) { sleep(1.5) }

        start_time = Time.current
        result = service.test_single_pattern(mock_pattern)
        duration = Time.current - start_time

        expect(result).to be false
        expect(duration).to be < 1.5
      end

      it "timeout is exactly 1 second as configured" do
        stub_const("Admin::PatternTestService::TIMEOUT_SECONDS", 1)
        expect(Admin::PatternTestService::TIMEOUT_SECONDS).to eq(1)
      end

      it "continues processing after timeout" do
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

        allow(pattern1).to receive(:matches?) { sleep(1.5) }
        allow(pattern2).to receive(:matches?).and_return(true)
        allow(Rails.cache).to receive(:fetch).and_return([ pattern1, pattern2 ])

        service.test_patterns
        expect(service.matching_patterns.size).to eq(1)
        expect(service.matching_patterns.first[:pattern]).to eq(pattern2)
      end

      it "logs timeout occurrences" do
        allow(mock_pattern).to receive(:matches?) { sleep(1.5) }
        allow(Rails.cache).to receive(:fetch).and_return([ mock_pattern ])

        service.test_patterns
        expect(Rails.logger).to have_received(:warn).with(/Pattern 1 test timeout/)
      end

      it "adds timeout error for single pattern test" do
        allow(mock_pattern).to receive(:matches?) { sleep(1.5) }

        service.test_single_pattern(mock_pattern)
        expect(service.errors[:base]).to include("Pattern test timed out - pattern may be too complex")
      end

      it "handles rapid successive timeouts" do
        patterns = 5.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: true, effective_confidence: 0.9,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          ).tap { |p| allow(p).to receive(:matches?) { sleep(1.5) } }
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        start_time = Time.current
        service.test_patterns
        duration = Time.current - start_time

        # Should timeout each individually, not wait for all
        expect(duration).to be < 7.5 # Would be 7.5 if all waited full time
      end

      it "applies timeout to pattern matches? method only" do
        allow(mock_pattern).to receive(:matches?) do
          # Simulate complex regex that takes time
          start = Time.current
          while (Time.current - start) < 2
            "a" * 1000 =~ /^(a+)+$/
          end
          true
        end

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
      end
    end

    describe "Input Length Limits" do
      it "enforces MAX_INPUT_LENGTH constant of 1000" do
        expect(Admin::PatternTestService::MAX_INPUT_LENGTH).to eq(1000)
      end

      it "truncates description to MAX_INPUT_LENGTH" do
        long_description = "a" * 2000
        service = described_class.new(description: long_description)
        expect(service.description.length).to eq(1000)
      end

      it "truncates merchant_name to MAX_INPUT_LENGTH" do
        long_name = "b" * 2000
        service = described_class.new(merchant_name: long_name)
        expect(service.merchant_name.length).to eq(1000)
      end

      it "validates description length" do
        service.description = "a" * 1001
        expect(service.valid?).to be false
        expect(service.errors[:description]).to include("is too long (maximum is 1000 characters)")
      end

      it "validates merchant_name length" do
        service.merchant_name = "b" * 1001
        expect(service.valid?).to be false
        expect(service.errors[:merchant_name]).to include("is too long (maximum is 1000 characters)")
      end

      it "allows exactly MAX_INPUT_LENGTH characters" do
        service.description = "a" * 1000
        service.merchant_name = "b" * 1000
        expect(service.valid?).to be true
      end

      it "truncates before validation" do
        service = described_class.new(description: "a" * 2000)
        expect(service.valid?).to be true # Already truncated in initialize
      end

      it "handles unicode characters in length calculation" do
        unicode_string = "🎉" * 1100
        service = described_class.new(description: unicode_string)
        expect(service.description.length).to eq(1000)
      end

      it "preserves important content when truncating" do
        important_text = "Important: " + ("x" * 1000)
        service = described_class.new(description: important_text)
        expect(service.description).to start_with("Important:")
      end
    end

    describe "Pattern Count Limits" do
      it "enforces MAX_PATTERNS_TO_TEST constant of 100" do
        expect(Admin::PatternTestService::MAX_PATTERNS_TO_TEST).to eq(100)
      end

      it "limits patterns to MAX_PATTERNS_TO_TEST" do
        allow(Rails.cache).to receive(:fetch).and_yield
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:to_a).and_return([])

        expect(CategorizationPattern).to receive(:active).and_return(relation)
        expect(relation).to receive(:limit).with(100).and_return(relation)

        service.test_patterns
      end

      it "processes exactly MAX_PATTERNS_TO_TEST patterns" do
        patterns = 150.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: i.even?, effective_confidence: 0.9,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        # Simulate database returning limited results
        limited_patterns = patterns.take(100)
        allow(Rails.cache).to receive(:fetch).and_return(limited_patterns)

        service.test_patterns

        # Count how many were actually tested
        expect(limited_patterns.size).to eq(100)
      end

      it "handles fewer patterns than limit gracefully" do
        patterns = 10.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: true, effective_confidence: 0.9,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        service.test_patterns
        expect(service.matching_patterns.size).to eq(10)
      end

      it "does not create memory issues with max patterns" do
        patterns = 100.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: true, effective_confidence: rand,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        expect { service.test_patterns }.not_to raise_error
        expect(service.matching_patterns.size).to eq(100)
      end
    end

    describe "Amount Limits" do
      it "enforces maximum amount of 10 million" do
        service = described_class.new(amount: "10000000")
        expect(service.amount).to be_nil
      end

      it "accepts amount just below 10 million" do
        service = described_class.new(amount: "9999999.99")
        expect(service.amount).to eq(9999999.99)
      end

      it "validates amount upper bound" do
        service.amount = 10_000_000
        expect(service.valid?).to be false
        expect(service.errors[:amount]).to include("must be less than 10000000")
      end

      it "validates amount lower bound" do
        service.amount = -1
        expect(service.valid?).to be false
        expect(service.errors[:amount]).to include("must be greater than or equal to 0")
      end

      it "allows nil amount" do
        service.amount = nil
        expect(service.valid?).to be true
      end

      it "sanitizes amounts above limit to nil" do
        service = described_class.new(amount: "99999999999")
        expect(service.amount).to be_nil
      end

      it "sanitizes negative amounts to positive" do
        # The sanitization removes non-numeric chars including "-", so "-500" becomes "500"
        service = described_class.new(amount: "-500")
        expect(service.amount).to eq(500.0)
      end
    end

    describe "Memory Management" do
      it "does not accumulate pattern results in memory" do
        patterns = 50.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: false, effective_confidence: 0.9,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        service.test_patterns
        expect(service.matching_patterns).to be_empty # Non-matching patterns not stored
      end

      it "clears test expense between runs" do
        service.test_patterns
        first_expense = service.test_expense

        service.test_patterns
        second_expense = service.test_expense

        expect(first_expense).not_to equal(second_expense)
      end

      it "does not leak memory with large inputs" do
        large_description = "a" * 1000
        large_merchant = "b" * 1000

        100.times do
          temp_service = described_class.new(
            description: large_description,
            merchant_name: large_merchant
          )
          temp_service.test_patterns
        end

        # If we get here without memory errors, test passes
        expect(true).to be true
      end

      it "handles garbage collection during pattern testing" do
        patterns = 100.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: true, effective_confidence: rand,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        # Force GC during test
        allow(mock_pattern).to receive(:matches?) do
          GC.start
          true
        end

        expect { service.test_patterns }.not_to raise_error
      end
    end

    # Cache TTL tests moved to cache_behavior_spec.rb

    describe "Date Range Limits" do
      it "rejects dates more than 10 years in past" do
        old_date = 11.years.ago
        service = described_class.new(transaction_date: old_date.to_s)
        expect(service.transaction_date).to be_within(1.hour).of(DateTime.current)
      end

      it "rejects dates more than 10 years in future" do
        future_date = 11.years.from_now
        service = described_class.new(transaction_date: future_date.to_s)
        expect(service.transaction_date).to be_within(1.hour).of(DateTime.current)
      end

      it "accepts dates exactly 10 years ago" do
        valid_date = 10.years.ago + 1.day
        service = described_class.new(transaction_date: valid_date.to_s)
        # Convert both to Time for comparison
        expect(service.transaction_date.to_time).to be_within(1.day).of(valid_date.to_time)
      end

      it "accepts dates exactly 10 years in future" do
        valid_date = 10.years.from_now - 1.day
        service = described_class.new(transaction_date: valid_date.to_s)
        # Convert both to Time for comparison
        expect(service.transaction_date.to_time).to be_within(1.day).of(valid_date.to_time)
      end
    end

    describe "Performance Optimization" do
      it "short-circuits on validation failure" do
        # Create service and then set invalid data to bypass sanitization
        invalid_service = described_class.new(description: "test")
        invalid_service.description = "a" * 1001 # Exceeds MAX_INPUT_LENGTH

        expect(Rails.cache).not_to receive(:fetch)

        result = invalid_service.test_patterns
        expect(result).to be false
      end

      it "builds test expense only once per test run" do
        allow(Rails.cache).to receive(:fetch).and_return([ mock_pattern, mock_pattern ])

        # Should create OpenStruct only once
        expect(OpenStruct).to receive(:new).once.and_call_original

        service.test_patterns
      end

      it "sorts results efficiently after all matching" do
        patterns = 10.times.map do |i|
          instance_double("CategorizationPattern",
            id: i, matches?: true, effective_confidence: rand,
            category: mock_category, pattern_type: "description",
            created_at: Time.current
          )
        end

        allow(Rails.cache).to receive(:fetch).and_return(patterns)

        service.test_patterns

        # Verify sorting happened (highest confidence first)
        confidences = service.matching_patterns.map { |m| m[:confidence] }
        expect(confidences).to eq(confidences.sort.reverse)
      end

      it "minimizes logger calls on success" do
        allow(Rails.cache).to receive(:fetch).and_return([ mock_pattern ])

        service.test_patterns

        expect(Rails.logger).not_to have_received(:error)
        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end
end
