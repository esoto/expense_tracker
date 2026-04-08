class DashboardController < ApplicationController
  def show
    @primary_email_account = EmailAccount.active.first

    if @primary_email_account
      month_result = Services::MetricsCalculator.new(
        email_account: @primary_email_account,
        period: :month,
        reference_date: Date.current
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

    dashboard_service = Services::DashboardService.new
    dashboard_data = dashboard_service.analytics

    # Category breakdown — top 10 for horizontal bar chart
    category_data = dashboard_data[:category_breakdown]
    @category_breakdown = category_data[:sorted]&.first(10) || []

    # Monthly trend — 6 months for line chart
    @monthly_trend = dashboard_data[:monthly_trend]

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
