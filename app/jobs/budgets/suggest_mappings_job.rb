# frozen_string_literal: true

module Budgets
  # Runs the tiered MappingSuggester over an account's synced-but-unmapped
  # budgets. Enqueued after every successful external budget sync; safe to
  # re-run (cache hits and already-mapped budgets no-op). PER spec
  # 2026-07-05-budget-mapping-suggester-design.md.
  class SuggestMappingsJob < ApplicationJob
    queue_as :low

    # Serialize per USER (not per account): two accounts of one user syncing
    # concurrently would otherwise race MappingSuggester's cache upserts on
    # the shared (user_id, normalized_name) unique index. Solid Queue native
    # concurrency control instead of a hand-rolled lock.
    limits_concurrency to: 1, key: ->(email_account_id) {
      EmailAccount.find_by(id: email_account_id)&.user_id || email_account_id
    }

    def perform(email_account_id)
      email_account = EmailAccount.find_by(id: email_account_id)
      return if email_account.nil?

      budgets = Budget.synced_unmapped.where(email_account: email_account).includes(:user, :categories)
      return if budgets.empty?

      result = Services::Budgets::MappingSuggester.call(budgets)
      Rails.logger.info(
        "[SuggestMappingsJob] account=#{email_account_id} applied=#{result[:applied]} " \
        "suggested=#{result[:suggested]} unresolved=#{result[:unresolved].size}"
      )
    end
  end
end
