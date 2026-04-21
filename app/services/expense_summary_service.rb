module Services
  class ExpenseSummaryService
  VALID_PERIODS = %w[week month year].freeze
  DEFAULT_PERIOD = "month".freeze

  def initialize(period = DEFAULT_PERIOD, user: nil)
    @period = normalize_period(period)
    @user = user
  end

  def summary
    case @period
    when "week"
      weekly_summary
    when "month"
      monthly_summary
    when "year"
      yearly_summary
    end
  end

  def period
    @period
  end

  private

  def normalize_period(period)
    VALID_PERIODS.include?(period) ? period : DEFAULT_PERIOD
  end

  def weekly_summary
    start_date = 1.week.ago.beginning_of_day
    end_date = Time.current.end_of_day

    build_summary(start_date, end_date)
  end

  def monthly_summary
    start_date = 1.month.ago.beginning_of_day
    end_date = Time.current.end_of_day

    build_summary(start_date, end_date)
  end

  def yearly_summary
    start_date = 1.year.ago.beginning_of_day
    end_date = Time.current.end_of_day

    summary = build_summary(start_date, end_date)
    summary[:monthly_breakdown] = monthly_breakdown_for_year(start_date, end_date)
    summary
  end

  def build_summary(start_date, end_date)
    {
      total_amount: total_amount_for_period(start_date, end_date),
      expense_count: expense_count_for_period(start_date, end_date),
      start_date: start_date.iso8601,
      end_date: end_date.iso8601,
      by_category: category_breakdown_for_period(start_date, end_date)
    }
  end

  def scoped_expenses
    # PR 11: raise on missing user rather than silently falling back to
    # Expense.all. The service is used from user-facing summary endpoints,
    # and a nil-user call was leaking cross-user totals. Callers must supply
    # user: current_user / current_api_user explicitly.
    raise ArgumentError, "user is required for ExpenseSummaryService" unless @user
    Expense.for_user(@user)
  end

  def total_amount_for_period(start_date, end_date)
    scoped_expenses.total_amount_for_period(start_date, end_date).to_f
  end

  def expense_count_for_period(start_date, end_date)
    scoped_expenses.by_date_range(start_date, end_date).count
  end

  def category_breakdown_for_period(start_date, end_date)
    scoped_expenses.joins(:category)
      .by_date_range(start_date, end_date)
      .group("categories.name")
      .sum(:amount)
      .transform_values(&:to_f)
  end

  def monthly_breakdown_for_year(start_date, end_date)
    scoped_expenses.by_date_range(start_date, end_date)
      .group_by_month(:transaction_date)
      .sum(:amount)
      .transform_values(&:to_f)
  end
  end
end
