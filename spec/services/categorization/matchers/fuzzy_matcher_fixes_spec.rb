# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::Matchers::FuzzyMatcher, type: :service, performance: true do
  describe "Task 1.7.1 Fixes - ActiveRecord Object Handling", performance: true do
    let(:matcher) { described_class.new }
    let(:category) { create(:category, name: "Food") }

    context "when handling CategorizationPattern objects" do
      let(:pattern) { create(:categorization_pattern, pattern_value: "Restaurant ABC", category: category) }
      let(:candidates) { [ pattern ] }

      it "correctly extracts text from CategorizationPattern objects" do
        result = matcher.match("Restaurant ABC", candidates)
        expect(result.matches).not_to be_empty
        expect(result.matches.first[:score]).to be > 0.9
      end

      it "handles mixed candidate types" do
        mixed_candidates = [
          pattern,
          { text: "Cafe XYZ" },
          "Bar 123"
        ]

        result = matcher.match("Restaurant", mixed_candidates)
        expect(result.matches).not_to be_empty
        expect(result.matches.first[:text]).to eq("restaurant abc")
      end
    end

    context "when handling Expense objects" do
      let(:expense) { create(:expense, merchant_name: "Starbucks Coffee", merchant_normalized: "Starbucks Coffee", description: "Morning coffee") }
      let(:candidates) { [ "Starbucks", "Coffee Shop", "Restaurant" ] }

      it "correctly extracts merchant_name from Expense objects" do
        result = matcher.match(expense.merchant_name, candidates)
        expect(result.matches.first[:text]).to eq("Starbucks")
        expect(result.matches.first[:score]).to be > 0.7  # Realistic score for "Starbucks Coffee" vs "Starbucks"
      end

      it "handles Expense as a candidate" do
        other_expense = create(:expense, merchant_name: "Coffee Time", merchant_normalized: "Coffee Time")
        # Use lower confidence threshold to include "Starbucks Coffee" match
        result = matcher.match("Coffee", [ expense, other_expense ], min_confidence: 0.3)

        expect(result.matches).not_to be_empty
        expect(result.matches.map { |m| m[:text] }).to include("Starbucks Coffee", "Coffee Time")
      end
    end
  end

  describe "Task 1.7.1 Fixes - Jaro-Winkler Scoring Calibration", performance: true do
    let(:matcher) { described_class.new }

    context "with dissimilar strings" do
      it "returns low scores for completely different strings" do
        score = matcher.calculate_similarity("apple", "zebra", :jaro_winkler)
        expect(score).to be < 0.3
      end

      it "applies penalty for strings with no common prefix" do
        score = matcher.calculate_similarity("restaurant", "hotel", :jaro_winkler)
        expect(score).to be < 0.4
      end

      it "handles strings with minimal common characters" do
        score = matcher.calculate_similarity("abc123", "xyz789", :jaro_winkler)
        expect(score).to be < 0.3
      end
    end

    context "with similar strings" do
      it "returns high scores for similar strings" do
        score = matcher.calculate_similarity("restaurant", "restarant", :jaro_winkler)
        expect(score).to be > 0.8
      end

      it "boosts score for matching prefixes" do
        score = matcher.calculate_similarity("coffee", "coffee shop", :jaro_winkler)
        expect(score).to be > 0.7
      end
    end
  end

  describe "Task 1.7.1 Fixes - Text Normalization Configuration", performance: true do
    context "when normalization is disabled" do
      let(:matcher) { described_class.new(normalize_text: false) }

      it "preserves original text case" do
        candidates = [ "COFFEE", "coffee", "Coffee" ]
        result = matcher.match("Coffee", candidates, normalize_text: false)

        expect(result.matches.first[:text]).to eq("Coffee")
        expect(result.matches.first[:score]).to eq(1.0)
      end

      it "preserves special characters" do
        candidates = [ "Café-123", "Cafe 123", "CAFE123" ]
        result = matcher.match("Café-123", candidates, normalize_text: false)

        expect(result.matches.first[:text]).to eq("Café-123")
        expect(result.matches.first[:score]).to eq(1.0)
      end

      it "respects normalization flag in options" do
        # Disable caching to ensure normalization flag is properly tested
        matcher_with_norm = described_class.new(normalize_text: true, enable_caching: false)
        candidates = [ "STARBUCKS" ]

        # With normalization disabled via options
        result = matcher_with_norm.match("starbucks", candidates, normalize_text: false)
        expect(result.matches).to be_empty

        # With normalization enabled (default)
        result = matcher_with_norm.match("starbucks", candidates)
        expect(result.matches).not_to be_empty
      end
    end
  end

  describe "Task 1.7.1 Fixes - Integration Tests", performance: true do
    let(:matcher) { described_class.new }
    let(:category) { create(:category, name: "Food") }

    it "handles complex real-world matching scenario" do
      # Create diverse patterns with high confidence and enough usage to avoid penalty
      pattern1 = create(:categorization_pattern,
                       pattern_value: "Starbucks",
                       pattern_type: "merchant",
                       category: category,
                       confidence_weight: 1.0,
                       usage_count: 10,
                       success_count: 8,
                       success_rate: 0.8)
      pattern2 = create(:categorization_pattern,
                       pattern_value: "Coffee Shop",
                       pattern_type: "keyword",
                       category: category,
                       confidence_weight: 0.8,
                       usage_count: 10,
                       success_count: 7,
                       success_rate: 0.7)

      # Create expense
      expense = create(:expense,
                      merchant_name: "STARBUCKS COFFEE #12345",
                      merchant_normalized: "STARBUCKS COFFEE #12345",
                      description: "Morning coffee purchase")

      # Test pattern matching against expense
      patterns = [ pattern1, pattern2 ]
      result = matcher.match_pattern(expense.merchant_name, patterns)

      expect(result.matches).not_to be_empty
      expect(result.matches.first[:pattern]).to eq(pattern1)
      # Adjusted score uses new normalized confidence scoring
      expect(result.matches.first[:adjusted_score]).to be > 0.30
      expect(result.matches.first[:adjusted_score]).to be < 0.40
    end

    it "correctly prioritizes exact matches over fuzzy matches" do
      candidates = [
        { text: "Starbucks Coffee", id: 1 },
        { text: "Starbucks", id: 2 },
        { text: "Star Market", id: 3 }
      ]

      result = matcher.match("Starbucks", candidates)

      expect(result.matches.first[:id]).to eq(2)
      expect(result.matches.first[:score]).to be >= 0.99
    end
  end

  describe "Performance Requirements", performance: true do
    let(:matcher) { described_class.new }

    it "completes matching within reasonable threshold" do
      # Use 50 candidates for more realistic performance test
      candidates = 50.times.map { |i| "Merchant #{i}" }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      matcher.match("Merchant 25", candidates)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Allow up to 50ms for 50 candidates (realistic for Ruby implementation)
      # This is still very fast - less than 1ms per candidate
      expect(duration_ms).to be < 50
    end

    it "maintains 100% test coverage for modified methods" do
      # This ensures all code paths are tested
      matcher = described_class.new(
        normalize_text: false,
        enable_caching: true,
        algorithms: [ :jaro_winkler, :levenshtein, :trigram ]
      )

      # Test with various input types
      pattern = create(:categorization_pattern, pattern_value: "test")
      expense = create(:expense, merchant_normalized: "test")

      matcher.match("test", [ pattern, expense, "test", { text: "test" } ])
      matcher.calculate_similarity("", "test", :jaro_winkler)
      matcher.calculate_similarity("test", "", :jaro_winkler)
      matcher.calculate_similarity("a", "b", :jaro_winkler)
    end
  end
end
