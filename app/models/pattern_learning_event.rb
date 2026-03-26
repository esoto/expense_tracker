# frozen_string_literal: true

class PatternLearningEvent < ApplicationRecord
  belongs_to :expense
  belongs_to :category

  validates :pattern_used, presence: true
  validates :was_correct, inclusion: { in: [ true, false ] }
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true

  scope :successful, -> { where(was_correct: true) }
  scope :unsuccessful, -> { where(was_correct: false) }
  scope :recent, -> { order(created_at: :desc) }

  after_commit :invalidate_analytics_cache

  # Class method to record learning events
  def self.record_event(expense:, category:, pattern:, was_correct:, confidence: nil)
    pattern_name = case pattern
    when CategorizationPattern
                     "#{pattern.pattern_type}:#{pattern.pattern_value}"
    when CompositePattern
                     "composite:#{pattern.name}"
    else
                     pattern.to_s
    end

    create!(
      expense: expense,
      category: category,
      pattern_used: pattern_name,
      was_correct: was_correct,
      confidence_score: confidence,
      context_data: {
        pattern_id: pattern&.id,
        pattern_class: pattern&.class&.name
      }
    )
  end

  # Check if this event indicates success
  def successful?
    was_correct == true
  end

  private

  def invalidate_analytics_cache
    # Atomically bump the shared analytics version key.  The analytics
    # controller embeds this value in every cache key, so any entry written
    # with the previous version becomes unreachable — no delete_matched needed.
    if Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)
      current = Rails.cache.read(Analytics::PatternDashboardController::ANALYTICS_VERSION_KEY) || 0
      Rails.cache.write(Analytics::PatternDashboardController::ANALYTICS_VERSION_KEY, current + 1)
    else
      Rails.cache.increment(Analytics::PatternDashboardController::ANALYTICS_VERSION_KEY, 1, initial: 1) ||
        Rails.cache.write(Analytics::PatternDashboardController::ANALYTICS_VERSION_KEY, 1)
    end
  rescue => e
    Rails.logger.error "[PatternLearningEvent] Analytics cache invalidation failed: #{e.message}"
  end
end
