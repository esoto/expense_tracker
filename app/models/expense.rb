class Expense < ApplicationRecord
  include ExpenseQueryOptimizer
  include QuerySecurity
  include SoftDelete

  # Associations
  belongs_to :email_account, optional: true
  belongs_to :category, optional: true
  belongs_to :ml_suggested_category, class_name: "Category", foreign_key: "ml_suggested_category_id", optional: true
  has_many :pattern_feedbacks, dependent: :destroy
  has_many :pattern_learning_events, dependent: :destroy
  has_many :bulk_operation_items, dependent: :destroy

  # Enums
  enum :currency, { crc: 0, usd: 1, eur: 2 }
  enum :status, { pending: 0, processed: 1, failed: 2, duplicate: 3 }

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_date, presence: true
  validates :status, presence: true
  validates :currency, presence: true
  validate :category_exists_if_provided

  # Callbacks
  before_save :normalize_merchant_name
  after_commit :clear_dashboard_cache
  after_commit :trigger_metrics_refresh, on: [ :create, :update ]
  after_commit :trigger_metrics_refresh_for_deletion, on: [ :update ], if: :saved_change_to_deleted_at?

  # Scopes
  scope :recent, -> { order(transaction_date: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_date_range, ->(start_date, end_date) { where(transaction_date: start_date..end_date) }
  scope :by_amount_range, ->(min, max) { where(amount: min..max) }
  scope :uncategorized, -> { where(category: nil) }
  scope :this_month, -> { where(transaction_date: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :this_year, -> { where(transaction_date: Date.current.beginning_of_year..Date.current.end_of_year) }

  # Instance methods
  def formatted_amount
    symbol = crc? ? "₡" : (usd? ? "$" : "€")
    "#{symbol}#{amount.to_f.round(2)}"
  end

  def bank_name
    value = self[:bank_name]
    return value if value.present?

    email_account&.bank_name || "Manual"
  end

  def category_name
    category&.name || "Uncategorized"
  end

  def display_description
    description.presence || merchant_name.presence || "Unknown Transaction"
  end

  def merchant_name
    # Simple attribute access without computed logic to avoid circular dependencies
    # Returns merchant_name if present, otherwise merchant_normalized
    self[:merchant_name] || self[:merchant_normalized]
  end

  def parsed_email_data
    return {} unless parsed_data.present?
    JSON.parse(parsed_data)
  rescue JSON::ParserError
    {}
  end

  def parsed_email_data=(hash)
    self.parsed_data = hash.to_json
  end

  # ML Confidence methods
  def confidence_level
    return :none if ml_confidence.nil?
    return :high if ml_confidence >= 0.85
    return :medium if ml_confidence >= 0.70
    return :low if ml_confidence >= 0.50
    :very_low
  end

  def confidence_percentage
    return 0 if ml_confidence.nil?
    (ml_confidence * 100).round
  end

  def needs_review?
    confidence_level == :low || confidence_level == :very_low
  end

  # Check if expense is locked from editing (can be expanded with business rules)
  def locked?
    # For now, no expenses are locked. This can be extended based on business rules
    # e.g., expenses older than 90 days, reconciled expenses, etc.
    false
  end

  def accept_ml_suggestion!
    return false unless ml_suggested_category_id.present?

    transaction do
      # Track the correction
      self.ml_correction_count = (ml_correction_count || 0) + 1
      self.ml_last_corrected_at = Time.current

      # Apply the suggestion
      self.category_id = ml_suggested_category_id
      self.ml_suggested_category_id = nil

      # Update confidence
      self.ml_confidence = 1.0
      self.ml_confidence_explanation = "Manually confirmed by user"

      save!
    end
  end

  def reject_ml_suggestion!(new_category_id)
    transaction do
      # Track the correction
      self.ml_correction_count = (ml_correction_count || 0) + 1
      self.ml_last_corrected_at = Time.current

      # Apply the new category
      self.category_id = new_category_id
      self.ml_suggested_category_id = nil

      # Update confidence
      self.ml_confidence = 1.0
      self.ml_confidence_explanation = "Manually corrected by user"

      # Create learning event for pattern improvement
      pattern_learning_events.create!(
        category_id: new_category_id,
        pattern_used: "manual_correction",
        was_correct: true,
        confidence_score: 1.0,
        context_data: {
          previous_category_id: category_id_was,
          merchant: merchant_name,
          description: description
        }
      )

      save!
    end
  end

  # Class methods
  def self.total_amount_for_period(start_date, end_date)
    by_date_range(start_date, end_date).sum(:amount)
  end

  def self.by_category_summary
    joins(:category)
      .group("categories.name")
      .sum(:amount)
      .transform_keys { |key| key || "Uncategorized" }
  end

  def self.monthly_summary
    group_by_month(:transaction_date, last: 12).sum(:amount)
  end

  private

  def category_exists_if_provided
    if category_id.present? && !Category.exists?(category_id)
      errors.add(:category, "must exist")
    end
  end

  def clear_dashboard_cache
    Services::DashboardService.clear_cache
  end

  def trigger_metrics_refresh
    # Smart refresh - only trigger if significant fields changed
    if saved_change_to_amount? || saved_change_to_transaction_date? ||
       saved_change_to_category_id? || saved_change_to_status?

      # Schedule metrics refresh with debouncing
      if saved_change_to_transaction_date? && transaction_date_before_last_save.present?
        # Transaction date actually changed (not creation) - refresh both old and new dates
        MetricsRefreshJob.enqueue_debounced(
          email_account_id,
          affected_date: transaction_date_before_last_save,
          delay: 3.seconds
        )
        MetricsRefreshJob.enqueue_debounced(
          email_account_id,
          affected_date: transaction_date,
          delay: 3.seconds
        )
      else
        # Creation or other field changes - refresh current transaction date
        MetricsRefreshJob.enqueue_debounced(
          email_account_id,
          affected_date: transaction_date,
          delay: 3.seconds
        )
      end
    end
  rescue StandardError => e
    # Don't let background job issues affect the main transaction
    Rails.logger.error "Failed to trigger metrics refresh: #{e.message}"
  end

  def trigger_metrics_refresh_for_deletion
    # Trigger metrics refresh for the deleted expense's date
    MetricsRefreshJob.enqueue_debounced(
      email_account_id,
      affected_date: transaction_date,
      delay: 3.seconds
    )
  rescue StandardError => e
    Rails.logger.error "Failed to trigger metrics refresh after deletion: #{e.message}"
  end

  def normalize_merchant_name
    self.merchant_normalized = normalized_merchant_value
  end

  def normalized_merchant_value
    return nil if self[:merchant_name].blank?

    # Normalize merchant name for search:
    # - Convert to lowercase
    # - Remove special characters except spaces and alphanumeric
    # - Compress multiple spaces to single space
    # - Strip leading/trailing whitespace
    self[:merchant_name].downcase
                 .gsub(/[^\w\s]/, " ")
                 .squeeze(" ")
                 .strip
  end
end
