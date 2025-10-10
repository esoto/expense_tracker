# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::EnhancedCategorizationService, performance: true do
  let(:service) { described_class.new }

  describe "#categorize", performance: true do
    let(:food_category) { create(:category, name: "Food & Dining") }
    let(:transport_category) { create(:category, name: "Transportation") }
    let(:expense) do
      build(:expense,
            merchant_name: "STARBUCKS COFFEE #123",
            description: "Coffee purchase",
            amount: 5.75,
            transaction_date: Time.current)
    end

    context "with user preferences" do
      before do
        create(:user_category_preference,
               context_type: "merchant",
               context_value: "starbucks coffee #123",
               category: food_category)
      end

      it "prioritizes user preferences" do
        category = service.categorize(expense)
        expect(category).to eq(food_category)
      end

      it "tracks cache hits in metrics" do
        service.categorize(expense)

        metrics = service.metrics
        expect(metrics[:categorization][:cache_hits]).to eq(1)
      end
    end

    context "with canonical merchant matching" do
      before do
        canonical = create(:canonical_merchant,
                          name: "starbucks",
                          display_name: "Starbucks",
                          category_hint: "Food & Dining")

        create(:merchant_alias,
               raw_name: "STARBUCKS COFFEE #123",
               normalized_name: "starbucks coffee",
               canonical_merchant: canonical,
               confidence: 0.95)

        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "starbucks",
               category: food_category)
      end

      it "finds category through canonical merchant" do
        category = service.categorize(expense)
        expect(category).to eq(food_category)
      end

      it "tracks fuzzy matching in metrics" do
        service.categorize(expense)

        metrics = service.metrics
        expect(metrics[:categorization][:fuzzy_matched]).to be >= 1
      end
    end

    context "with pattern matching" do
      before do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "Starbucks",
               category: food_category,
               confidence_weight: 2.0,
               usage_count: 100,
               success_count: 90)
      end

      it "matches patterns using fuzzy logic" do
        category = service.categorize(expense)
        expect(category).to eq(food_category)
      end

      it "handles typos in merchant names" do
        expense.merchant_name = "STARBUKCS COFFE" # typos

        category = service.categorize(expense)
        expect(category).to eq(food_category)
      end

      it "respects confidence thresholds" do
        # Create a low-confidence pattern
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "Random Merchant",
               category: transport_category,
               confidence_weight: 0.1)

        expense.merchant_name = "Something completely different"

        category = service.categorize(expense)
        expect(category).to be_nil # Should not match due to low confidence
      end
    end

    context "with composite patterns" do
      let(:pattern1) do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "uber",
               category: transport_category)
      end

      let(:pattern2) do
        create(:categorization_pattern,
               pattern_type: "amount_range",
               pattern_value: "5-50",
               category: transport_category)
      end

      before do
        create(:composite_pattern,
               name: "Uber Rides",
               operator: "AND",
               pattern_ids: [ pattern1.id, pattern2.id ],
               category: transport_category)
      end

      it "matches composite patterns" do
        expense.merchant_name = "UBER *TRIP"
        expense.amount = 25.00

        category = service.categorize(expense)
        expect(category).to eq(transport_category)
      end
    end

    context "with multiple pattern types" do
      before do
        # Use a strong merchant pattern that should definitely match
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "STARBUCKS",
               category: food_category,
               confidence_weight: 3.0,
               success_rate: 0.95,
               usage_count: 15,
               success_count: 14)

        # And a description pattern to complement it
        create(:categorization_pattern,
               pattern_type: "description",
               pattern_value: "coffee",
               category: food_category,
               confidence_weight: 2.5,
               success_rate: 0.90,
               usage_count: 12,
               success_count: 11)
      end

      it "considers all pattern types" do
        # Expense has merchant_name: "STARBUCKS COFFEE #123" and description: "Coffee purchase"
        # Both patterns should match
        category = service.categorize(expense)
        expect(category).to eq(food_category)
      end
    end
  end

  describe "#categorize_batch", performance: true do
    let(:food_category) { create(:category, name: "Food & Dining") }
    let(:transport_category) { create(:category, name: "Transportation") }

    let(:expenses) do
      [
        build(:expense, merchant_name: "STARBUCKS", amount: 5.00),
        build(:expense, merchant_name: "UBER TRIP", amount: 15.00),
        build(:expense, merchant_name: "WALMART", amount: 75.00)
      ]
    end

    before do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "starbucks",
             category: food_category)

      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "uber",
             category: transport_category)
    end

    it "categorizes multiple expenses efficiently" do
      results = service.categorize_batch(expenses)

      expect(results).to be_an(Array)
      expect(results.size).to eq(3)

      expect(results[0][:category]).to eq(food_category)
      expect(results[1][:category]).to eq(transport_category)
    end

    it "includes confidence scores" do
      results = service.categorize_batch(expenses)

      results.each do |result|
        expect(result).to have_key(:confidence)
        expect(result[:confidence]).to be_a(Numeric) if result[:category]
      end
    end

    it "preloads cache for efficiency" do
      expect_any_instance_of(Categorization::PatternCache)
        .to receive(:preload_for_expenses).with(expenses)

      service.categorize_batch(expenses)
    end
  end

  describe "#find_matching_patterns", performance: true do
    let(:category) { create(:category) }

    before do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "Starbucks Coffee",
             category: category)

      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "Coffee Shop",
             category: category)

      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "Walmart",
             category: category)
    end

    it "finds matching patterns for merchant name" do
      matches = service.find_matching_patterns("starbucks")

      expect(matches).not_to be_empty
      expect(matches.first[:text]).to include("starbucks")
    end

    it "returns multiple matches sorted by score" do
      matches = service.find_matching_patterns("coffee")

      expect(matches.size).to be >= 2

      # Verify sorting
      scores = matches.map { |m| m[:score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it "respects max_results option" do
      matches = service.find_matching_patterns("coffee", max_results: 1)

      expect(matches.size).to eq(1)
    end

    it "respects min_confidence option" do
      matches = service.find_matching_patterns("xyz", min_confidence: 0.9)

      expect(matches).to be_empty
    end
  end

  describe "#suggest_categories", performance: true do
    let(:food_category) { create(:category, name: "Food & Dining") }
    let(:shopping_category) { create(:category, name: "Shopping") }

    let(:expense) do
      build(:expense,
            merchant_name: "STARBUCKS COFFEE",
            description: "Morning coffee and pastry")
    end

    before do
      # Create canonical merchant with category hint
      canonical = create(:canonical_merchant,
                        name: "starbucks",
                        display_name: "Starbucks",
                        category_hint: "Food & Dining")

      create(:merchant_alias,
             raw_name: "STARBUCKS COFFEE",
             canonical_merchant: canonical)

      # Create patterns
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "starbucks",
             category: food_category,
             confidence_weight: 2.0)

      create(:categorization_pattern,
             pattern_type: "description",
             pattern_value: "coffee",
             category: food_category)
    end

    it "suggests categories based on merchant and patterns" do
      suggestions = service.suggest_categories(expense)

      expect(suggestions).not_to be_empty
      expect(suggestions.first[:category]).to eq(food_category)
    end

    it "includes confidence scores and reasons" do
      suggestions = service.suggest_categories(expense)

      suggestions.each do |suggestion|
        expect(suggestion).to have_key(:confidence)
        expect(suggestion).to have_key(:reason)
        expect(suggestion).to have_key(:type)
      end
    end

    it "limits number of suggestions" do
      suggestions = service.suggest_categories(expense, 2)

      expect(suggestions.size).to be <= 2
    end

    it "sorts suggestions by confidence" do
      suggestions = service.suggest_categories(expense)

      if suggestions.size > 1
        confidences = suggestions.map { |s| s[:confidence] }
        expect(confidences).to eq(confidences.sort.reverse)
      end
    end
  end

  describe "#learn_from_feedback", performance: true do
    let(:category) { create(:category) }
    let(:email_account) { create(:email_account) }
    let(:expense) { create(:expense, merchant_name: "NEW MERCHANT", email_account: email_account) }
    let(:pattern) do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "new merchant",
             category: category,
             usage_count: 5,
             success_count: 3)
    end

    before do
      # Simulate that this pattern was used
      service.instance_variable_set(:@last_matched_pattern, pattern)
      service.instance_variable_set(:@last_match_confidence, 0.85)
    end

    it "updates pattern statistics" do
      expect { service.learn_from_feedback(expense, category, true) }
        .to change { pattern.reload.usage_count }.by(1)
        .and change { pattern.reload.success_count }.by(1)
    end

    it "creates user preference when correct" do
      # Ensure no existing preference
      UserCategoryPreference.where(
        context_type: "merchant",
        context_value: expense.merchant_name.downcase.strip
      ).destroy_all

      expect {
        service.learn_from_feedback(expense, category, true)
      }.to change(UserCategoryPreference, :count).by(1)

      preference = UserCategoryPreference.last
      expect(preference.context_value).to eq("new merchant")
      expect(preference.category).to eq(category)
    end

    it "doesn't create preference when incorrect" do
      expect {
        service.learn_from_feedback(expense, category, false)
      }.not_to change(UserCategoryPreference, :count)
    end

    it "records learning event" do
      expect {
        service.learn_from_feedback(expense, category, true)
      }.to change(PatternLearningEvent, :count).by(1)

      event = PatternLearningEvent.last
      expect(event.expense).to eq(expense)
      expect(event.category).to eq(category)
      expect(event.was_correct).to be true
    end
  end

  describe "#metrics", performance: true do
    it "returns comprehensive metrics" do
      # Perform some operations
      expense = build(:expense, merchant_name: "TEST")
      service.categorize(expense)

      metrics = service.metrics

      expect(metrics).to have_key(:categorization)
      expect(metrics).to have_key(:fuzzy_matcher)
      expect(metrics).to have_key(:pattern_cache)

      expect(metrics[:categorization]).to include(
        :categorized,
        :fuzzy_matched,
        :cache_hits
      )
    end
  end

  describe "Spanish text handling", performance: true do
    let(:category) { create(:category, name: "Restaurantes") }

    let(:expense) do
      build(:expense,
            merchant_name: "CAFÉ MARÍA",
            description: "Almuerzo en el restaurante")
    end

    before do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "cafe maria",
             category: category)
    end

    it "handles Spanish accents in matching" do
      result = service.categorize(expense)
      expect(result).to eq(category)
    end

    it "normalizes ñ character" do
      expense.merchant_name = "PANADERÍA PEÑA"

      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "panaderia pena",
             category: category)

      result = service.categorize(expense)
      expect(result).to eq(category)
    end
  end

  describe "performance", performance: true do
    it "categorizes within reasonable time" do
      expense = build(:expense, merchant_name: "STARBUCKS")

      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "starbucks",
             category: create(:category))

      time = Benchmark.realtime { service.categorize(expense) }

      # Performance varies in test environment - use more lenient threshold
      expect(time * 1000).to be < 50
    end

    it "batch categorizes efficiently" do
      expenses = 10.times.map do |i|
        build(:expense, merchant_name: "Merchant #{i}")
      end

      time = Benchmark.realtime { service.categorize_batch(expenses) }
      time_per_expense = (time * 1000) / expenses.size

      expect(time_per_expense).to be < 25  # Updated for enhanced matching capabilities
    end
  end
end
