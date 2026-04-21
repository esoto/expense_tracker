# frozen_string_literal: true

module Services
  module ExternalBudgets
    # Drives one pull-sync cycle for an ExternalBudgetSource:
    # 1. Fetch the current monthly budget (honoring If-Modified-Since).
    # 2. Upsert each budget item as a local Budget row keyed by
    #    (email_account_id, external_source, external_id, start_date); assign_attributes
    #    never touches category_id, so user mappings survive re-syncs.
    # 3. Deactivate any previously-synced Budget rows from prior months, and any
    #    current-month external rows that are no longer present upstream.
    # 4. Mark the source as succeeded on any non-error terminal state
    #    (200, 304, 404 — all mean "we reached the server successfully").
    #
    # Error policy:
    # - UnauthorizedError → deactivate! (permanent, user must re-link)
    # - InvalidPayload (bad data from upstream) → record_failure! and return false
    # - ServerError / NetworkError → record_failure! and re-raise for job-layer retry
    # - NotFoundError → silent success (no MonthlyBudget for this month yet)
    class SyncService
      SOURCE_KEY = "salary_calculator"
      ALLOWED_CURRENCIES = %w[CRC USD EUR].freeze

      class InvalidPayload < StandardError; end

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
      rescue InvalidPayload => e
        @source.record_failure!(error: e.message)
        false
      rescue ApiClient::ServerError, ApiClient::NetworkError => e
        @source.record_failure!(error: "#{e.class.name}: #{e.message.to_s.truncate(200)}")
        raise
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
          # Deactivate any external rows from prior/other months FIRST — only the
          # current period should remain active after a successful sync. This
          # must happen before upserts to avoid clashing with the Budget model's
          # "one active budget per (period, category)" validation when the same
          # external_id appears across months.
          account.budgets
            .where(external_source: SOURCE_KEY)
            .where.not(start_date: period_start)
            .update_all(active: false)

          # Deactivate any current-month external rows that dropped out of the
          # upstream response. If the response is empty, deactivate them all.
          scope = account.budgets
            .where(external_source: SOURCE_KEY, start_date: period_start)
          scope = scope.where.not(external_id: present_ids) if present_ids.any?
          scope.update_all(active: false)

          items.each { |item| upsert_budget(account, item, period_start, period_end) }
        end
      end

      def upsert_budget(account, item, period_start, period_end)
        currency = item.fetch("currency").to_s.upcase
        unless ALLOWED_CURRENCIES.include?(currency)
          raise InvalidPayload, "unsupported currency=#{currency.inspect} for item id=#{item['id']}"
        end

        budget = account.budgets.find_or_initialize_by(
          external_source: SOURCE_KEY,
          external_id: item.fetch("id"),
          start_date: period_start
        )
        # FIXME(PR-6b): user is derived from email_account.user here because
        # ExternalBudgets::SyncService has no direct authenticated user context.
        # This is the same pattern used by WebhooksController in PR 5.
        budget.user ||= account.user
        budget.assign_attributes(
          name: item.fetch("name"),
          amount: item.fetch("amount"),
          currency: currency,
          period: :monthly,
          start_date: period_start,
          end_date: period_end,
          active: true,
          external_synced_at: Time.current
        )
        budget.save!
      end
    end
  end
end
