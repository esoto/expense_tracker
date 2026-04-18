# frozen_string_literal: true

require "rails_helper"

# Covers the PR 4 "salary_calc" UI additions on the budgets index:
#   - empty-state CTA when no external source is linked
#   - sync-in-progress empty state when a source IS linked
#   - "from salary_calc" badge on external budgets
#   - unmapped banner with inline category picker for synced_unmapped rows
#   - no badge on native budgets
#   - banner disappears after patching category_id via the existing update action
RSpec.describe "Budgets external source UI", type: :request, unit: true do
  let!(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }

  before do
    sign_in_admin(admin_user)
    # Controller uses EmailAccount.active.first; stub to guarantee isolation.
    allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
  end

  describe "GET /budgets" do
    context "with no external source and no budgets" do
      it "renders the Connect salary_calc empty-state CTA" do
        get budgets_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("budgets.empty_state.cta"))
        expect(response.body).to include(I18n.t("budgets.empty_state.heading"))
        # The CTA must be a POST form to connect_external_source_path.
        expect(response.body).to match(
          %r{<form[^>]+action="#{Regexp.escape(connect_external_source_path)}"}i
        )
        expect(response.body).to match(%r{<form[^>]+method="post"}i)
      end
    end

    context "with an active external source and no budgets" do
      before do
        create(:external_budget_source, email_account: email_account, active: true)
      end

      it "renders the sync-in-progress empty state" do
        get budgets_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("budgets.empty_state.sync_in_progress"))
        expect(response.body).not_to include(I18n.t("budgets.empty_state.cta"))
      end
    end

    context "with an external mapped budget" do
      let!(:category) { create(:category) }
      let!(:budget) do
        create(:budget,
          email_account: email_account,
          category: category,
          external_source: "salary_calculator",
          external_id: "sc-123")
      end

      it "shows the from-salary_calc badge" do
        get budgets_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("budgets.external_badge"))
        # Mapped — no unmapped banner.
        expect(response.body).not_to include(I18n.t("budgets.unmapped_banner"))
      end
    end

    context "with an unmapped external budget" do
      let!(:budget) do
        create(:budget,
          email_account: email_account,
          category: nil,
          external_source: "salary_calculator",
          external_id: "sc-unmapped-1")
      end

      it "shows the unmapped banner with a category picker select" do
        get budgets_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("budgets.unmapped_banner"))
        expect(response.body).to match(%r{<select[^>]+name="budget\[category_id\]"})
        # Badge still rendered because the budget is external.
        expect(response.body).to include(I18n.t("budgets.external_badge"))
      end
    end

    context "with a native budget" do
      let!(:budget) do
        create(:budget, email_account: email_account, category: nil)
      end

      it "does not render the external badge or the unmapped banner" do
        get budgets_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("budgets.external_badge"))
        expect(response.body).not_to include(I18n.t("budgets.unmapped_banner"))
      end
    end
  end

  describe "PATCH /budgets/:id then GET /budgets" do
    let!(:category) { create(:category) }
    let!(:budget) do
      create(:budget,
        email_account: email_account,
        category: nil,
        external_source: "salary_calculator",
        external_id: "sc-42")
    end

    it "clears the unmapped banner once a category is assigned" do
      expect(budget.reload.unmapped?).to be(true)

      patch budget_path(budget), params: { budget: { category_id: category.id } }
      expect(response).to have_http_status(:found)

      expect(budget.reload.unmapped?).to be(false)

      get budgets_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("budgets.unmapped_banner"))
      # Badge should still be visible on the (now mapped) external budget.
      expect(response.body).to include(I18n.t("budgets.external_badge"))
    end
  end

  describe "Query efficiency for multiple unmapped external budgets" do
    it "renders multiple unmapped external cards without raising" do
      # email_account.categories is `through: :expenses`, so expenses anchor the categories.
      categories = create_list(:category, 2)
      categories.each do |cat|
        create(:expense, email_account: email_account, category: cat)
      end

      3.times do |i|
        create(:budget,
          email_account: email_account,
          category: nil,
          external_source: "salary_calculator",
          external_id: 200 + i,
          name: "Unmapped Budget #{i}")
      end

      get budgets_path

      expect(response).to have_http_status(:ok)
      expect(assigns(:category_options)).to be_an(Array)
      expect(response.body).to include("Unmapped Budget 0", "Unmapped Budget 1", "Unmapped Budget 2")
      categories.each do |cat|
        # Each category renders once per unmapped card's dropdown.
        expect(response.body.scan(cat.display_name).size).to be >= 3
      end
    end
  end
end
