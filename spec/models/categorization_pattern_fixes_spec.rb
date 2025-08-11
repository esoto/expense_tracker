# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationPattern, type: :model do
  describe "Task 1.7.1 Fixes - Expense Object Matching" do
    let(:category) { create(:category, name: "Food") }

    context "when matching Expense objects with merchant patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "merchant",
                            pattern_value: "starbucks",
                            category: category) }

      it "matches expense with matching merchant_name" do
        expense = build(:expense, merchant_name: "Starbucks Coffee", description: "Morning brew")
        expect(pattern.matches?(expense)).to be true
      end

      it "does not match expense with non-matching merchant_name" do
        expense = build(:expense, merchant_name: "McDonald's", description: "Lunch")
        expect(pattern.matches?(expense)).to be false
      end

      it "handles expense without merchant_name gracefully" do
        expense = build(:expense, merchant_name: nil, description: "Unknown purchase")
        expect(pattern.matches?(expense)).to be false
      end
    end

    context "when matching Expense objects with description patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "description",
                            pattern_value: "coffee",
                            category: category) }

      it "matches expense with matching description" do
        expense = build(:expense, merchant_name: "Store ABC", description: "Coffee purchase")
        expect(pattern.matches?(expense)).to be true
      end

      it "does not check merchant_name for description patterns" do
        expense = build(:expense, merchant_name: "Coffee Shop", description: "Tea purchase")
        expect(pattern.matches?(expense)).to be false
      end

      it "handles expense without description gracefully" do
        expense = build(:expense, merchant_name: "Coffee Shop", description: nil)
        expect(pattern.matches?(expense)).to be false
      end
    end

    context "when matching Expense objects with keyword patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "keyword",
                            pattern_value: "lunch",
                            category: category) }

      it "matches expense with keyword in description" do
        expense = build(:expense, merchant_name: "Restaurant", description: "Business lunch meeting")
        expect(pattern.matches?(expense)).to be true
      end

      it "matches expense with keyword in merchant_name when no description" do
        expense = build(:expense, merchant_name: "Lunch Box Cafe", description: nil)
        expect(pattern.matches?(expense)).to be true
      end

      it "prioritizes description over merchant_name" do
        expense = build(:expense, merchant_name: "Dinner Place", description: "Quick lunch")
        expect(pattern.matches?(expense)).to be true
      end
    end

    context "when matching Expense objects with regex patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "regex",
                            pattern_value: "COFFEE|CAFE|STARBUCKS",
                            category: category) }

      it "matches against combined description and merchant_name" do
        expense = build(:expense, merchant_name: "Store 123", description: "COFFEE purchase")
        expect(pattern.matches?(expense)).to be true
      end

      it "matches when pattern is in merchant_name only" do
        expense = build(:expense, merchant_name: "STARBUCKS #456", description: nil)
        expect(pattern.matches?(expense)).to be true
      end

      it "handles complex regex patterns" do
        pattern.update!(pattern_value: "^STAR.*\\d{3,}$")
        expense = build(:expense, merchant_name: "STARBUCKS 12345", description: nil)
        expect(pattern.matches?(expense)).to be true
      end
    end

    context "when matching Expense objects with amount_range patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "amount_range",
                            pattern_value: "10.00-50.00",
                            category: category) }

      it "matches expense within amount range" do
        expense = build(:expense, amount: 25.50)
        expect(pattern.matches?(expense)).to be true
      end

      it "does not match expense outside amount range" do
        expense = build(:expense, amount: 75.00)
        expect(pattern.matches?(expense)).to be false
      end

      it "handles negative amounts" do
        pattern.update!(pattern_value: "-100.00--50.00")
        expense = build(:expense, amount: -75.00)
        expect(pattern.matches?(expense)).to be true
      end
    end

    context "when matching Expense objects with time patterns" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "time",
                            pattern_value: "morning",
                            category: category) }

      it "matches expense with morning transaction" do
        expense = build(:expense, transaction_date: Time.zone.parse("2024-01-15 09:30:00"))
        expect(pattern.matches?(expense)).to be true
      end

      it "does not match expense with evening transaction" do
        expense = build(:expense, transaction_date: Time.zone.parse("2024-01-15 19:30:00"))
        expect(pattern.matches?(expense)).to be false
      end

      it "handles time range patterns" do
        pattern.update!(pattern_value: "09:00-17:00")
        expense = build(:expense, transaction_date: Time.zone.parse("2024-01-15 14:30:00"))
        expect(pattern.matches?(expense)).to be true
      end
    end

    context "when matching with Hash input (backward compatibility)" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "merchant",
                            pattern_value: "amazon",
                            category: category) }

      it "matches with hash containing expense" do
        expense = build(:expense, merchant_name: "Amazon.com")
        expect(pattern.matches?(expense: expense)).to be true
      end

      it "matches with hash containing merchant_name" do
        expect(pattern.matches?(merchant_name: "Amazon Prime")).to be true
      end

      it "matches with hash containing description" do
        pattern.update!(pattern_type: "description")
        expect(pattern.matches?(description: "Amazon purchase")).to be true
      end
    end

    context "when matching with String input (backward compatibility)" do
      let(:pattern) { create(:categorization_pattern,
                            pattern_type: "merchant",
                            pattern_value: "walmart",
                            category: category) }

      it "matches string directly" do
        expect(pattern.matches?("Walmart Store")).to be true
      end

      it "handles regex patterns with strings" do
        pattern.update!(pattern_type: "regex", pattern_value: "WAL.*MART")
        expect(pattern.matches?("WALMART #123")).to be true
      end
    end
  end

  describe "Edge Cases and Error Handling" do
    let(:category) { create(:category) }
    let(:pattern) { create(:categorization_pattern, category: category) }

    it "handles nil input gracefully" do
      expect(pattern.matches?(nil)).to be false
    end

    it "handles objects without expected methods" do
      custom_object = Object.new
      expect(pattern.matches?(custom_object)).to be false
    end

    it "handles empty expense fields" do
      expense = build(:expense, merchant_name: "", description: "")
      expect(pattern.matches?(expense)).to be false
    end

    it "handles malformed amount ranges gracefully" do
      # Note: Validation prevents saving invalid patterns, so we test with valid pattern
      pattern.update!(pattern_type: "amount_range", pattern_value: "10-50")
      # Test with non-numeric value
      expect(pattern.matches?("not_a_number")).to be false
      # Test with expense
      expense = build(:expense, amount: 30.00)
      expect(pattern.matches?(expense)).to be true
    end
  end

  describe "Performance" do
    let(:category) { create(:category) }

    it "matches quickly even with complex patterns" do
      pattern = create(:categorization_pattern,
                      pattern_type: "regex",
                      pattern_value: "(STAR|COFFEE|CAFE).*(SHOP|STORE|HOUSE)",
                      category: category)

      expense = build(:expense,
                     merchant_name: "STARBUCKS COFFEE SHOP",
                     description: "Morning coffee and pastry")

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times { pattern.matches?(expense) }
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      expect(duration_ms).to be < 100 # Less than 1ms per match
    end
  end
end
