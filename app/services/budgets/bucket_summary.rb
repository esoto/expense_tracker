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
    # Delegates to the shared Services::Budgets::DedupSpend so the same
    # dedup logic is used here and in BudgetsController#calculate_overall_budget_health.
    def dedup_spend(budgets)
      Services::Budgets::DedupSpend.call(budgets)
    end
  end
end
