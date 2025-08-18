require "rails_helper"

RSpec.describe "Dashboard Inline Actions Basic Test", type: :system, js: true do
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category,
      status: "pending",
      merchant_name: "Test Restaurant",
      amount: 5000,
      transaction_date: Date.current
    )
  end

  before do
    visit dashboard_expenses_path
    wait_for_turbo
  end

  def wait_for_turbo
    expect(page).to have_css('body', wait: 5)
    sleep 0.5 # Give Stimulus time to connect
  end

  it "displays the dashboard page" do
    expect(page).to have_content("Dashboard de Gastos")
    expect(page).to have_content("Gastos Recientes")
  end

  it "shows expense in the list" do
    within "#dashboard-expenses-widget" do
      expect(page).to have_content("Test Restaurant")
      expect(page).to have_content("5,000")
    end
  end

  it "has inline actions controller attached" do
    expense_row = find("[data-expense-id='#{expense.id}']", match: :first)
    expect(expense_row["data-controller"]).to include("dashboard-inline-actions")
  end

  it "shows quick actions on hover" do
    expense_row = find("[data-expense-id='#{expense.id}']", match: :first)

    # Actions should be hidden initially
    within expense_row do
      actions = find('[data-dashboard-expenses-target="quickActions"]', visible: :all)
      expect(actions).not_to be_visible
    end

    # Hover to show actions
    expense_row.hover
    sleep 0.5 # Wait for CSS transition

    # Actions should be visible
    within expense_row do
      actions = find('[data-dashboard-expenses-target="quickActions"]')
      expect(actions).to be_visible
    end
  end
end
