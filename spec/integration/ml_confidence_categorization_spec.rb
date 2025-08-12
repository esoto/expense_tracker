# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ML Confidence Categorization Integration', type: :integration do
  let(:expense) do
    create(:expense,
           description: 'Starbucks Coffee',
           merchant_name: 'Starbucks',
           merchant_normalized: 'starbucks',
           category: nil)
  end
  let(:food_category) { create(:category, name: 'Alimentación') }
  let(:pattern) do
    create(:categorization_pattern,
           category: food_category,
           pattern_type: 'merchant',
           pattern_value: 'starbucks',
           confidence_weight: 0.95,
           success_rate: 0.90)
  end

  before do
    pattern # Ensure pattern exists
    # Reset engine to clear any cached state
    reset_categorization_engine!
  end

  describe 'automatic categorization with ML confidence' do
    it 'updates ML fields when categorization result is applied' do
      # Create a mock successful categorization result
      result = Categorization::CategorizationResult.new(
        category: food_category,
        confidence: 0.85,
        method: 'pattern_match',
        patterns_used: [ 'merchant:starbucks' ],
        confidence_breakdown: {
          pattern_strength: { value: 0.85 }
        }
      )

      # Use the ML confidence integration directly
      integration = Class.new { include Categorization::MlConfidenceIntegration }.new

      expect(integration.update_expense_with_ml_confidence(expense, result)).to be true

      # Check that expense was updated with ML fields
      expense.reload
      expect(expense.ml_confidence).to eq(0.85)
      expect(expense.ml_confidence_explanation).to be_present
      expect(expense.categorization_method).to eq('pattern_match')
      expect(expense.categorization_confidence).to eq(0.85)
      expect(expense.category).to eq(food_category)
    end

    context 'with low confidence result' do
      it 'suggests category instead of directly applying when confidence is low' do
        # Create a mock low confidence result
        result = Categorization::CategorizationResult.new(
          category: food_category,
          confidence: 0.45,
          method: 'pattern_match'
        )

        # Use the ML confidence integration directly
        integration = Class.new { include Categorization::MlConfidenceIntegration }.new

        # Ensure expense has no category initially
        expense.update!(category: nil)

        expect(integration.update_expense_with_ml_confidence(expense, result)).to be true

        expense.reload

        # With low confidence, it should suggest rather than directly apply
        expect(expense.category).to be_nil
        expect(expense.ml_suggested_category_id).to eq(food_category.id)
        expect(expense.ml_confidence).to eq(0.45)
      end
    end
  end

  describe 'user feedback integration' do
    before do
      # Set up expense with ML suggestion
      expense.update!(
        ml_suggested_category_id: food_category.id,
        ml_confidence: 0.65,
        ml_confidence_explanation: 'Based on merchant pattern'
      )
    end

    it 'handles acceptance of ML suggestion' do
      expect {
        expense.accept_ml_suggestion!
      }.to change { expense.category }.from(nil).to(food_category)

      expect(expense.ml_confidence).to eq(1.0)
      expect(expense.ml_suggested_category_id).to be_nil
      expect(expense.ml_confidence_explanation).to include('confirmed')
    end

    it 'handles rejection of ML suggestion with correction' do
      transport_category = create(:category, name: 'Transporte')

      expect {
        expense.reject_ml_suggestion!(transport_category.id)
      }.to change { expense.category }.from(nil).to(transport_category)

      expect(expense.ml_confidence).to eq(1.0)
      expect(expense.ml_suggested_category_id).to be_nil
      expect(expense.ml_correction_count).to eq(1)
      expect(expense.ml_last_corrected_at).to be_present
    end
  end

  describe 'confidence levels' do
    it 'correctly identifies confidence levels' do
      test_cases = [
        { confidence: 0.95, expected_level: :high },
        { confidence: 0.75, expected_level: :medium },
        { confidence: 0.55, expected_level: :low },
        { confidence: 0.30, expected_level: :very_low },
        { confidence: nil, expected_level: :none }
      ]

      test_cases.each do |test_case|
        expense.ml_confidence = test_case[:confidence]
        expect(expense.confidence_level).to eq(test_case[:expected_level])
      end
    end

    it 'identifies expenses needing review' do
      expense.ml_confidence = 0.45
      expect(expense.needs_review?).to be true

      expense.ml_confidence = 0.85
      expect(expense.needs_review?).to be false
    end
  end
end
