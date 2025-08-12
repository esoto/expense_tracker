class Expense < ApplicationRecord
  # Associations
  belongs_to :email_account
  belongs_to :category, optional: true
  has_many :pattern_feedbacks, dependent: :destroy
  has_many :pattern_learning_events, dependent: :destroy

  # Enums
  enum :currency, { crc: 0, usd: 1, eur: 2 }

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_date, presence: true
  validates :status, presence: true, inclusion: { in: [ "pending", "processed", "failed", "duplicate" ] }
  validates :currency, presence: true

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
end
