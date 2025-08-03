class Api::WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_token

  def process_emails
    email_account_id = params[:email_account_id]
    since = parse_since_parameter

    if email_account_id.present?
      ProcessEmailsJob.perform_later(email_account_id.to_i, since: since)
      render json: {
        status: "success",
        message: "Email processing queued for account #{email_account_id}",
        email_account_id: email_account_id
      }, status: :accepted
    else
      ProcessEmailsJob.perform_later(since: since)
      render json: {
        status: "success",
        message: "Email processing queued for all active accounts"
      }, status: :accepted
    end
  end

  def add_expense
    expense_params = params.require(:expense).permit(
      :amount, :description, :merchant_name, :transaction_date, :category_id
    )

    expense = Expense.new(expense_params)
    expense.email_account = default_email_account
    expense.status = "processed"

    if expense.save
      render json: {
        status: "success",
        message: "Expense created successfully",
        expense: format_expense(expense)
      }, status: :created
    else
      render json: {
        status: "error",
        message: "Failed to create expense",
        errors: expense.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  def recent_expenses
    limit = [ params[:limit].to_i, 50 ].min
    limit = 10 if limit <= 0

    expenses = Expense.includes(:category, :email_account)
                     .recent
                     .limit(limit)

    render json: {
      status: "success",
      expenses: expenses.map { |expense| format_expense(expense) }
    }
  end

  def expense_summary
    service = ExpenseSummaryService.new(params[:period])

    render json: {
      status: "success",
      period: service.period,
      summary: service.summary
    }
  end

  private

  def authenticate_api_token
    token = request.headers["Authorization"]&.remove("Bearer ")

    unless token.present?
      render json: { error: "Missing API token" }, status: :unauthorized
      return
    end

    @current_api_token = ApiToken.authenticate(token)

    unless @current_api_token
      render json: { error: "Invalid or expired API token" }, status: :unauthorized
      nil
    end
  end

  def parse_since_parameter
    since_param = params[:since]
    return 1.week.ago unless since_param.present?

    case since_param
    when /^\d+$/
      since_param.to_i.hours.ago
    when "today"
      Date.current.beginning_of_day
    when "yesterday"
      1.day.ago.beginning_of_day
    when "week"
      1.week.ago
    when "month"
      1.month.ago
    else
      begin
        Time.parse(since_param)
      rescue ArgumentError
        1.week.ago
      end
    end
  end

  def default_email_account
    # For manual entries, use the first active account or create a default one
    EmailAccount.active.first || create_default_manual_account
  end

  def create_default_manual_account
    EmailAccount.create!(
      provider: "manual",
      email: "manual@localhost",
      bank_name: "Manual Entry",
      active: true
    )
  end

  def format_expense(expense)
    {
      id: expense.id,
      amount: expense.amount.to_f,
      formatted_amount: expense.formatted_amount,
      description: expense.display_description,
      merchant_name: expense.merchant_name,
      transaction_date: expense.transaction_date.iso8601,
      category: expense.category_name,
      bank_name: expense.bank_name,
      status: expense.status,
      created_at: expense.created_at.iso8601
    }
  end
end
