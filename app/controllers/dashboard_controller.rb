class DashboardController < ApplicationController
  def show
    @period = params[:period].presence || "month"
    @primary_email_account = EmailAccount.active.first

    if @primary_email_account
      calculator_period = case @period
      when "month", "last_month", "quarter" then :month
      when "year" then :year
      else :month
      end

      reference_date = case @period
      when "last_month" then 1.month.ago.to_date
      else Date.current
      end

      month_result = Services::MetricsCalculator.new(
        email_account: @primary_email_account,
        period: calculator_period,
        reference_date: reference_date
      ).calculate

      @monthly_metrics = month_result[:metrics]
      @monthly_trends = month_result[:trends]
      @budgets = month_result[:budgets]
      @uncategorized_count = @monthly_metrics[:uncategorized_count]
      @daily_average = calculate_daily_average(@monthly_metrics[:total_amount])
    else
      @monthly_metrics = default_empty_metrics
      @monthly_trends = {}
      @budgets = {}
      @uncategorized_count = 0
      @daily_average = 0.0
    end

    # TODO: DashboardService queries are globally scoped (not per-account).
    # This mirrors the existing ExpensesController#dashboard behavior.
    # A follow-up ticket should scope all data to the selected account(s).
    dashboard_service = Services::DashboardService.new
    dashboard_data = dashboard_service.analytics

    # Category breakdown — top 10 for horizontal bar chart
    category_data = dashboard_data[:category_breakdown]
    @category_breakdown = category_data[:sorted]&.first(10) || []

    # Monthly trend — last 6 calendar months for line chart
    trend_data = dashboard_data[:monthly_trend] || {}
    @monthly_trend = trend_data.sort_by { |date, _| date }.last(6).to_h

    # Sync status — lightweight
    sync_sessions = dashboard_data[:sync_sessions] || {}
    @sync_status = {
      last_sync: sync_sessions[:last_completed]&.completed_at,
      active: sync_sessions[:active_session].present?
    }

    # Recent expenses — last 8, read-only
    @recent_expenses = Expense.includes(:category, :email_account)
                              .order(transaction_date: :desc, created_at: :desc)
                              .limit(8)

    # Actionable insights
    insights_service = Services::DashboardInsightsService.new(
      monthly_metrics: @monthly_metrics,
      monthly_trends: @monthly_trends,
      budgets: @budgets,
      uncategorized_count: @uncategorized_count,
      daily_average: @daily_average,
      category_breakdown: @category_breakdown
    )
    @insights = insights_service.insights
  end

  private

  def calculate_daily_average(month_total)
    return 0.0 if month_total.nil? || month_total.zero?

    days_elapsed = [ Date.current.day, 1 ].max
    (month_total / days_elapsed).round(2)
  end

  def default_empty_metrics
    {
      total_amount: 0.0,
      transaction_count: 0,
      average_amount: 0.0,
      median_amount: 0.0,
      min_amount: 0.0,
      max_amount: 0.0,
      unique_merchants: 0,
      unique_categories: 0,
      uncategorized_count: 0,
      by_status: {},
      by_currency: {}
    }
  end
end
