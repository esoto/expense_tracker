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

  # Callbacks
  after_commit :clear_dashboard_cache

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

  def clear_dashboard_cache
    DashboardService.clear_cache
  end
end
