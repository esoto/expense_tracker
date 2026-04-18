# frozen_string_literal: true

module ExternalBudgets
  # Stub PR 2 implementation — real implementation lands in PR 3 (salary_calc
  # sync service). Exists only so the OAuth callback in PR 2 can enqueue a
  # real job class without NameError.
  class PullJob < ApplicationJob
    queue_as :default

    def perform(source_id)
      Rails.logger.info("[external_budgets] pull job stub invoked for source=#{source_id}")
    end
  end
end
