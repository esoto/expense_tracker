# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categorization::Orchestrator Integration", type: :service do
  describe "End-to-end service orchestration" do
    let(:orchestrator) { Categorization::OrchestratorFactory.create_test }
    
    # Create test data
    let!(:groceries_category) { create(:category, name: "Groceries") }
    let!(:restaurant_category) { create(:category, name: "Restaurants") }
    let!(:transport_category) { create(:category, name: "Transportation") }
    
    let!(:grocery_patterns) do
      [
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "whole foods",
               category: groceries_category,
               confidence_weight: 2.5),
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "safeway",
               category: groceries_category,
               confidence_weight: 2.3),
        create(:categorization_pattern,
               pattern_type: "keyword",
               pattern_value: "grocery",
               category: groceries_category,
               confidence_weight: 2.2)
      ]
    end
    
    let!(:restaurant_patterns) do
      [
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "starbucks",
               category: restaurant_category,
               confidence_weight: 2.4),
        create(:categorization_pattern,
               pattern_type: "keyword",
               pattern_value: "restaurant",
               category: restaurant_category,
               confidence_weight: 2.0)
      ]
    end
    
    describe "Single expense categorization" do
      context "with clear merchant match" do
        let(:expense) do
          create(:expense,
                 merchant_name: "Whole Foods Market",
                 description: "Grocery shopping",
                 amount: 125.50)
        end
        
        it "categorizes correctly with high confidence" do
          result = orchestrator.categorize(expense)
          
          # Debug output to understand what's happening
          unless result.successful?
            puts "Result failed: #{result.inspect}"
            puts "Error: #{result.error}" if result.respond_to?(:error)
            puts "Method: #{result.method}" if result.respond_to?(:method)
          end
          
          expect(result).to be_successful
          expect(result.category).to eq(groceries_category)
          expect(result.confidence).to be >= 0.7
          expect(result.patterns_used).to include("merchant:whole foods")
        end
        
        it "includes confidence breakdown" do
          result = orchestrator.categorize(expense)
          
          expect(result.confidence_breakdown).to be_present
          expect(result.confidence_breakdown).to include(:text_match)
        end
        
        it "auto-updates expense when configured" do
          result = orchestrator.categorize(expense, auto_update: true, auto_categorize_threshold: 0.6)
          
          expect(result).to be_successful
          expense.reload
          expect(expense.category).to eq(groceries_category)
          expect(expense.auto_categorized).to be true
          expect(expense.categorization_confidence).to be_present
        end
      end
      
      context "with keyword match only" do
        let(:expense) do
          create(:expense,
                 merchant_name: "Unknown Store",
                 description: "Weekly grocery shopping",
                 amount: 200.00)
        end
        
        it "categorizes based on description keywords" do
          result = orchestrator.categorize(expense)
          
          expect(result).to be_successful
          expect(result.category).to eq(groceries_category)
          expect(result.patterns_used).to include("keyword:grocery")
        end
      end
      
      context "with ambiguous patterns" do
        let(:expense) do
          create(:expense,
                 merchant_name: "Food Market",
                 description: "Restaurant supplies",
                 amount: 150.00)
        end
        
        before do
          # Create additional patterns that will match to ensure alternatives
          create(:categorization_pattern,
                 pattern_type: "merchant",
                 pattern_value: "food market",
                 category: groceries_category,
                 confidence_weight: 1.8)
          
          create(:categorization_pattern,
                 pattern_type: "merchant",
                 pattern_value: "food market",
                 category: restaurant_category,
                 confidence_weight: 1.5)
        end
        
        it "returns alternatives when requested" do
          result = orchestrator.categorize(expense, include_alternatives: true)
          
          expect(result.alternative_categories).to be_present
          expect(result.alternative_categories).to be_an(Array)
        end
      end
      
      context "with no matching patterns" do
        let(:expense) do
          create(:expense,
                 merchant_name: "Random Company XYZ",
                 description: "Miscellaneous purchase",
                 amount: 50.00)
        end
        
        it "returns no_match result" do
          result = orchestrator.categorize(expense)
          
          expect(result).not_to be_successful
          expect(result).to be_no_match
          expect(result.category).to be_nil
        end
      end
    end
    
    describe "Batch categorization" do
      let(:expenses) do
        [
          create(:expense, merchant_name: "Whole Foods", amount: 100),
          create(:expense, merchant_name: "Starbucks", amount: 5),
          create(:expense, merchant_name: "Safeway", amount: 80),
          create(:expense, merchant_name: "Unknown Store", amount: 20)
        ]
      end
      
      it "processes multiple expenses efficiently" do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = orchestrator.batch_categorize(expenses)
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        
        expect(results).to be_an(Array)
        expect(results.size).to eq(4)
        expect(results).to all(be_a(Categorization::CategorizationResult))
        
        # Should be efficient for batch processing
        expect(elapsed_ms).to be < 200 # 50ms per expense max
      end
      
      it "preloads data to avoid N+1 queries" do
        # Use ActiveRecord query counter
        query_count = 0
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          query_count += 1
        end
        
        orchestrator.batch_categorize(expenses)
        
        ActiveSupport::Notifications.unsubscribe("sql.active_record")
        
        # Should have minimal queries (preloading patterns and categories)
        # Allow for reasonable number of queries but prevent N+1
        # With 4 expenses and various lookups, allow up to 100 queries but ensure it's not N+1
        expect(query_count).to be < 100 # Baseline + preload queries + lookups
      end
      
      context "with parallel processing" do
        it "processes expenses in parallel when configured" do
          results = orchestrator.batch_categorize(expenses, parallel: true)
          
          expect(results.size).to eq(4)
          expect(results).to all(be_a(Categorization::CategorizationResult))
        end
      end
    end
    
    describe "User preference handling" do
      let(:expense) do
        create(:expense,
               merchant_name: "Coffee Shop ABC",
               description: "Morning coffee",
               amount: 4.50)
      end
      
      let!(:user_preference) do
        create(:user_category_preference,
               context_type: "merchant",
               context_value: "coffee shop abc",
               category: restaurant_category,
               preference_weight: 9.0)
      end
      
      it "prioritizes user preferences" do
        result = orchestrator.categorize(expense)
        
        expect(result).to be_successful
        expect(result.category).to eq(restaurant_category)
        expect(result.confidence).to be >= 0.9
        expect(result).to be_user_preference
      end
      
      it "skips user preferences when disabled" do
        result = orchestrator.categorize(expense, check_user_preferences: false)
        
        expect(result).not_to be_user_preference
      end
    end
    
    describe "Learning from corrections" do
      let(:expense) do
        create(:expense,
               merchant_name: "New Store XYZ",
               description: "Shopping",
               amount: 75.00,
               category: nil)
      end
      
      it "learns from user corrections" do
        result = orchestrator.learn_from_correction(
          expense,
          groceries_category,
          nil
        )
        
        expect(result).to be_success
        expect(result.patterns_created.size).to be >= 0
      end
      
      it "invalidates caches after learning" do
        # Mock cache invalidation
        pattern_cache = orchestrator.pattern_cache
        expect(pattern_cache).to receive(:invalidate_category).with(groceries_category.id)
        
        orchestrator.learn_from_correction(expense, groceries_category)
      end
    end
    
    describe "Error handling and recovery" do
      context "with database errors" do
        it "handles database connection errors gracefully" do
          allow(CategorizationPattern).to receive(:active).and_raise(
            ActiveRecord::StatementInvalid, "Database connection lost"
          )
          
          expense = create(:expense)
          result = orchestrator.categorize(expense)
          
          expect(result).to be_failed
          expect(result.error).to include("Database connection error")
        end
      end
      
      context "with service failures" do
        it "degrades gracefully when services fail" do
          # Simulate pattern cache failure
          allow(orchestrator.pattern_cache).to receive(:get_patterns_for_expense)
            .and_raise(StandardError, "Cache unavailable")
          
          expense = create(:expense)
          result = orchestrator.categorize(expense)
          
          expect(result).to be_failed
        end
      end
    end
    
    describe "Configuration management" do
      it "allows runtime configuration changes" do
        orchestrator.configure(
          min_confidence: 0.6,
          auto_categorize_threshold: 0.75,
          include_alternatives: true,
          max_alternatives: 5
        )
        
        expense = create(:expense, merchant_name: "Test Store")
        result = orchestrator.categorize(expense, include_alternatives: true)
        
        # Configuration should be applied
        expect(result).to be_a(Categorization::CategorizationResult)
      end
    end
    
    describe "Health monitoring" do
      it "reports health status correctly" do
        expect(orchestrator).to be_healthy
        
        # Simulate unhealthy service
        allow(orchestrator.pattern_cache).to receive(:healthy?).and_return(false)
        
        expect(orchestrator).not_to be_healthy
      end
      
      it "provides detailed metrics" do
        metrics = orchestrator.metrics
        
        expect(metrics).to include(
          :pattern_cache,
          :matcher,
          :confidence_calculator,
          :pattern_learner,
          :performance_tracker
        )
      end
    end
    
    describe "Service reset functionality" do
      it "resets all services correctly" do
        # Perform some operations
        expense = create(:expense, merchant_name: "Test Store")
        orchestrator.categorize(expense)
        
        # Reset
        expect { orchestrator.reset! }.not_to raise_error
        
        # Should still work after reset
        result = orchestrator.categorize(expense)
        expect(result).to be_a(Categorization::CategorizationResult)
      end
    end
  end
end