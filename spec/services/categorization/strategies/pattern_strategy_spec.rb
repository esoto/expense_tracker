# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Strategies::PatternStrategy, :unit, type: :service do
  let(:pattern_cache_service) do
    Services::Categorization::PatternCache.new
  end

  let(:fuzzy_matcher) do
    Services::Categorization::Matchers::FuzzyMatcher.new
  end

  let(:confidence_calculator) do
    Services::Categorization::ConfidenceCalculator.new
  end

  let(:strategy) do
    described_class.new(
      pattern_cache_service: pattern_cache_service,
      fuzzy_matcher: fuzzy_matcher,
      confidence_calculator: confidence_calculator
    )
  end

  let(:category) { create(:category, name: "Groceries #{SecureRandom.hex(4)}") }

  let(:expense) do
    create(:expense,
           merchant_name: "Whole Foods Market",
           description: "Grocery shopping",
           amount: 125.50,
           transaction_date: Time.current)
  end

  describe "#layer_name" do
    it "returns 'pattern'" do
      expect(strategy.layer_name).to eq("pattern")
    end
  end

  describe "interface compliance" do
    it "inherits from BaseStrategy" do
      expect(strategy).to be_a(Services::Categorization::Strategies::BaseStrategy)
    end

    it "responds to #call" do
      expect(strategy).to respond_to(:call)
    end

    it "responds to #layer_name" do
      expect(strategy).to respond_to(:layer_name)
    end
  end

  describe "#call" do
    it "returns a CategorizationResult" do
      result = strategy.call(expense)
      expect(result).to be_a(Services::Categorization::CategorizationResult)
    end

    context "with matching merchant pattern" do
      let!(:merchant_pattern) do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "whole foods",
               category: category,
               confidence_weight: 1.5,
               usage_count: 50,
               success_count: 45)
      end

      it "returns a successful result with the correct category" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.confidence).to be > 0.5
      end

      it "includes patterns_used in the result" do
        result = strategy.call(expense)

        expect(result.patterns_used).to include("merchant:whole foods")
      end

      it "includes matched_patterns in metadata for usage recording" do
        result = strategy.call(expense)

        expect(result.metadata[:matched_patterns]).to be_present
        expect(result.metadata[:matched_patterns].first).to be_a(CategorizationPattern)
      end

      it "tracks processing time" do
        result = strategy.call(expense)

        expect(result.processing_time_ms).to be_a(Float)
        expect(result.processing_time_ms).to be >= 0
      end
    end

    context "with matching keyword pattern" do
      let!(:keyword_pattern) do
        create(:categorization_pattern,
               pattern_type: "keyword",
               pattern_value: "grocery",
               category: category,
               confidence_weight: 1.2,
               usage_count: 30,
               success_count: 25)
      end

      it "matches on description keywords" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
      end
    end

    context "with no matching patterns" do
      let(:unmatched_expense) do
        create(:expense,
               merchant_name: "Random Store XYZ #{SecureRandom.hex(8)}",
               description: "Unknown purchase #{SecureRandom.hex(8)}",
               amount: 50.00)
      end

      it "returns a no_match result" do
        result = strategy.call(unmatched_expense)

        expect(result).not_to be_successful
        expect(result).to be_no_match
        expect(result.category).to be_nil
      end

      it "includes processing time in no_match result" do
        result = strategy.call(unmatched_expense)

        expect(result.processing_time_ms).to be_a(Float)
        expect(result.processing_time_ms).to be >= 0
      end
    end

    context "with confidence below min_confidence" do
      let!(:weak_pattern) do
        create(:categorization_pattern,
               pattern_type: "keyword",
               pattern_value: "market",
               category: category,
               confidence_weight: 0.3,
               usage_count: 5,
               success_count: 2)
      end

      it "returns no_match when best match is below threshold" do
        result = strategy.call(expense, min_confidence: 0.99)

        expect(result).to be_no_match
      end
    end

    context "with user preferences" do
      let!(:user_preference) do
        create(:user_category_preference,
               context_type: "merchant",
               context_value: "whole foods market",
               category: category,
               preference_weight: 8.0)
      end

      it "returns user preference result when available" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.method).to eq("user_preference")
        expect(result.confidence).to be >= 0.85
      end

      it "skips user preferences when disabled" do
        result = strategy.call(expense, check_user_preferences: false)

        if result.successful?
          expect(result.method).not_to eq("user_preference")
        end
      end
    end

    context "with amount_range pattern" do
      let(:amount_category) { create(:category, name: "Amount-#{SecureRandom.hex(4)}") }
      let!(:amount_pattern) do
        create(:categorization_pattern, :new_pattern,
               pattern_type: "amount_range",
               pattern_value: "100.00-150.00",
               category: amount_category)
      end

      it "matches non-fuzzy pattern types" do
        # Clear any other patterns that might match
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(amount_category)
      end
    end

    context "with include_alternatives option" do
      let(:other_category) { create(:category, name: "Other #{SecureRandom.hex(4)}") }

      let!(:primary_pattern) do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "whole foods",
               category: category,
               confidence_weight: 2.0,
               usage_count: 100,
               success_count: 90)
      end

      let!(:secondary_pattern) do
        create(:categorization_pattern,
               pattern_type: "keyword",
               pattern_value: "food",
               category: other_category,
               confidence_weight: 0.8,
               usage_count: 20,
               success_count: 15)
      end

      it "includes alternative categories when requested" do
        result = strategy.call(expense, include_alternatives: true)

        expect(result).to be_successful
        expect(result.alternative_categories).to be_an(Array)
      end
    end

    context "when user preference check fails" do
      before do
        allow(pattern_cache_service).to receive(:get_user_preference).and_raise(StandardError, "Cache down")
      end

      let!(:pattern) do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "whole foods",
               category: category,
               confidence_weight: 1.5,
               usage_count: 50,
               success_count: 45)
      end

      it "falls through to pattern matching" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.method).not_to eq("user_preference")
      end
    end
  end
end
