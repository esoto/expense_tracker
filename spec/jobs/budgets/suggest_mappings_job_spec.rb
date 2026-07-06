# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::SuggestMappingsJob, :unit do
  let(:email_account) { create(:email_account) }

  it "runs the suggester over the account's synced unmapped budgets" do
    budget = create(:budget, email_account: email_account, user: email_account.user,
                    external_source: "salary_calculator", external_id: 1, category: nil)
    create(:budget, email_account: email_account, user: email_account.user, name: "native one")

    expect(Services::Budgets::MappingSuggester).to receive(:call) do |budgets|
      expect(budgets).to contain_exactly(budget)
      { applied: 0, suggested: 0, unresolved: [] }
    end

    described_class.perform_now(email_account.id)
  end

  it "no-ops for a missing email account" do
    expect(Services::Budgets::MappingSuggester).not_to receive(:call)
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
