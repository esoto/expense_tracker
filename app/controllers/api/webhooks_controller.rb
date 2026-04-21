class Api::WebhooksController < Api::BaseController
  # Inheriting from Api::BaseController gets us the canonical
  # authenticate_api_token (with locked-user check), @current_api_user
  # wiring, and error handlers — no duplicate auth code to drift.

  def process_emails
    email_account_id = params[:email_account_id]
    since = parse_since_parameter

    if email_account_id.present?
      # Validate that the requested email account belongs to the token's owner.
      account = @current_api_user.email_accounts.find_by(id: email_account_id.to_i)
      unless account
        render json: { error: "Email account not found or access denied", status: 404 }, status: :not_found
        return
      end

      ProcessEmailsJob.perform_later(account.id, since: since)
      render json: {
        status: "success",
        message: "Email processing queued for account #{account.id}",
        email_account_id: account.id
      }, status: :accepted
    else
      # No specific account — process ONLY the token owner's active accounts.
      # Pre-PR-11 this fell through to "all active accounts globally", which
      # let any valid token trigger processing for other users' mailboxes.
      owner_account_ids = @current_api_user.email_accounts.active.pluck(:id)
      if owner_account_ids.empty?
        render json: { error: "No active email accounts for this user", status: 404 }, status: :not_found
        return
      end
      owner_account_ids.each { |id| ProcessEmailsJob.perform_later(id, since: since) }
      render json: {
        status: "success",
        message: "Email processing queued for #{owner_account_ids.size} account(s)",
        email_account_ids: owner_account_ids
      }, status: :accepted
    end
  end

  def add_expense
    expense_params = params.require(:expense).permit(
      :amount, :description, :merchant_name, :transaction_date, :category_id
    )

    expense = Expense.new(expense_params)
    account = default_email_account
    expense.email_account = account
    expense.user = @current_api_user
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
  rescue ActiveRecord::RecordNotUnique
    # PER-498: return the existing row (idempotent) instead of a 500 when the
    # iPhone Shortcuts retries or a user double-taps. Scope the lookup by
    # email_account_id so we always return the row that the unique index
    # actually collided on — both the pre-existing idx_expenses_duplicate_check
    # (email_account_id IS NOT NULL) and the new idx_expenses_manual_duplicate_check
    # (email_account_id IS NULL) reduce to "a row with the same email_account_id
    # tuple." Matches either.
    existing = Expense.where(
      email_account_id: expense.email_account_id,
      amount: expense.amount,
      transaction_date: expense.transaction_date,
      merchant_name: expense.merchant_name,
      deleted_at: nil
    ).first

    if existing
      render json: {
        status: "success",
        message: "Expense already exists (idempotent retry)",
        expense: format_expense(existing)
      }, status: :ok
    else
      # Belt-and-braces: the unique-index predicate says the row must exist,
      # but if lookup doesn't find it (e.g. soft-deleted between the INSERT
      # attempt and this SELECT) return a 409 rather than a silent success.
      Rails.logger.warn "[WebhooksController] RecordNotUnique but existing row not found for expense params (#{expense.amount}, #{expense.transaction_date}, #{expense.merchant_name})"
      render json: {
        status: "error",
        message: "Duplicate detected but existing expense could not be located"
      }, status: :conflict
    end
  end

  def recent_expenses
    limit = [ params[:limit].to_i, 50 ].min
    limit = 10 if limit <= 0

    expenses = Expense.for_user(@current_api_user)
                     .includes(:category, :email_account)
                     .recent
                     .limit(limit)

    render json: {
      status: "success",
      expenses: expenses.map { |expense| format_expense(expense) }
    }
  end

  def expense_summary
    service = Services::ExpenseSummaryService.new(params[:period], user: @current_api_user)

    render json: {
      status: "success",
      period: service.period,
      summary: service.summary
    }
  end

  private

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
    # For manual entries, use the current user's first active account or create a default one
    @current_api_user.email_accounts.active.first || create_default_manual_account
  end

  def create_default_manual_account
    EmailAccount.create!(
      provider: "manual",
      email: "manual+#{@current_api_user.id}@localhost",
      bank_name: "Manual Entry",
      active: true,
      user: @current_api_user
    )
  end

  def format_expense(expense)
    {
      id: expense.id,
      amount: expense.amount.to_f,
      formatted_amount: expense.formatted_amount,
      description: expense.display_description,
      merchant_name: expense.display_merchant_name,
      transaction_date: expense.transaction_date.iso8601,
      category: expense.category_name,
      bank_name: expense.bank_name,
      status: expense.status,
      created_at: expense.created_at.iso8601
    }
  end
end
