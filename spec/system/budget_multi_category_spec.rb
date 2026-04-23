# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Creating a multi-category budget", type: :system do
  let(:admin_user)     { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }
  let!(:food)          { create(:category, name: "Food") }
  let!(:transport)     { create(:category, name: "Transport") }

  before do
    # Use rack_test: no JS is needed for this non-interactive form
    # (checkboxes, selects, submit), and it avoids the Selenium overhead.
    driven_by(:rack_test)

    # Sign in via the unified /login form (post PR-12). The shared
    # `sign_in_admin_user` helper still uses the pre-PR-12 Spanish button
    # label ("Iniciar Sesión"), so we drive the current form directly.
    visit login_path
    fill_in "email", with: admin_user.email
    fill_in "password", with: "TestPass123!" # factory default
    click_button "Sign in"
  end

  it "lets the user pick multiple categories and a salary bucket" do
    visit new_budget_path

    fill_in "budget[name]", with: "Familia"
    fill_in "budget[amount]", with: "200000"

    check "Food"
    check "Transport"
    select "Gastos fijos", from: "budget[salary_bucket]"

    click_on "Crear Presupuesto"

    budget = Budget.last
    expect(budget.categories).to contain_exactly(food, transport)
    expect(budget.salary_bucket).to eq("fixed")
  end
end
