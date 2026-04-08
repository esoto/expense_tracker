# frozen_string_literal: true

module Services
  # Pure calculation service that produces actionable insight cards
  # for the dashboard. Takes already-prepared data — no DB queries.
  class DashboardInsightsService
    MAX_INSIGHTS = 3
    SEVERITY_ORDER = { warning: 0, info: 1 }.freeze

    def initialize(monthly_metrics:, monthly_trends:, budgets:, uncategorized_count:, daily_average:, category_breakdown:)
      @monthly_metrics = monthly_metrics
      @monthly_trends = monthly_trends
      @budgets = budgets
      @uncategorized_count = uncategorized_count
      @daily_average = daily_average
      @category_breakdown = category_breakdown
    end

    def insights
      all_insights = []

      all_insights << spending_velocity_insight if @budgets[:has_budget]
      all_insights << uncategorized_items_insight if @uncategorized_count.positive?

      all_insights
        .compact
        .sort_by { |i| SEVERITY_ORDER.fetch(i[:severity], 99) }
        .first(MAX_INSIGHTS)
    end

    private

    def spending_velocity_insight
      month_total = @monthly_metrics[:total_amount].to_f
      budget_amount = @budgets[:total_budget_amount].to_f
      budget_amount = @budgets[:amount].to_f if budget_amount.zero? && @budgets.key?(:amount)
      days_elapsed = [ Date.current.day, 1 ].max
      days_in_month = Date.current.end_of_month.day
      projected_spend = (month_total / days_elapsed) * days_in_month

      if projected_spend > budget_amount
        excess = projected_spend - budget_amount
        {
          type: :spending_velocity,
          severity: :warning,
          icon: "⚠️",
          message: "Projected to exceed budget by ₡#{format_number(excess)}",
          link_path: nil
        }
      else
        {
          type: :spending_velocity,
          severity: :info,
          icon: "✅",
          message: "On track to stay within budget",
          link_path: nil
        }
      end
    end

    def uncategorized_items_insight
      {
        type: :uncategorized_items,
        severity: :info,
        icon: "🏷️",
        message: "#{@uncategorized_count} expenses need categorization",
        link_path: nil
      }
    end

    def format_number(amount)
      whole = amount.round(0).to_i
      whole.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
    end
  end
end
