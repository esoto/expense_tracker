# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categorization Pattern Edge Cases", type: :model do
  let(:category) { create(:category, name: "Test Category") }
  
  describe CategorizationPattern do
    describe "concurrent updates" do
      it "handles race conditions with optimistic locking" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Starbucks"
        )
        
        # Simulate concurrent access
        pattern1 = CategorizationPattern.find(pattern.id)
        pattern2 = CategorizationPattern.find(pattern.id)
        
        pattern1.record_usage(true)
        pattern2.record_usage(false)
        
        expect(pattern1.reload.usage_count).to eq(2)
        expect(pattern1.success_count).to eq(1)
      end
    end
    
    describe "boundary value testing" do
      it "handles maximum confidence weight" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          confidence_weight: 5.0
        )
        
        expect(pattern.confidence_weight).to eq(5.0)
        pattern.confidence_weight = 5.1
        expect(pattern).not_to be_valid
      end
      
      it "handles minimum confidence weight" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          confidence_weight: 0.1
        )
        
        expect(pattern.confidence_weight).to eq(0.1)
        pattern.confidence_weight = 0.09
        expect(pattern).not_to be_valid
      end
      
      it "handles very large usage counts" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          usage_count: 999_999_999,
          success_count: 500_000_000
        )
        
        expect(pattern.success_rate).to be_within(0.01).of(0.5)
      end
    end
    
    describe "special characters and encoding" do
      it "handles Unicode characters in pattern values" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Café 北京 🍕"
        )
        
        expect(pattern.matches?("Café 北京 🍕")).to be true
      end
      
      it "handles SQL injection attempts in pattern values" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "'; DROP TABLE users; --"
        )
        
        expect(pattern.pattern_value).to eq("'; DROP TABLE users; --")
        expect { pattern.matches?("test") }.not_to raise_error
      end
      
      it "handles regex special characters in non-regex patterns" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test.*Company[0-9]+"
        )
        
        # Should match literally, not as regex
        expect(pattern.matches?("Test.*Company[0-9]+")).to be true
        expect(pattern.matches?("Test Company123")).to be false
      end
    end
    
    describe "metadata handling" do
      it "handles complex nested metadata" do
        metadata = {
          source: "user_input",
          confidence_factors: {
            historical_accuracy: 0.95,
            sample_size: 1000,
            last_updated: Time.current
          },
          rules: [
            { type: "exclude", value: "refund" },
            { type: "include", value: "purchase" }
          ]
        }
        
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          metadata: metadata
        )
        
        expect(pattern.metadata["confidence_factors"]["historical_accuracy"]).to eq(0.95)
        expect(pattern.metadata["rules"].size).to eq(2)
      end
      
      it "handles nil metadata gracefully" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          metadata: nil
        )
        
        expect(pattern.metadata).to eq({})
      end
    end
    
    describe "amount range edge cases" do
      it "handles very small amounts" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "amount_range",
          pattern_value: "0.01-0.99"
        )
        
        expect(pattern.matches?(expense: double(amount: 0.01))).to be true
        expect(pattern.matches?(expense: double(amount: 0.99))).to be true
        expect(pattern.matches?(expense: double(amount: 1.00))).to be false
      end
      
      it "handles very large amounts" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "amount_range",
          pattern_value: "1000000-9999999"
        )
        
        expect(pattern.matches?(expense: double(amount: 1_000_000))).to be true
        expect(pattern.matches?(expense: double(amount: 999_999))).to be false
      end
      
      it "handles negative amounts" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "amount_range",
          pattern_value: "-100--50"
        )
        
        expect(pattern.matches?(expense: double(amount: -75))).to be true
        expect(pattern.matches?(expense: double(amount: -49))).to be false
      end
    end
    
    describe "time pattern edge cases" do
      it "handles midnight boundary" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "time",
          pattern_value: "23:00-01:00"
        )
        
        expect(pattern.matches?(expense: double(transaction_date: Time.parse("23:30")))).to be true
        expect(pattern.matches?(expense: double(transaction_date: Time.parse("00:30")))).to be true
        expect(pattern.matches?(expense: double(transaction_date: Time.parse("02:00")))).to be false
      end
      
      it "handles year boundaries" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "time",
          pattern_value: "weekend"
        )
        
        # Test New Year's Eve/Day
        expect(pattern.matches?(expense: double(transaction_date: Date.new(2024, 12, 31)))).to be false # Tuesday
        expect(pattern.matches?(expense: double(transaction_date: Date.new(2025, 1, 4)))).to be true # Saturday
      end
    end
    
    describe "regex pattern security" do
      it "prevents ReDoS attacks" do
        # Potentially dangerous regex
        pattern = CategorizationPattern.new(
          category: category,
          pattern_type: "regex",
          pattern_value: "(a+)+" # Catastrophic backtracking
        )
        
        expect(pattern).not_to be_valid
        expect(pattern.errors[:pattern_value]).to include("is not a valid regular expression")
      end
      
      it "handles complex but safe regex patterns" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "regex",
          pattern_value: "^(uber|lyft)\\s+(trip|ride)\\s+\\d{4}-\\d{2}-\\d{2}$"
        )
        
        expect(pattern.matches?("uber trip 2024-01-01")).to be true
        expect(pattern.matches?("lyft ride 2024-12-31")).to be true
        expect(pattern.matches?("taxi trip 2024-01-01")).to be false
      end
    end
    
    describe "deactivation thresholds" do
      it "deactivates after consistent failures" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          usage_count: 100,
          success_count: 10,
          active: true
        )
        
        pattern.check_and_deactivate_if_poor_performance
        
        expect(pattern.active).to be false
      end
      
      it "preserves user-created patterns even with poor performance" do
        pattern = CategorizationPattern.create!(
          category: category,
          pattern_type: "merchant",
          pattern_value: "Test",
          usage_count: 100,
          success_count: 10,
          user_created: true,
          active: true
        )
        
        pattern.check_and_deactivate_if_poor_performance
        
        expect(pattern.active).to be true # User patterns not auto-deactivated
      end
    end
  end
  
  describe CompositePattern do
    let!(:pattern1) do
      CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "Starbucks"
      )
    end
    
    let!(:pattern2) do
      CategorizationPattern.create!(
        category: category,
        pattern_type: "amount_range",
        pattern_value: "5-20"
      )
    end
    
    describe "circular reference prevention" do
      it "prevents self-reference" do
        composite = CompositePattern.create!(
          category: category,
          name: "Test Composite",
          operator: "AND",
          pattern_ids: [pattern1.id]
        )
        
        # Try to add itself to pattern_ids
        composite.pattern_ids = [composite.id]
        
        expect(composite).not_to be_valid
        expect(composite.errors[:pattern_ids]).to include("must exist and belong to CategorizationPattern")
      end
    end
    
    describe "operator edge cases" do
      it "handles empty pattern_ids with OR operator" do
        composite = CompositePattern.new(
          category: category,
          name: "Empty OR",
          operator: "OR",
          pattern_ids: []
        )
        
        expect(composite).not_to be_valid
        expect(composite.errors[:pattern_ids]).to include("can't be blank")
      end
      
      it "handles NOT operator with multiple patterns" do
        composite = CompositePattern.create!(
          category: category,
          name: "NOT multiple",
          operator: "NOT",
          pattern_ids: [pattern1.id, pattern2.id]
        )
        
        expense = double(merchant_name: "Starbucks", amount: 10)
        expect(composite.matches?(expense)).to be false # Both match, so NOT returns false
        
        expense2 = double(merchant_name: "McDonald's", amount: 100)
        expect(composite.matches?(expense2)).to be true # Neither match, so NOT returns true
      end
    end
    
    describe "complex conditions" do
      it "handles multiple condition types together" do
        conditions = {
          min_amount: 100,
          max_amount: 500,
          days_of_week: [1, 5], # Monday and Friday
          time_ranges: ["09:00-17:00", "20:00-22:00"]
        }
        
        composite = CompositePattern.create!(
          category: category,
          name: "Complex conditions",
          operator: "AND",
          pattern_ids: [pattern1.id],
          conditions: conditions
        )
        
        # Should match: right amount, right day, right time
        expense = double(
          merchant_name: "Starbucks",
          amount: 250,
          transaction_date: Time.parse("2024-01-01 10:00") # Monday at 10am
        )
        
        expect(composite.matches?(expense)).to be true
        
        # Should not match: wrong time
        expense2 = double(
          merchant_name: "Starbucks",
          amount: 250,
          transaction_date: Time.parse("2024-01-01 18:00") # Monday at 6pm
        )
        
        expect(composite.matches?(expense2)).to be false
      end
    end
    
    describe "performance with large pattern sets" do
      it "handles composites with many patterns efficiently" do
        patterns = 50.times.map do |i|
          CategorizationPattern.create!(
            category: category,
            pattern_type: "merchant",
            pattern_value: "Merchant#{i}"
          )
        end
        
        composite = CompositePattern.create!(
          category: category,
          name: "Large composite",
          operator: "OR",
          pattern_ids: patterns.map(&:id)
        )
        
        expense = double(merchant_name: "Merchant25")
        
        # Should complete quickly even with many patterns
        result = nil
        time = Benchmark.realtime { result = composite.matches?(expense) }
        
        expect(result).to be true
        expect(time).to be < 0.1 # Should complete in under 100ms
      end
    end
    
    describe "description generation" do
      it "handles very long pattern lists" do
        patterns = 10.times.map do |i|
          CategorizationPattern.create!(
            category: category,
            pattern_type: "merchant",
            pattern_value: "Very Long Merchant Name #{i} That Goes On And On"
          )
        end
        
        composite = CompositePattern.create!(
          category: category,
          name: "Long description",
          operator: "OR",
          pattern_ids: patterns.map(&:id)
        )
        
        description = composite.description
        
        expect(description).to include("Very Long Merchant Name 0")
        expect(description.length).to be < 1000 # Should truncate or summarize
      end
    end
  end
  
  describe "Integration between patterns and composites" do
    it "handles pattern deletion with composite references" do
      pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "Test"
      )
      
      composite = CompositePattern.create!(
        category: category,
        name: "Test Composite",
        operator: "AND",
        pattern_ids: [pattern.id]
      )
      
      # Deleting a pattern should handle composite gracefully
      pattern.destroy
      
      composite.reload
      expect(composite.pattern_ids).to eq([pattern.id]) # ID remains but pattern is gone
      expect(composite.component_patterns).to eq([]) # No actual patterns returned
    end
    
    it "handles category changes" do
      other_category = create(:category, name: "Other Category")
      
      pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "Test"
      )
      
      # Should not allow changing to a different category if referenced
      pattern.category = other_category
      expect(pattern.save).to be true # Pattern can change category
      
      # But composite should validate pattern categories match
      composite = CompositePattern.new(
        category: category,
        name: "Mismatched",
        operator: "AND",
        pattern_ids: [pattern.id]
      )
      
      expect(composite).not_to be_valid # Different categories
    end
  end
end