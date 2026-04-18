# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the inline category picker on unmapped external
# budgets. Tagged :slow so it only runs in CI (and in the worktree on demand).
RSpec.describe "Budgets external source UI", type: :system, slow: true do
  let(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account, active: true) }
  let!(:category) { create(:category, name: "Comida", i18n_key: "food") }
  # Seed at least one expense so the `has_many :categories, through: :expenses`
  # association surfaces `category` in the picker options.
  let!(:seed_expense) do
    create(:expense, email_account: email_account, category: category)
  end
  let!(:unmapped_budget) do
    create(:budget,
      email_account: email_account,
      category: nil,
      external_source: "salary_calculator",
      external_id: "sc-system-1",
      name: "Salary budget")
  end

  before do
    driven_by(:rack_test)
    sign_in_admin_user(admin_user)
    allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
  end

  it "lets the user map an unmapped external budget to a category inline" do
    visit budgets_path

    expect(page).to have_content(I18n.t("budgets.external_badge"))
    expect(page).to have_content(I18n.t("budgets.unmapped_banner"))

    select category.display_name, from: "budget[category_id]"
    click_button I18n.t("budgets.save_category")

    # Redirects to dashboard on success; revisit the index to confirm state.
    visit budgets_path

    expect(page).not_to have_content(I18n.t("budgets.unmapped_banner"))
    expect(page).to have_content(I18n.t("budgets.external_badge"))
  end
end
