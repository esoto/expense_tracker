# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categorization Models Integration", type: :model do
  let(:category) { Category.create!(name: "Food & Dining") }
  let(:email_account) { EmailAccount.create!(email: "test@example.com", provider: "gmail", bank_name: "Test Bank") }
  let(:expense) do
    Expense.create!(
      email_account: email_account,
      merchant_name: "Starbucks #1234",
      description: "Coffee and breakfast",
      amount: 15.50,
      transaction_date: DateTime.new(2024, 1, 8, 8, 30, 0), # Monday morning
      status: "processed",
      currency: "usd"
    )
  end

  describe "full categorization workflow" do
    it "creates and uses patterns to categorize expenses" do
      # Create a merchant pattern
      merchant_pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "starbucks",
        confidence_weight: 2.0
      )

      expect(merchant_pattern).to be_valid
      expect(merchant_pattern.matches?("STARBUCKS")).to be true

      # Create an amount range pattern
      amount_pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "amount_range",
        pattern_value: "10.00-25.00",
        confidence_weight: 1.5
      )

      expect(amount_pattern).to be_valid
      expect(amount_pattern.matches?(15.50)).to be true

      # Create a composite pattern combining both
      composite = CompositePattern.create!(
        category: category,
        name: "Starbucks breakfast",
        operator: "AND",
        pattern_ids: [ merchant_pattern.id, amount_pattern.id ],
        confidence_weight: 2.5
      )

      expect(composite).to be_valid
      expect(composite.matches?(expense)).to be true

      # Record feedback when categorization is correct
      feedback = PatternFeedback.record_feedback(
        expense: expense,
        correct_category: category,
        pattern: merchant_pattern,
        was_correct: true,
        confidence: 0.85,
        type: "confirmation"
      )

      expect(feedback).to be_persisted
      expect(feedback.successful?).to be true

      # Record a learning event
      event = PatternLearningEvent.record_event(
        expense: expense,
        category: category,
        pattern: composite,
        was_correct: true,
        confidence: 0.9
      )

      expect(event).to be_persisted
      expect(event.successful?).to be true

      # Learn user preferences
      UserCategoryPreference.learn_from_categorization(
        email_account: email_account,
        expense: expense,
        category: category
      )

      preferences = UserCategoryPreference.matching_preferences(
        email_account: email_account,
        expense: expense
      )

      expect(preferences).not_to be_empty
      expect(preferences.first.category).to eq(category)
    end
  end

  describe "merchant normalization" do
    it "normalizes merchant names and creates aliases" do
      # Create canonical merchant
      canonical = CanonicalMerchant.find_or_create_from_raw("STARBUCKS #1234")

      expect(canonical).to be_persisted
      expect(canonical.name).to eq("starbucks")
      expect(canonical.display_name).to eq("Starbucks")

      # Find the same merchant with different format
      canonical2 = CanonicalMerchant.find_or_create_from_raw("Starbucks Store #5678")
      expect(canonical2.id).to eq(canonical.id)

      # Check aliases were created
      aliases = MerchantAlias.for_merchant(canonical)
      expect(aliases.count).to eq(2)

      # Test alias matching
      best_match = MerchantAlias.find_best_match("STARBUCKS #9999")
      expect(best_match).not_to be_nil
      expect(best_match.canonical_merchant).to eq(canonical)
    end
  end

  describe "pattern learning and improvement" do
    it "learns from user corrections" do
      # Initial wrong categorization
      wrong_category = Category.create!(name: "Shopping")
      expense.update!(category: wrong_category)

      # User corrects to right category
      feedback = PatternFeedback.create!(
        expense: expense,
        category: category, # Correct category
        was_correct: false,
        feedback_type: "correction"
      )

      # Check that improvement suggestion is generated
      suggestion = feedback.improvement_suggestion
      expect(suggestion).not_to be_nil
      expect(suggestion[:pattern_type]).to eq("merchant")
      expect(suggestion[:category_id]).to eq(category.id)

      # Verify patterns are created from feedback
      patterns = CategorizationPattern.where(category: category)
      expect(patterns.count).to be > 0
    end
  end

  describe "performance tracking" do
    it "tracks pattern performance over time" do
      pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test"
      )

      # Record multiple uses
      5.times { pattern.record_usage(true) }
      3.times { pattern.record_usage(false) }

      expect(pattern.usage_count).to eq(8)
      expect(pattern.success_count).to eq(5)
      expect(pattern.success_rate).to be_within(0.01).of(0.625)

      # Check effective confidence adjusts based on performance
      confidence = pattern.effective_confidence
      expect(confidence).to be < pattern.confidence_weight
    end
  end

  describe "database integrity" do
    it "maintains referential integrity with cascading deletes" do
      pattern = CategorizationPattern.create!(
        category: category,
        pattern_type: "merchant",
        pattern_value: "test"
      )

      feedback = PatternFeedback.create!(
        categorization_pattern: pattern,
        expense: expense,
        category: category,
        was_correct: true
      )

      composite = CompositePattern.create!(
        category: category,
        name: "Test composite",
        operator: "OR",
        pattern_ids: [ pattern.id ]
      )

      # Deleting category should cascade
      expect { category.destroy }.to change { CategorizationPattern.count }.by(-1)
                                  .and change { PatternFeedback.count }.by(-1)
                                  .and change { CompositePattern.count }.by(-1)
    end
  end

  describe "migration rollback safety" do
    it "verifies all tables exist with correct structure" do
      # Check all tables exist
      expect(ActiveRecord::Base.connection.table_exists?(:categorization_patterns)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:pattern_feedbacks)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:composite_patterns)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:canonical_merchants)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:merchant_aliases)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:pattern_learning_events)).to be true
      expect(ActiveRecord::Base.connection.table_exists?(:user_category_preferences)).to be true

      # Check expense columns were added
      expense_columns = Expense.column_names
      expect(expense_columns).to include(
        "merchant_normalized",
        "auto_categorized",
        "categorization_confidence",
        "categorization_method"
      )

      # Check indexes exist
      indexes = ActiveRecord::Base.connection.indexes(:categorization_patterns)
      expect(indexes.map(&:name)).to include("index_categorization_patterns_on_pattern_value")
    end
  end
end
