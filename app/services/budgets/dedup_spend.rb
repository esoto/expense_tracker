# frozen_string_literal: true

# Computes total spend across a collection of budgets without double-counting
# an expense claimed by more than one budget (e.g., two active budgets that
# both claim the same category).
#
# For each budget, collect the ids of matching expenses:
#   1. expenses.budget_id = budget.id always counts (override).
#   2. expenses.budget_id IS NULL AND category IN budget's claimed categories
#      counts (default routing).
# scoped to that budget's own period range, currency, and email_account.
# Then union the ids across all budgets and sum each expense exactly once.
module Services::Budgets
  class DedupSpend
    def self.call(budgets)
      new(budgets).call
    end

    def initialize(budgets)
      @budgets = budgets
    end

    def call
      budgets = Array(@budgets)
      return 0.0 if budgets.empty?

      expense_ids = budgets.flat_map { |budget| matching_expense_ids(budget) }.uniq
      return 0.0 if expense_ids.empty?

      Expense.where(id: expense_ids).sum(:amount).to_f
    end

    private

    def matching_expense_ids(budget)
      range = budget.current_period_range
      currency_enum = currency_to_expense_currency(budget.currency)

      base = budget.email_account.expenses
        .where(transaction_date: range)
        .where(currency: currency_enum)

      conditions = [ "expenses.budget_id = :bid" ]
      bindings = { bid: budget.id }

      claimed = claimed_category_ids_by_budget[budget.id] || []
      if claimed.any?
        conditions << "(expenses.budget_id IS NULL AND expenses.category_id IN (:cats))"
        bindings[:cats] = claimed
      end

      base.where(conditions.join(" OR "), bindings).pluck(:id)
    end

    # Batch-load claimed category ids for all budgets in a single query
    # instead of calling budget.category_ids per budget (avoids an N+1
    # against the budget_categories/categories tables).
    def claimed_category_ids_by_budget
      @claimed_category_ids_by_budget ||= BudgetCategory
        .where(budget_id: Array(@budgets).map(&:id))
        .pluck(:budget_id, :category_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(bid, cid), acc| acc[bid] << cid }
    end

    def currency_to_expense_currency(code)
      case code
      when "CRC" then Expense.currencies[:crc]
      when "USD" then Expense.currencies[:usd]
      when "EUR" then Expense.currencies[:eur]
      else Expense.currencies[:crc]
      end
    end
  end
end
