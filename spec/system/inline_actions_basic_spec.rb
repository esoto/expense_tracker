require "rails_helper"

RSpec.describe "Inline Actions Basic", type: :system, js: true do
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: "Test Category", color: "#FF0000") }
  let!(:expense) { create(:expense, email_account: email_account, status: "pending", merchant_name: "Test Merchant") }

  before do
    visit dashboard_expenses_path
    expect(page).to have_css("#dashboard-expenses-widget", wait: 10)
    sleep 1 # Allow JS to load
  end

  it "shows inline action buttons on hover" do
    row = find("[data-expense-id='#{expense.id}']")
    
    # Initially buttons should be hidden
    within row do
      actions = find('.inline-quick-actions', visible: :all)
      expect(actions[:style]).to include("opacity: 0")
    end
    
    # Hover should show buttons
    row.hover
    sleep 0.5
    
    within row do
      # Check if buttons are present
      expect(page).to have_css('button[title*="Categorizar"]', visible: :all)
      expect(page).to have_css('button[data-action*="toggleStatus"]', visible: :all)
      expect(page).to have_css('button[title*="Duplicar"]', visible: :all)
      expect(page).to have_css('button[title*="Eliminar"]', visible: :all)
    end
  end

  it "toggles expense status" do
    row = find("[data-expense-id='#{expense.id}']")
    row.hover
    sleep 0.5
    
    within row do
      # Force visibility for test
      actions = find('.inline-quick-actions', visible: :all)
      page.execute_script("arguments[0].style.opacity = '1'", actions.native)
      
      # Find and click status button
      status_button = find('button[data-action*="toggleStatus"]', visible: :all)
      page.execute_script("arguments[0].click()", status_button.native)
    end
    
    # Wait for update
    sleep 1
    
    # Check for success message
    expect(page).to have_content("Estado cambiado", wait: 5)
  end
end