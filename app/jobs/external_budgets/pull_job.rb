# frozen_string_literal: true

module ExternalBudgets
  # Pulls the current monthly budget from an ExternalBudgetSource via
  # Services::ExternalBudgets::SyncService. Retries on transient transport
  # failures; deactivation on 401 is handled by SyncService (no retry at
  # the job layer for auth failures — user must re-link).
  class PullJob < ApplicationJob
    queue_as :default

    retry_on Services::ExternalBudgets::ApiClient::NetworkError,
             wait: :polynomially_longer, attempts: 3
    retry_on Services::ExternalBudgets::ApiClient::ServerError,
             wait: :polynomially_longer, attempts: 3

    def perform(source_id)
      source = ExternalBudgetSource.find_by(id: source_id)
      return unless source&.active?

      Services::ExternalBudgets::SyncService.new(source: source).call
    end
  end
end
