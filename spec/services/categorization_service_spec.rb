# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationService do
  let(:service) { described_class.new }
  let(:groceries_category) { create(:category, name: "Groceries") }
  let(:dining_category) { create(:category, name: "Dining") }
  let(:transport_category) { create(:category, name: "Transportation") }
  
  describe "#categorize_expense" do
    let(:expense) do
      create(:expense,
        merchant_name: "Starbucks Coffee",
        description: "Coffee and pastry",
        amount: 15.50,
        transaction_date: Time.current
      )
    end
    
    context "with matching patterns" do
      before do
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "merchant",
          pattern_value: "Starbucks",
          confidence_weight: 3.0,
          success_rate: 0.95
        )
        
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "keyword",
          pattern_value: "coffee",
          confidence_weight: 2.0,
          success_rate: 0.80
        )
      end
      
      it "categorizes expense based on patterns" do
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to eq(dining_category)
        expect(result[:confidence]).to be > 0.8
        expect(result[:method]).to eq("pattern_matching")
        expect(result[:patterns_used]).to include("merchant:Starbucks", "keyword:coffee")
      end
      
      it "updates expense with categorization" do
        service.categorize_expense(expense)
        
        expense.reload
        expect(expense.category).to eq(dining_category)
        expect(expense.auto_categorized).to be true
        expect(expense.categorization_confidence).to be > 0.8
        expect(expense.categorization_method).to eq("pattern_matching")
      end
    end
    
    context "with competing patterns" do
      before do
        # Strong pattern for dining
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "merchant",
          pattern_value: "Restaurant",
          confidence_weight: 4.0,
          success_rate: 0.98
        )
        
        # Weaker pattern for groceries
        CategorizationPattern.create!(
          category: groceries_category,
          pattern_type: "keyword",
          pattern_value: "food",
          confidence_weight: 1.5,
          success_rate: 0.60
        )
      end
      
      it "chooses category with highest confidence score" do
        expense.update!(
          merchant_name: "Restaurant ABC",
          description: "Food purchase"
        )
        
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to eq(dining_category)
        expect(result[:confidence]).to be > result[:alternative_categories].first[:confidence]
      end
      
      it "returns alternative categories" do
        expense.update!(
          merchant_name: "Restaurant ABC",
          description: "Food purchase"
        )
        
        result = service.categorize_expense(expense)
        
        expect(result[:alternative_categories]).not_to be_empty
        expect(result[:alternative_categories].first[:category]).to eq(groceries_category)
      end
    end
    
    context "with composite patterns" do
      let!(:merchant_pattern) do
        CategorizationPattern.create!(
          category: transport_category,
          pattern_type: "merchant",
          pattern_value: "Uber"
        )
      end
      
      let!(:amount_pattern) do
        CategorizationPattern.create!(
          category: transport_category,
          pattern_type: "amount_range",
          pattern_value: "10-50"
        )
      end
      
      let!(:composite) do
        CompositePattern.create!(
          category: transport_category,
          name: "Uber rides",
          operator: "AND",
          pattern_ids: [merchant_pattern.id, amount_pattern.id],
          confidence_weight: 4.5
        )
      end
      
      it "uses composite patterns for categorization" do
        expense.update!(
          merchant_name: "Uber Technologies",
          amount: 25.00
        )
        
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to eq(transport_category)
        expect(result[:method]).to eq("composite_pattern")
        expect(result[:patterns_used]).to include("composite:Uber rides")
      end
      
      it "requires all conditions for AND composite" do
        expense.update!(
          merchant_name: "Uber Technologies",
          amount: 100.00 # Outside range
        )
        
        result = service.categorize_expense(expense)
        
        # Composite shouldn't match, might match individual pattern
        if result[:category] == transport_category
          expect(result[:method]).not_to eq("composite_pattern")
        end
      end
    end
    
    context "with user preferences" do
      before do
        UserCategoryPreference.create!(
          merchant_name: "Starbucks",
          category: dining_category,
          confidence: 1.0
        )
        
        # Conflicting pattern
        CategorizationPattern.create!(
          category: groceries_category,
          pattern_type: "merchant",
          pattern_value: "Starbucks",
          confidence_weight: 3.0
        )
      end
      
      it "prioritizes user preferences over patterns" do
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to eq(dining_category)
        expect(result[:method]).to eq("user_preference")
        expect(result[:confidence]).to eq(1.0)
      end
    end
    
    context "with learning feedback" do
      before do
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "merchant",
          pattern_value: "Cafe",
          usage_count: 50,
          success_count: 45,
          success_rate: 0.9
        )
      end
      
      it "records successful categorization" do
        expense.update!(merchant_name: "Cafe Nero")
        
        result = service.categorize_expense(expense)
        pattern = CategorizationPattern.find_by(pattern_value: "Cafe")
        
        initial_usage = pattern.usage_count
        
        service.record_feedback(expense, result[:category], true)
        
        pattern.reload
        expect(pattern.usage_count).to eq(initial_usage + 1)
        expect(pattern.success_count).to eq(46)
      end
      
      it "records failed categorization" do
        expense.update!(merchant_name: "Cafe Nero")
        
        result = service.categorize_expense(expense)
        pattern = CategorizationPattern.find_by(pattern_value: "Cafe")
        
        service.record_feedback(expense, groceries_category, false)
        
        pattern.reload
        expect(pattern.usage_count).to eq(51)
        expect(pattern.success_count).to eq(45) # No increase
      end
      
      it "creates learning event" do
        expense.update!(merchant_name: "Cafe Nero")
        result = service.categorize_expense(expense)
        
        expect {
          service.record_feedback(expense, result[:category], true)
        }.to change(PatternLearningEvent, :count).by(1)
        
        event = PatternLearningEvent.last
        expect(event.expense).to eq(expense)
        expect(event.was_correct).to be true
        expect(event.confidence_score).to eq(result[:confidence])
      end
    end
    
    context "with no matching patterns" do
      it "returns nil category" do
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to be_nil
        expect(result[:confidence]).to eq(0)
        expect(result[:method]).to eq("no_match")
      end
      
      it "does not update expense" do
        service.categorize_expense(expense)
        
        expense.reload
        expect(expense.category).to be_nil
        expect(expense.auto_categorized).to be false
      end
    end
    
    context "with disabled patterns" do
      before do
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "merchant",
          pattern_value: "Starbucks",
          active: false,
          confidence_weight: 5.0
        )
      end
      
      it "ignores inactive patterns" do
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to be_nil
        expect(result[:patterns_used]).to be_empty
      end
    end
    
    context "error handling" do
      it "handles nil expense gracefully" do
        expect { service.categorize_expense(nil) }.not_to raise_error
        
        result = service.categorize_expense(nil)
        expect(result[:category]).to be_nil
        expect(result[:error]).to eq("Invalid expense")
      end
      
      it "handles database errors gracefully" do
        allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::ConnectionNotEstablished)
        
        result = service.categorize_expense(expense)
        
        expect(result[:category]).to be_nil
        expect(result[:error]).to include("Database error")
      end
      
      it "handles malformed patterns gracefully" do
        CategorizationPattern.create!(
          category: dining_category,
          pattern_type: "regex",
          pattern_value: "[invalid regex"
        )
        
        expect { service.categorize_expense(expense) }.not_to raise_error
      end
    end
  end
  
  describe "#bulk_categorize" do
    let(:expenses) do
      [
        create(:expense, merchant_name: "Starbucks", amount: 5),
        create(:expense, merchant_name: "Walmart", amount: 150),
        create(:expense, merchant_name: "Uber", amount: 25)
      ]
    end
    
    before do
      CategorizationPattern.create!(
        category: dining_category,
        pattern_type: "merchant",
        pattern_value: "Starbucks"
      )
      
      CategorizationPattern.create!(
        category: groceries_category,
        pattern_type: "merchant",
        pattern_value: "Walmart"
      )
      
      CategorizationPattern.create!(
        category: transport_category,
        pattern_type: "merchant",
        pattern_value: "Uber"
      )
    end
    
    it "categorizes multiple expenses efficiently" do
      results = service.bulk_categorize(expenses)
      
      expect(results.size).to eq(3)
      expect(results[0][:category]).to eq(dining_category)
      expect(results[1][:category]).to eq(groceries_category)
      expect(results[2][:category]).to eq(transport_category)
    end
    
    it "uses batch queries for performance" do
      expect(CategorizationPattern).to receive(:active).once.and_call_original
      
      service.bulk_categorize(expenses)
    end
    
    it "handles mixed success and failures" do
      expenses << create(:expense, merchant_name: "Unknown Store")
      
      results = service.bulk_categorize(expenses)
      
      expect(results.size).to eq(4)
      expect(results[3][:category]).to be_nil
    end
  end
  
  describe "#suggest_new_patterns" do
    it "identifies frequently uncategorized merchants" do
      5.times { create(:expense, merchant_name: "New Coffee Shop", category: nil) }
      3.times { create(:expense, merchant_name: "New Restaurant", category: nil) }
      
      suggestions = service.suggest_new_patterns
      
      expect(suggestions).to include(
        hash_including(
          merchant: "New Coffee Shop",
          frequency: 5,
          suggested_category: nil
        )
      )
    end
    
    it "suggests categories based on similar merchants" do
      CategorizationPattern.create!(
        category: dining_category,
        pattern_type: "merchant",
        pattern_value: "Coffee"
      )
      
      5.times { create(:expense, merchant_name: "New Coffee Shop", category: nil) }
      
      suggestions = service.suggest_new_patterns
      
      coffee_suggestion = suggestions.find { |s| s[:merchant] == "New Coffee Shop" }
      expect(coffee_suggestion[:suggested_category]).to eq(dining_category)
    end
  end
  
  describe "#pattern_performance_report" do
    before do
      @pattern1 = CategorizationPattern.create!(
        category: dining_category,
        pattern_type: "merchant",
        pattern_value: "Restaurant",
        usage_count: 100,
        success_count: 95
      )
      
      @pattern2 = CategorizationPattern.create!(
        category: groceries_category,
        pattern_type: "merchant",
        pattern_value: "Market",
        usage_count: 50,
        success_count: 25
      )
    end
    
    it "generates performance metrics for patterns" do
      report = service.pattern_performance_report
      
      expect(report[:high_performing].map(&:id)).to include(@pattern1.id)
      expect(report[:low_performing].map(&:id)).to include(@pattern2.id)
      expect(report[:summary][:total_patterns]).to eq(2)
      expect(report[:summary][:average_success_rate]).to be_between(0, 1)
    end
    
    it "recommends patterns for deactivation" do
      report = service.pattern_performance_report
      
      expect(report[:recommendations][:deactivate].map(&:id)).to include(@pattern2.id)
    end
  end
end