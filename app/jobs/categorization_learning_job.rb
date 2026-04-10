# frozen_string_literal: true

# Background job that feeds the "silence = acceptance" signal into categorization vectors.
#
# Finds expenses categorized 24h+ ago that have NOT been corrected by the user,
# and upserts their merchant+category pairs into categorization_vectors so the
# similarity-based categorization layer can learn from them.
#
# Runs daily via Solid Queue recurring schedule.
#
# Usage:
#   CategorizationLearningJob.perform_now   # Run immediately
#   CategorizationLearningJob.perform_later # Enqueue for background execution
class CategorizationLearningJob < ApplicationJob
  queue_as :low

  ACCEPTANCE_THRESHOLD = 24.hours

  def perform
    Rails.logger.info "[CategorizationLearning] Starting daily learning sweep..."

    processed = 0

    qualifying_metrics.find_each do |metric|
      expense = metric.expense
      next unless expense.merchant_name? && expense.category.present?

      begin
        updater.upsert(
          merchant: expense.merchant_name,
          category: expense.category,
          description_keywords: extract_keywords(expense.description)
        )
        processed += 1
      rescue StandardError => e
        Rails.logger.warn "[CategorizationLearning] Failed for expense##{expense.id} " \
                          "(#{expense.merchant_name}): #{e.class}: #{e.message}"
      end
    end

    Rails.logger.info "[CategorizationLearning] Sweep complete: processed=#{processed}"
  end

  private

  def qualifying_metrics
    CategorizationMetric
      .uncorrected
      .where(created_at: ...ACCEPTANCE_THRESHOLD.ago)
      .includes(expense: :category)
      .where.not(expense_id: already_vectorized_expense_ids)
  end

  # Expense IDs whose merchant+category pair already exists in categorization_vectors.
  # This ensures idempotency — we don't re-upsert what we've already learned.
  def already_vectorized_expense_ids
    Expense
      .joins(:category)
      .where(
        "EXISTS (SELECT 1 FROM categorization_vectors cv " \
        "WHERE cv.merchant_normalized = expenses.merchant_normalized " \
        "AND cv.category_id = expenses.category_id)"
      )
      .select(:id)
  end

  def updater
    @updater ||= Services::Categorization::Learning::VectorUpdater.new
  end

  def extract_keywords(description)
    return [] if description.blank?

    description.downcase.split(/\s+/).uniq
  end
end
