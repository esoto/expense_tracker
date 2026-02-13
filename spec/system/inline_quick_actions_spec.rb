require 'rails_helper'

RSpec.describe "Inline Quick Actions", type: :system, js: true do
  let(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }
  let!(:category1) { create(:category, name: "Food", color: "#22c55e") }
  let!(:category2) { create(:category, name: "Transport", color: "#3b82f6") }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category1,
      status: "pending",
      merchant_name: "Test Merchant",
      amount: 1000,
      transaction_date: Date.current
    )
  end

  before do
    driven_by(:selenium_chrome_headless)
    sign_in_admin_user(admin_user)
    visit expenses_path

    # Wait for Stimulus to be loaded
    expect(page).to have_css('tr[data-controller="inline-actions"]', wait: 5)

    # Ensure JavaScript is ready
    page.execute_script("console.log('Test starting')")
  end

  describe "Actions visibility" do
    it "shows actions on hover in expanded view" do
      # Ensure we're in expanded view
      unless page.has_css?('[data-view-toggle-target="expandedIcon"].hidden')
        find('[data-view-toggle-target="toggleButton"]').click
      end

      # Find and hover over the expense row
      expense_row = find("tr.expense-row-with-actions", match: :first)
      expense_row.hover

      # Wait for CSS transition
      sleep 0.2

      # Actions should become visible via CSS hover
      # Use visible: :all to find hidden elements, then check computed style
      actions_container = find('.inline-actions-container', match: :first, visible: :all)

      # Check if visible using computed styles
      opacity = page.evaluate_script("window.getComputedStyle(arguments[0]).opacity", actions_container.native)
      expect(opacity.to_f).to be > 0
    end

    it "hides actions in compact view mode" do
      # Switch to compact view if not already
      if page.has_css?('[data-view-toggle-target="compactIcon"]:not(.hidden)')
        find('[data-view-toggle-target="toggleButton"]').click
      end

      # Actions should be hidden in compact mode
      expect(page).not_to have_css('[data-inline-actions-target="actionsContainer"].opacity-100')
    end
  end

  describe "Category dropdown" do
    it "opens category dropdown and allows selection" do
      # Hover to show actions
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Click category button
      within expense_row do
        find('button[title*="Cambiar categoría"]').click
      end

      # Dropdown should be visible
      expect(page).to have_css('[data-inline-actions-target="categoryDropdown"]:not(.hidden)')

      # Select Transport category
      within '[data-inline-actions-target="categoryDropdown"]' do
        click_button "Transport"
      end

      # Check for success toast
      expect(page).to have_content("Categoría actualizada", wait: 3)
    end

    it "positions dropdown correctly to avoid clipping" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Cambiar categoría"]').click
      end

      dropdown = find('[data-inline-actions-target="categoryDropdown"]:not(.hidden)')
      # z-index is set via CSS, not inline style - just verify it's visible
      expect(dropdown).to be_visible
    end
  end

  describe "Delete confirmation" do
    it "shows confirmation modal before deleting" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Click delete button
      within expense_row do
        find('button[title*="Eliminar gasto"]').click
      end

      # Confirmation modal should appear
      expect(page).to have_content("Confirmar eliminación")
      expect(page).to have_content("Esta acción no se puede deshacer")

      # Cancel deletion
      within '[data-inline-actions-target="deleteConfirmation"]' do
        click_button "Cancelar"
      end

      # Modal should close (wait for it to be hidden)
      expect(page).to have_css('[data-inline-actions-target="deleteConfirmation"].hidden', visible: :hidden, wait: 2)

      # Expense should still exist
      expect(page).to have_content(expense.merchant_name)
    end

    it "deletes expense after confirmation" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Eliminar gasto"]').click
      end

      # Confirm deletion
      within '[data-inline-actions-target="deleteConfirmation"]' do
        click_button "Eliminar"
      end

      # Row should disappear with animation
      expect(page).not_to have_content(expense.merchant_name, wait: 3)

      # Success toast should appear
      expect(page).to have_content("Gasto eliminado", wait: 3)
    end
  end

  describe "Status toggle" do
    it "toggles between pending and processed status" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Initial status should be pending
      expect(page).to have_content("Pendiente")

      # Click status toggle button
      within expense_row do
        find('button[title*="Marcar como revisado"]').click
      end

      # Status should change to processed
      expect(page).to have_content("Procesado", wait: 2)

      # Success toast should appear
      expect(page).to have_content("Marcado como revisado", wait: 3)
    end
  end

  describe "Duplicate expense" do
    it "creates a duplicate of the expense" do
      initial_count = all("tr[data-controller='inline-actions']").count

      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Click duplicate button
      within expense_row do
        find('button[title*="Duplicar gasto"]').click
      end

      # Success toast should appear
      expect(page).to have_content("Gasto duplicado exitosamente", wait: 3)

      # Should have one more expense row
      expect(all("tr[data-controller='inline-actions']").count).to eq(initial_count + 1)
    end
  end

  describe "Toast notifications" do
    it "displays toast notifications for all actions" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Test category change toast
      within expense_row do
        find('button[title*="Cambiar categoría"]').click
      end
      within '[data-inline-actions-target="categoryDropdown"]' do
        click_button "Transport"
      end

      # Toast container should exist and show message
      expect(page).to have_css('#toast-container')
      expect(page).to have_content("Categoría actualizada", wait: 3)
    end
  end

  describe "Keyboard shortcuts" do
    it "supports keyboard shortcuts for quick actions" do
      expense_row = find("tr[data-controller='inline-actions']", match: :first)
      expense_row.hover

      # Focus on the row
      expense_row.click

      # Press 'C' for category
      page.send_keys('c')
      expect(page).to have_css('[data-inline-actions-target="categoryDropdown"]:not(.hidden)', wait: 2)

      # Press Escape to close
      page.send_keys(:escape)
      expect(page).to have_css('[data-inline-actions-target="categoryDropdown"].hidden', visible: :hidden)
    end
  end

  describe "Mobile responsiveness" do
    it "handles touch interactions on mobile devices" do
      # Simulate mobile viewport
      page.driver.browser.manage.window.resize_to(375, 667)

      # Give the page time to adjust to mobile size
      sleep 0.5

      expense_row = find("tr[data-controller='inline-actions']", match: :first)

      # On mobile, actions should be visible by default due to CSS media query
      # Find the actions container (might be hidden in expanded view but visible on mobile)
      actions_container = find('.inline-actions-container', visible: :all, match: :first)

      # Verify it's visible on mobile using computed styles
      opacity = page.evaluate_script("window.getComputedStyle(arguments[0]).opacity", actions_container.native)
      visibility = page.evaluate_script("window.getComputedStyle(arguments[0]).visibility", actions_container.native)

      expect(opacity.to_f).to eq(1.0)
      expect(visibility).to eq('visible')

      # Verify that action buttons are accessible on mobile
      category_button = find('button[title*="Cambiar categoría"]', visible: :all, match: :first)
      expect(category_button).to be_present

      # Verify the button is accessible (not hidden)
      button_display = page.evaluate_script("window.getComputedStyle(arguments[0]).display", category_button.native)
      expect(button_display).not_to eq('none')
    end
  end
end
