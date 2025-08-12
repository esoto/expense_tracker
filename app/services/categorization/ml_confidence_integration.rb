# frozen_string_literal: true

module Categorization
  # Integrates ML confidence scores with the expense categorization system
  # This module provides methods to populate ML confidence fields when categorizing expenses
  module MlConfidenceIntegration
    extend ActiveSupport::Concern

    # Updates expense with ML confidence information from categorization result
    # @param expense [Expense] The expense to update
    # @param result [CategorizationResult] The categorization result
    # @return [Boolean] True if update successful
    def update_expense_with_ml_confidence(expense, result)
      return false unless result.successful?

      ml_attributes = build_ml_attributes(result)

      # If confidence is low, suggest the category instead of directly applying it
      if result.low_confidence? && !expense.category_id_changed?
        ml_attributes[:ml_suggested_category_id] = result.category.id
        ml_attributes.delete(:category_id)
      else
        ml_attributes[:category_id] = result.category.id
        ml_attributes[:ml_suggested_category_id] = nil
      end

      expense.update!(ml_attributes)
      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[MlConfidenceIntegration] Failed to update expense #{expense.id}: #{e.message}"
      false
    end

    # Builds attributes hash for ML confidence fields
    # @param result [CategorizationResult] The categorization result
    # @return [Hash] Attributes for updating expense
    def build_ml_attributes(result)
      {
        ml_confidence: result.confidence,
        ml_confidence_explanation: build_confidence_explanation(result),
        auto_categorized: true,
        categorization_confidence: result.confidence,
        categorization_method: result.method
      }
    end

    # Builds human-readable explanation of confidence score
    # @param result [CategorizationResult] The categorization result
    # @return [String] Explanation text
    def build_confidence_explanation(result)
      factors = []

      if result.confidence_breakdown.present?
        result.confidence_breakdown.each do |factor, details|
          case factor
          when :pattern_strength
            factors << "Patrón fuerte (#{(details[:value] * 100).round}%)"
          when :success_rate
            factors << "Tasa de éxito alta (#{(details[:value] * 100).round}%)"
          when :usage_count
            factors << "Patrón usado frecuentemente"
          when :composite_match
            factors << "Coincidencia múltiple"
          when :user_preference
            factors << "Preferencia del usuario"
          end
        end
      end

      if factors.empty?
        case result.confidence_level
        when :very_high, :high
          "Categorización con alta confianza basada en patrones establecidos"
        when :medium
          "Categorización con confianza media basada en patrones parciales"
        when :low, :very_low
          "Categorización con baja confianza - requiere revisión"
        else
          "Categorización automática"
        end
      else
        "Basado en: #{factors.join(', ')}"
      end
    end

    # Applies ML suggestion to expense (user accepted the suggestion)
    # @param expense [Expense] The expense to update
    # @return [Boolean] True if successful
    def apply_ml_suggestion(expense)
      return false unless expense.ml_suggested_category_id.present?

      expense.accept_ml_suggestion!

      # Track this as positive feedback for the pattern
      track_pattern_feedback(expense, true)

      true
    rescue => e
      Rails.logger.error "[MlConfidenceIntegration] Failed to apply ML suggestion: #{e.message}"
      false
    end

    # Rejects ML suggestion and applies user's correction
    # @param expense [Expense] The expense to update
    # @param correct_category_id [Integer] The correct category ID
    # @return [Boolean] True if successful
    def reject_ml_suggestion(expense, correct_category_id)
      return false unless correct_category_id.present?

      expense.reject_ml_suggestion!(correct_category_id)

      # Track this as negative feedback for the pattern
      track_pattern_feedback(expense, false)

      # Learn from the correction
      learn_from_correction(expense, correct_category_id)

      true
    rescue => e
      Rails.logger.error "[MlConfidenceIntegration] Failed to reject ML suggestion: #{e.message}"
      false
    end

    private

    # Tracks pattern feedback for learning
    def track_pattern_feedback(expense, was_correct)
      return unless defined?(PatternLearner)

      PatternLearner.new.record_feedback(
        expense: expense,
        was_correct: was_correct,
        confidence_score: expense.ml_confidence || 0.0
      )
    rescue => e
      Rails.logger.warn "[MlConfidenceIntegration] Failed to track pattern feedback: #{e.message}"
    end

    # Learns from user correction
    def learn_from_correction(expense, correct_category_id)
      return unless defined?(PatternLearner)

      PatternLearner.new.learn_from_correction(
        expense: expense,
        correct_category_id: correct_category_id,
        previous_category_id: expense.category_id_was
      )
    rescue => e
      Rails.logger.warn "[MlConfidenceIntegration] Failed to learn from correction: #{e.message}"
    end
  end
end
