# frozen_string_literal: true

module Services
  module ExternalBudgets
    # Drives one pull-sync cycle for an ExternalBudgetSource:
    # 1. Fetch the current monthly budget (honoring If-Modified-Since).
    # 2. Upsert each budget item as a local Budget row keyed by
    #    (external_source, external_id); assign_attributes never touches
    #    category_id or active, so user mappings survive re-syncs.
    # 3. Deactivate any previously-synced Budget rows that are no longer
    #    present in the upstream response.
    # 4. Mark the source as succeeded on any non-error terminal state
    #    (200, 304, 404 — all mean "we reached the server successfully").
    #
    # Error policy:
    # - UnauthorizedError → deactivate! (permanent, user must re-link)
    # - ServerError / NetworkError → re-raise for job-layer retry
    # - NotFoundError → silent success (no MonthlyBudget for this month yet)
    class SyncService
      SOURCE_KEY = "salary_calculator"

      def initialize(source:)
        @source = source
      end

      def call
        result = ApiClient.new(source: @source).fetch_current_budget(
          if_modified_since: @source.last_synced_at
        )
        apply_payload(result.body) if result.ok?
        @source.mark_succeeded!
        true
      rescue ApiClient::NotFoundError
        @source.mark_succeeded!
        true
      rescue ApiClient::UnauthorizedError => e
        @source.deactivate!(reason: "unauthorized: #{e.message.to_s.truncate(200)}")
        false
      end

      private

      def apply_payload(body)
        monthly = body.fetch("monthly_budget")
        items   = body.fetch("budget_items", [])
        period_start = Date.new(monthly.fetch("year").to_i, monthly.fetch("month").to_i, 1)
        period_end   = period_start.end_of_month
        account = @source.email_account
        present_ids = items.map { |i| i.fetch("id") }

        ActiveRecord::Base.transaction do
          items.each { |item| upsert_budget(account, item, period_start, period_end) }
          account.budgets
            .where(external_source: SOURCE_KEY)
            .where.not(external_id: present_ids)
            .update_all(active: false)
        end
      end

      def upsert_budget(account, item, period_start, period_end)
        budget = account.budgets.find_or_initialize_by(
          external_source: SOURCE_KEY,
          external_id: item.fetch("id")
        )
        budget.assign_attributes(
          name: item.fetch("name"),
          amount: item.fetch("amount"),
          currency: item.fetch("currency"),
          period: :monthly,
          start_date: period_start,
          end_date: period_end,
          external_synced_at: Time.current
        )
        budget.active = true if budget.new_record?
        budget.save!
      end
    end
  end
end
