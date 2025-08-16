class Expense < ApplicationRecord
  include ExpenseQueryOptimizer
  include QuerySecurity

  # Associations
  belongs_to :email_account
  belongs_to :category, optional: true
  belongs_to :ml_suggested_category, class_name: "Category", foreign_key: "ml_suggested_category_id", optional: true
  has_many :pattern_feedbacks, dependent: :destroy
  has_many :pattern_learning_events, dependent: :destroy
  has_many :bulk_operation_items, dependent: :destroy

  # Enums
  enum :currency, { crc: 0, usd: 1, eur: 2 }

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_date, presence: true
  validates :status, presence: true, inclusion: { in: [ "pending", "processed", "failed", "duplicate" ] }
  validates :currency, presence: true

  # Callbacks
  before_save :normalize_merchant_name

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
    email_account.bank_name
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

  def duplicate?
    status == "duplicate"
  end

  def processed?
    status == "processed"
  end

  def pending?
    status == "pending"
  end

  def failed?
    status == "failed"
  end

  # Currency detection methods (replacing CurrencyDetectorService)
  def detect_and_set_currency(email_content = nil)
    detected = detect_currency(email_content)
    self.currency = detected
    save if persisted?
    detected
  end

  def detect_currency(email_content = nil)
    text = build_currency_detection_text(email_content)

    if text.match?(/\$|usd|dollar/i)
      "usd"
    elsif text.match?(/€|eur|euro/i)
      "eur"
    else
      "crc" # Default for Costa Rican banks
    end
  end

  private

  def build_currency_detection_text(email_content)
    [
      email_content,
      description,
      merchant_name,
      parsed_data
    ].compact.join(" ").downcase
  end

  public

  # Category guessing methods (replacing CategoryGuesserService)
  def guess_category
    text = [ description, merchant_name ].compact.join(" ").downcase
    return nil if text.blank?

    category_keywords = {
      "Alimentación" => %w[restaurant restaurante comida food super supermercado grocery mercado],
      "Transporte" => %w[gasolina gas combustible uber taxi transporte],
      "Servicios" => %w[electricidad agua telefono internet cable servicio],
      "Entretenimiento" => %w[cine movie teatro entertainment entretenimiento],
      "Salud" => %w[farmacia medicina doctor hospital clinica salud],
      "Compras" => %w[tienda store compra shopping mall centro comercial]
    }

    category_keywords.each do |category_name, keywords|
      if keywords.any? { |keyword| text.include?(keyword) }
        return Category.find_by(name: category_name)
      end
    end

    # Try default categories
    Category.find_by(name: "Sin Categoría") || Category.find_by(name: "Other")
  end

  def auto_categorize!
    if category.nil?
      self.category = guess_category
      save if changed?
    end
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

  # Callbacks
  after_commit :clear_dashboard_cache
  after_commit :trigger_metrics_refresh, on: [ :create, :update ]
  after_destroy :trigger_metrics_refresh_for_deletion

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

  # Expense summary methods (replacing ExpenseSummaryService)
  def self.summary_for_period(period = "month")
    case period.to_s
    when "week"
      weekly_summary
    when "month"
      monthly_summary_report
    when "year"
      yearly_summary
    else
      monthly_summary_report
    end
  end

  def self.weekly_summary
    start_date = 1.week.ago.beginning_of_day
    end_date = Time.current.end_of_day
    build_summary(start_date, end_date)
  end

  def self.monthly_summary_report
    start_date = 1.month.ago.beginning_of_day
    end_date = Time.current.end_of_day
    build_summary(start_date, end_date)
  end

  def self.yearly_summary
    start_date = 1.year.ago.beginning_of_day
    end_date = Time.current.end_of_day
    summary = build_summary(start_date, end_date)
    summary[:monthly_breakdown] = by_date_range(start_date, end_date)
                                    .group_by_month(:transaction_date)
                                    .sum(:amount)
                                    .transform_values(&:to_f)
    summary
  end

  def self.build_summary(start_date, end_date)
    expenses = by_date_range(start_date, end_date)

    {
      total_amount: expenses.sum(:amount).to_f,
      expense_count: expenses.count,
      start_date: start_date.iso8601,
      end_date: end_date.iso8601,
      by_category: expenses.joins(:category)
                          .group("categories.name")
                          .sum(:amount)
                          .transform_values(&:to_f)
    }
  end

  private

  def clear_dashboard_cache
    DashboardService.clear_cache
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

  private

  def normalize_merchant_name
    if merchant_name.present? && merchant_normalized != normalized_merchant_value
      self.merchant_normalized = normalized_merchant_value
    end
  end

  def normalized_merchant_value
    return nil if merchant_name.blank?

    # Normalize merchant name for search:
    # - Convert to lowercase
    # - Remove special characters except spaces and alphanumeric
    # - Compress multiple spaces to single space
    # - Strip leading/trailing whitespace
    merchant_name.downcase
                 .gsub(/[^\w\s]/, " ")
                 .squeeze(" ")
                 .strip
  end
end
