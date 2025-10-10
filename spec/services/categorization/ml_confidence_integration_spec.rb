# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Categorization::MlConfidenceIntegration do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include Categorization::MlConfidenceIntegration
    end
  end

  let(:integration) { test_class.new }
  let(:expense) { create(:expense) }
  let(:category) { create(:category) }

  describe '#update_expense_with_ml_confidence' do
    let(:result) do
      Categorization::CategorizationResult.new(
        category: category,
        confidence: confidence,
        method: 'pattern_match',
        patterns_used: [ 'merchant:Test Store' ],
        confidence_breakdown: {
          pattern_strength: { value: 0.8, contribution: 0.4 },
          success_rate: { value: 0.9, contribution: 0.3 }
        }
      )
    end

    context 'with high confidence' do
      let(:confidence) { 0.90 }

      it 'updates expense with category and ML fields' do
        expect(integration.update_expense_with_ml_confidence(expense, result)).to be true

        expense.reload
        expect(expense.category).to eq(category)
        expect(expense.ml_confidence).to eq(0.90)
        expect(expense.ml_confidence_explanation).to include('Patrón fuerte')
        expect(expense.categorization_method).to eq('pattern_match')
        expect(expense.ml_suggested_category_id).to be_nil
      end
    end

    context 'with low confidence' do
      let(:confidence) { 0.45 }

      it 'suggests the category instead of directly applying it' do
        # Ensure expense starts without a category
        expense.update!(category: nil)

        expect(integration.update_expense_with_ml_confidence(expense, result)).to be true

        expense.reload
        expect(expense.category).to be_nil # Should not update category directly
        expect(expense.ml_suggested_category_id).to eq(category.id)
        expect(expense.ml_confidence).to eq(0.45)
      end
    end

    context 'with unsuccessful result' do
      let(:result) { Categorization::CategorizationResult.no_match }

      it 'returns false and does not update expense' do
        expect(integration.update_expense_with_ml_confidence(expense, result)).to be false

        expense.reload
        expect(expense.ml_confidence).to be_nil
      end
    end
  end

  describe '#build_confidence_explanation' do
    context 'with confidence breakdown' do
      let(:result) do
        Categorization::CategorizationResult.new(
          category: category,
          confidence: 0.85,
          confidence_breakdown: {
            pattern_strength: { value: 0.9 },
            success_rate: { value: 0.85 },
            usage_count: { value: 100 }
          }
        )
      end

      it 'builds explanation from factors' do
        explanation = integration.build_confidence_explanation(result)
        expect(explanation).to include('Patrón fuerte (90%)')
        expect(explanation).to include('Tasa de éxito alta (85%)')
        expect(explanation).to include('Patrón usado frecuentemente')
      end
    end

    context 'without confidence breakdown' do
      let(:result) do
        Categorization::CategorizationResult.new(
          category: category,
          confidence: confidence
        )
      end

      context 'with high confidence' do
        let(:confidence) { 0.90 }

        it 'returns high confidence message' do
          explanation = integration.build_confidence_explanation(result)
          expect(explanation).to eq('Categorización con alta confianza basada en patrones establecidos')
        end
      end

      context 'with low confidence' do
        let(:confidence) { 0.40 }

        it 'returns low confidence message' do
          explanation = integration.build_confidence_explanation(result)
          expect(explanation).to eq('Categorización con baja confianza - requiere revisión')
        end
      end
    end
  end

  describe '#apply_ml_suggestion' do
    before do
      expense.update!(
        ml_suggested_category_id: category.id,
        ml_confidence: 0.75
      )
    end

    it 'accepts the ML suggestion' do
      expect(integration.apply_ml_suggestion(expense)).to be true

      expense.reload
      expect(expense.category).to eq(category)
      expect(expense.ml_suggested_category_id).to be_nil
      expect(expense.ml_confidence).to eq(1.0)
    end

    context 'when no suggestion exists' do
      before { expense.update!(ml_suggested_category_id: nil) }

      it 'returns false' do
        expect(integration.apply_ml_suggestion(expense)).to be false
      end
    end
  end

  describe '#reject_ml_suggestion' do
    let(:correct_category) { create(:category, name: 'Correct Category') }

    before do
      expense.update!(
        category: category,
        ml_suggested_category_id: category.id,
        ml_confidence: 0.75
      )
    end

    it 'rejects suggestion and applies correct category' do
      expect(integration.reject_ml_suggestion(expense, correct_category.id)).to be true

      expense.reload
      expect(expense.category).to eq(correct_category)
      expect(expense.ml_suggested_category_id).to be_nil
      expect(expense.ml_confidence).to eq(1.0)
      expect(expense.ml_correction_count).to eq(1)
    end

    context 'when category_id is nil' do
      it 'returns false' do
        expect(integration.reject_ml_suggestion(expense, nil)).to be false
      end
    end
  end
end
