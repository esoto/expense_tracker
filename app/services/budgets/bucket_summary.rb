# frozen_string_literal: true

# Aggregates active budgets in an email_account by salary_bucket.
# Dedupes spend via DISTINCT expense_id so overlapping budgets that
# claim the same category don't inflate the bucket total.
module Services::Budgets
  class BucketSummary
    Bucket = Struct.new(:key, :label, :budgeted, :spent, :remaining, :budget_count, keyword_init: true)

    def initialize(email_account)
      @email_account = email_account
    end

    def call
      return [] unless @email_account

      bucketed = @email_account.budgets.active.current.where.not(salary_bucket: nil)
      return [] if bucketed.none?

      grouped = bucketed.group_by(&:salary_bucket)

      Budget.salary_buckets.keys.filter_map do |key|
        rows = grouped[key]
        next if rows.blank?
        build_bucket(key, rows)
      end
    end

    private

    def build_bucket(key, budgets)
      budgeted = budgets.sum(&:amount).to_f
      spent = dedup_spend(budgets)

      Bucket.new(
        key: key,
        label: I18n.t("budgets.salary_buckets.#{key}"),
        budgeted: budgeted,
        spent: spent,
        remaining: budgeted - spent,
        budget_count: budgets.size
      )
    end

    # Per-budget accurate routing, then union expense ids, then sum once.
    def dedup_spend(budgets)
      expense_ids = budgets.flat_map do |b|
        range = b.current_period_range
        currency_enum = currency_to_expense_currency(b.currency)
        base = @email_account.expenses
          .where(transaction_date: range)
          .where(currency: currency_enum)

        conditions = [ "expenses.budget_id = :bid" ]
        bindings = { bid: b.id }

        if b.category_ids.any?
          conditions << "(expenses.budget_id IS NULL AND expenses.category_id IN (:cats))"
          bindings[:cats] = b.category_ids
        end

        base.where(conditions.join(" OR "), bindings).pluck(:id)
      end.uniq

      return 0.0 if expense_ids.empty?
      @email_account.expenses.where(id: expense_ids).sum(:amount).to_f
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
