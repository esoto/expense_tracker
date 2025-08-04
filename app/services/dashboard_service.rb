class DashboardService
  CACHE_EXPIRY = 5.minutes

  def initialize
  end

  def analytics
    # Don't cache sync_info as it needs real-time data
    sync_data = sync_info

    # Cache everything else
    cached_analytics = Rails.cache.fetch("dashboard_analytics", expires_in: CACHE_EXPIRY) do
      {
        totals: calculate_totals,
        recent_expenses: recent_expenses,
        category_breakdown: category_breakdown,
        monthly_trend: monthly_trend,
        bank_breakdown: bank_breakdown,
        top_merchants: top_merchants,
        email_accounts: active_email_accounts
      }
    end

    # Merge real-time sync info with cached data
    cached_analytics.merge(sync_info: sync_data)
  end

  # Add cache clearing
  def self.clear_cache
    Rails.cache.delete_matched("dashboard_*")
  end

  private

  def calculate_totals
    {
      total_expenses: Expense.sum(:amount),
      expense_count: Expense.count,
      current_month_total: current_month_total,
      last_month_total: last_month_total
    }
  end

  def current_month_total
    Expense.where(
      transaction_date: Date.current.beginning_of_month..Date.current.end_of_month
    ).sum(:amount)
  end

  def last_month_total
    Expense.where(
      transaction_date: 1.month.ago.beginning_of_month..1.month.ago.end_of_month
    ).sum(:amount)
  end

  def recent_expenses
    Expense.includes(:category, :email_account)  # Add :email_account to prevent N+1
           .order(transaction_date: :desc, created_at: :desc)
           .limit(10)
  end

  def category_breakdown
    category_totals = Expense.joins(:category)
                            .group("categories.name")
                            .sum(:amount)
                            .transform_values(&:to_f)

    {
      totals: category_totals,
      sorted: category_totals.sort_by { |_, amount| -amount }
    }
  end

  def monthly_trend
    Expense.where(
      transaction_date: 6.months.ago.beginning_of_month..Date.current.end_of_month
    ).group_by_month(:transaction_date)
     .sum(:amount)
     .transform_values(&:to_f)
  end

  def bank_breakdown
    Expense.group(:bank_name)
           .sum(:amount)
           .sort_by { |_, amount| -amount }
  end

  def top_merchants
    Expense.group(:merchant_name)
           .sum(:amount)
           .sort_by { |_, amount| -amount }
           .first(10)
  end

  def active_email_accounts
    EmailAccount.active.order(:bank_name, :email)
  end

  def sync_info
    # Single query approach to avoid N+1
    sync_data = EmailAccount.active
      .left_joins(:expenses)
      .group(:id)
      .select("email_accounts.*, MAX(expenses.created_at) as last_expense_created")
      .index_by(&:id)
      .transform_values do |account|
        {
          last_sync: account.last_expense_created,
          account: account
        }
      end

    # Check for running jobs
    running_jobs = SolidQueue::Job.where(
      class_name: "ProcessEmailsJob",
      finished_at: nil
    ).where("created_at > ?", 5.minutes.ago)

    sync_data[:has_running_jobs] = running_jobs.exists?
    sync_data[:running_job_count] = running_jobs.count

    sync_data
  end
end
