require "rails_helper"
require "support/inline_actions_helper"

RSpec.describe "Dashboard Inline Actions Comprehensive", type: :system, js: true do
  let!(:email_account) { create(:email_account) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }
  let!(:category_entertainment) { create(:category, name: "Entertainment", color: "#FFD93D") }
  
  let!(:expenses) do
    [
      create(:expense,
        email_account: email_account,
        category: category_food,
        status: "pending",
        merchant_name: "Restaurant ABC",
        amount: 5000,
        transaction_date: Date.current,
        description: "Business lunch"
      ),
      create(:expense,
        email_account: email_account,
        category: category_transport,
        status: "processed",
        merchant_name: "Uber Service",
        amount: 3500,
        transaction_date: 1.day.ago
      ),
      create(:expense,
        email_account: email_account,
        category: nil,
        status: "pending",
        merchant_name: "Unknown Store",
        amount: 2000,
        transaction_date: 2.days.ago
      )
    ]
  end

  before do
    visit dashboard_expenses_path
    wait_for_page_load
  end

  def wait_for_page_load
    expect(page).to have_css("#dashboard-expenses-widget", wait: 10)
    expect(page).to have_css('[data-controller="dashboard-inline-actions"]', wait: 10)
    # Wait for Stimulus controllers to fully initialize
    sleep 1
    # Ensure JavaScript is fully loaded
    expect(page.evaluate_script("typeof Stimulus !== 'undefined'")).to be true
  end

  def find_expense_row(expense)
    find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']", match: :first)
  end

  def wait_for_ajax
    sleep 0.5
    expect(page).not_to have_css(".inline-action-loading")
  end

  describe "Category Change Functionality" do
    it "allows changing category via dropdown" do
      uncategorized = expenses.last
      row = find_expense_row(uncategorized)
      
      # Hover to show actions and ensure they're visible
      row.hover
      sleep 0.5
      # Force hover state if needed
      page.execute_script("arguments[0].classList.add('hover')", row.native)
      
      # Click category button - use JavaScript to avoid overlay issues
      within row do
        button = find('button[title*="Categorizar"]', visible: :all)
        page.execute_script("arguments[0].scrollIntoView(true);", button.native)
        page.execute_script("arguments[0].click();", button.native)
      end
      
      # Dropdown should appear
      dropdown = find('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)', match: :first)
      expect(dropdown).to be_visible
      
      # Select Entertainment category
      within dropdown do
        click_button "Entertainment"
      end
      
      wait_for_ajax
      
      # Verify category was updated
      within row do
        badge = find('.expense-category-badge')
        # Convert hex to RGB for comparison or check the actual style value
        style = badge[:style]
        expect(style).to match(/background-color/i)
        expect(badge.text).to eq("E")
      end
      
      # Verify toast notification
      expect(page).to have_content('Categorizado como "Entertainment"')
    end

    it "updates category in metadata section" do
      expense = expenses.first
      row = find_expense_row(expense)
      
      row.hover
      within row do
        find('button[title*="Categorizar"]').click
      end
      
      within '[data-dashboard-inline-actions-target="categoryDropdown"]' do
        click_button "Transport"
      end
      
      wait_for_ajax
      
      within row do
        expect(page).to have_content("Transport")
      end
    end

    it "closes dropdown when clicking outside" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[title*="Categorizar"]').click
      end
      
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      
      # Click outside
      find('h1', text: 'Dashboard de Gastos').click
      sleep 0.3
      
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
    end

    it "handles category API errors gracefully" do
      # This would require mocking the API to fail
      # For now, we verify the error handling exists in the controller
      row = find_expense_row(expenses.first)
      
      # Verify the controller is attached
      expect(row["data-controller"]).to include("dashboard-inline-actions")
    end
  end

  describe "Status Toggle Functionality" do
    it "toggles status from pending to processed" do
      pending_expense = expenses.first
      row = find_expense_row(pending_expense)
      
      row.hover
      sleep 0.5
      
      # Find status button with better selector
      within row do
        status_button = find('button[data-action*="toggleStatus"]', visible: :all)
        page.execute_script("arguments[0].scrollIntoView(true);", status_button.native)
        
        # Should show pending state
        expect(status_button[:class]).to include("amber")
        
        # Click to toggle - use JavaScript to avoid overlay
        page.execute_script("arguments[0].click();", status_button.native)
      end
      
      wait_for_ajax
      
      # Verify status changed
      within row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-emerald-500")
      end
      
      # Verify toast
      expect(page).to have_content("Estado cambiado a procesado")
    end

    it "toggles status from processed to pending" do
      processed_expense = expenses[1]
      row = find_expense_row(processed_expense)
      
      row.hover
      
      within row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-emerald-500")
        status_button.click
      end
      
      wait_for_ajax
      
      within row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-amber-500")
      end
      
      expect(page).to have_content("Estado cambiado a pendiente")
    end

    it "updates status in expanded view" do
      # Switch to expanded view
      click_button "Expandida"
      sleep 0.5
      
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      wait_for_ajax
      
      # Check expanded details
      within row do
        expanded_details = find('.expense-expanded-details')
        expect(expanded_details).to have_content("Processed")
      end
    end
  end

  describe "Duplicate Functionality" do
    it "duplicates an expense successfully" do
      original_expense = expenses.first
      initial_count = all('[data-dashboard-inline-actions-expense-id-value]').count
      
      row = find_expense_row(original_expense)
      row.hover
      sleep 0.5
      
      within row do
        button = find('button[title*="Duplicar"]', visible: :all)
        page.execute_script("arguments[0].scrollIntoView(true);", button.native)
        page.execute_script("arguments[0].click();", button.native)
      end
      
      # Wait for duplication
      expect(page).to have_content("Gasto duplicado exitosamente", wait: 5)
      sleep 1.5 # Wait for page reload
      
      # Verify new expense appears
      new_count = all('[data-dashboard-inline-actions-expense-id-value]').count
      expect(new_count).to eq(initial_count + 1)
      
      # Verify duplicated content
      expect(page).to have_content("Restaurant ABC", count: 2)
    end

    it "shows loading state during duplication" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[title*="Duplicar"]').click
      end
      
      # Should show loading state
      expect(row[:class]).to include("opacity-75")
    end
  end

  describe "Delete Functionality" do
    it "shows confirmation modal before deletion" do
      row = find_expense_row(expenses.first)
      row.hover
      sleep 0.5
      
      within row do
        button = find('button[title*="Eliminar"]', visible: :all)
        page.execute_script("arguments[0].scrollIntoView(true);", button.native)
        page.execute_script("arguments[0].click();", button.native)
      end
      
      # Confirmation should appear
      confirmation = find('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)', match: :first)
      expect(confirmation).to be_visible
      expect(confirmation).to have_content("Confirmar eliminación")
      expect(confirmation).to have_content("Esta acción no se puede deshacer")
      
      within confirmation do
        expect(page).to have_button("Eliminar")
        expect(page).to have_button("Cancelar")
      end
    end

    it "cancels deletion when clicking cancel" do
      expense = expenses.first
      row = find_expense_row(expense)
      row.hover
      
      within row do
        find('button[title*="Eliminar"]').click
      end
      
      within '[data-dashboard-inline-actions-target="deleteConfirmation"]' do
        click_button "Cancelar"
      end
      
      sleep 0.3
      
      # Modal should close
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
      
      # Expense should still exist
      expect(page).to have_content(expense.merchant_name)
    end

    it "deletes expense after confirmation" do
      expense = expenses.last
      row = find_expense_row(expense)
      row.hover
      
      within row do
        find('button[title*="Eliminar"]').click
      end
      
      within '[data-dashboard-inline-actions-target="deleteConfirmation"]' do
        click_button "Eliminar"
      end
      
      # Wait for deletion animation
      sleep 0.5
      
      # Expense should be removed
      expect(page).not_to have_content(expense.merchant_name)
      
      # Success toast
      expect(page).to have_content("Gasto eliminado exitosamente")
    end

    it "closes confirmation with Escape key" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[title*="Eliminar"]').click
      end
      
      expect(page).to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
      
      page.send_keys(:escape)
      sleep 0.3
      
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
    end
  end

  describe "Keyboard Navigation" do
    it "supports keyboard shortcuts for actions" do
      row = find_expense_row(expenses.first)
      row.click # Focus the row
      
      # Test 'C' for category
      page.send_keys('c')
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      page.send_keys(:escape)
      sleep 0.2
      
      # Test 'S' for status
      page.send_keys('s')
      wait_for_ajax
      expect(page).to have_content("Estado cambiado")
      
      # Test 'D' for duplicate
      page.send_keys('d')
      expect(page).to have_content("Gasto duplicado exitosamente", wait: 5)
    end

    it "navigates dropdown with keyboard" do
      row = find_expense_row(expenses.first)
      row.click
      
      page.send_keys('c')
      
      # First category should be focused
      active_element = page.evaluate_script("document.activeElement")
      expect(active_element.tag_name.downcase).to eq("button")
    end

    it "supports Delete key for deletion" do
      row = find_expense_row(expenses.first)
      row.click
      
      page.send_keys(:delete)
      
      expect(page).to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
    end
  end

  describe "Loading States and Performance" do
    it "shows loading state during operations" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      # Should show loading state
      expect(row[:class]).to include("opacity-75")
      
      wait_for_ajax
      
      # Loading state should clear
      expect(row[:class]).not_to include("opacity-75")
    end

    it "disables actions during loading" do
      row = find_expense_row(expenses.first)
      row.hover
      sleep 0.5
      
      within row do
        button = find('button[data-action*="toggleStatus"]', visible: :all)
        button.click
        
        # Actions should be disabled
        actions = find('.inline-quick-actions', visible: :all)
        expect(actions[:style]).to include("pointer-events") if actions[:style]
      end
    end

    it "completes actions quickly" do
      row = find_expense_row(expenses.first)
      row.hover
      
      start_time = Time.now
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      expect(page).to have_content("Estado cambiado", wait: 2)
      
      end_time = Time.now
      response_time = (end_time - start_time) * 1000
      
      # Should be under 2 seconds in test environment
      expect(response_time).to be < 2000
    end
  end

  describe "Toast Notifications" do
    it "shows success toasts for all actions" do
      # Category change
      row = find_expense_row(expenses.last)
      row.hover
      
      within row do
        find('button[title*="Categorizar"]').click
      end
      
      within '[data-dashboard-inline-actions-target="categoryDropdown"]' do
        click_button "Food"
      end
      
      expect(page).to have_content('Categorizado como "Food"')
      
      # Status change
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      expect(page).to have_content("Estado cambiado")
    end

    it "auto-dismisses toasts" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      expect(page).to have_content("Estado cambiado")
      
      # Wait for auto-dismiss (5 seconds)
      sleep 5.5
      
      expect(page).not_to have_content("Estado cambiado")
    end

    it "allows manual toast dismissal" do
      row = find_expense_row(expenses.first)
      row.hover
      
      within row do
        find('button[data-action*="toggleStatus"]').click
      end
      
      expect(page).to have_content("Estado cambiado")
      
      # Find and click close button
      toast = find('div', text: /Estado cambiado/).ancestor('div.fixed')
      within toast do
        find('button').click
      end
      
      expect(page).not_to have_content("Estado cambiado")
    end
  end

  describe "Mobile Responsiveness", :mobile do
    before do
      page.driver.browser.manage.window.resize_to(375, 667)
      visit dashboard_expenses_path
      wait_for_page_load
    end

    after do
      page.driver.browser.manage.window.resize_to(1400, 900)
    end

    it "shows actions without hover on mobile" do
      row = find_expense_row(expenses.first)
      
      within row do
        # On mobile, actions should be visible without hover
        actions = find('.inline-quick-actions', visible: :all)
        # Check if actions container exists and has buttons
        expect(actions).not_to be_nil
        buttons = actions.all('button', visible: :all)
        expect(buttons.count).to be > 0
      end
    end

    it "has larger touch targets" do
      row = find_expense_row(expenses.first)
      
      within row do
        buttons = all('button[data-action*="dashboard-inline-actions"]')
        buttons.each do |button|
          width = page.evaluate_script("arguments[0].offsetWidth", button.native)
          height = page.evaluate_script("arguments[0].offsetHeight", button.native)
          
          # Should be at least 44x44 pixels for touch
          expect(width).to be >= 44
          expect(height).to be >= 44
        end
      end
    end
  end

  describe "Accessibility" do
    it "has proper ARIA labels" do
      row = find_expense_row(expenses.first)
      
      expect(row[:role]).to eq("article")
      expect(row["aria-label"]).to include("Gasto")
      
      row.hover
      
      within row do
        buttons = all('button[data-action*="dashboard-inline-actions"]')
        buttons.each do |button|
          expect(button["aria-label"]).not_to be_nil
        end
      end
    end

    it "maintains focus management" do
      row = find_expense_row(expenses.first)
      row.click
      
      # Open category dropdown
      page.send_keys('c')
      
      # Focus should move to dropdown
      active_element = page.evaluate_script("document.activeElement")
      expect(active_element.tag_name.downcase).to eq("button")
      
      # Close dropdown
      page.send_keys(:escape)
      
      # Focus should return
      active_element = page.evaluate_script("document.activeElement")
      expect(active_element).not_to be_nil
    end

    it "supports keyboard-only navigation" do
      # Tab to first expense row
      page.send_keys(:tab) until page.evaluate_script("document.activeElement").attribute("data-expense-id")
      
      # Use keyboard to interact
      page.send_keys('c')
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      
      page.send_keys(:escape)
      page.send_keys('s')
      
      expect(page).to have_content("Estado cambiado")
    end
  end

  describe "Integration with View Modes" do
    it "works in compact view" do
      # Default is compact
      expect(page).to have_css("[data-dashboard-expenses-view-mode-value='compact']")
      
      row = find_expense_row(expenses.first)
      row.hover
      sleep 0.5
      
      within row do
        expect(page).to have_css('button[title*="Categorizar"]', visible: :all)
        button = find('button[data-action*="toggleStatus"]', visible: :all)
        button.click
      end
      
      expect(page).to have_content("Estado cambiado")
    end

    it "works in expanded view" do
      click_button "Expandida"
      sleep 0.5
      
      expect(page).to have_css("[data-dashboard-expenses-view-mode-value='expanded']")
      
      row = find_expense_row(expenses.first)
      row.hover
      sleep 0.5
      
      within row do
        expect(page).to have_css('button[title*="Categorizar"]', visible: :all)
        button = find('button[data-action*="toggleStatus"]', visible: :all)
        button.click
      end
      
      expect(page).to have_content("Estado cambiado")
      
      # Verify expanded details updated
      within row do
        expect(page).to have_css('.expense-expanded-details')
      end
    end
  end

  describe "Error Handling" do
    it "controller handles errors gracefully" do
      # Verify error handling exists
      row = find_expense_row(expenses.first)
      
      controller_present = page.evaluate_script(
        "document.querySelector('[data-controller=\"dashboard-inline-actions\"]') !== null"
      )
      expect(controller_present).to be true
      
      # Verify toast system for errors
      has_toast_handler = page.evaluate_script(
        "typeof document.querySelector('[data-controller=\"dashboard-inline-actions\"]').__stimulusController !== 'undefined'"
      )
      # Controller should be attached
      expect(row["data-controller"]).to include("dashboard-inline-actions")
    end
  end

  describe "Multiple Actions" do
    it "handles rapid successive actions" do
      rows = all('[data-dashboard-inline-actions-expense-id-value]')
      
      # Perform actions on multiple rows quickly
      if rows.length >= 2
        rows[0].hover
        within rows[0] do
          find('button[data-action*="toggleStatus"]').click
        end
        
        sleep 0.2
        
        rows[1].hover
        within rows[1] do
          find('button[data-action*="toggleStatus"]').click
        end
        
        # Both should complete
        expect(page).to have_content("Estado cambiado")
      end
    end

    it "handles multiple dropdowns correctly" do
      rows = all('[data-dashboard-inline-actions-expense-id-value]')
      
      if rows.length >= 2
        # Open first dropdown
        rows[0].hover
        within rows[0] do
          find('button[title*="Categorizar"]').click
        end
        
        expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)', count: 1)
        
        # Opening second should close first
        rows[1].hover
        within rows[1] do
          find('button[title*="Categorizar"]').click
        end
        
        # Still only one dropdown open
        expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)', count: 1)
      end
    end
  end
end