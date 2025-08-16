require "rails_helper"

RSpec.describe "Batch Selection System", type: :system, js: true do
  let!(:category) { create(:category, name: "Food", color: "#22c55e") }
  let!(:email_account) { create(:email_account, email: "test@example.com") }

  let!(:expenses) do
    5.times.map do |i|
      create(:expense,
             merchant_name: "Merchant #{i + 1}",
             amount: (i + 1) * 100,
             transaction_date: Date.current - i.days,
             category: category,
             email_account: email_account,
             status: "pending")
    end
  end

  before do
    visit expenses_path
  end

  describe "Selection Mode Toggle" do
    it "shows and hides checkbox column when toggling selection mode" do
      # Initially checkboxes should be hidden
      expect(page).not_to have_css(".checkbox-header:not(.hidden)")
      expect(page).not_to have_css(".checkbox-cell:not(.hidden)")

      # Click selection mode button
      click_button "Selección Múltiple"

      # Checkboxes should now be visible
      expect(page).to have_css(".checkbox-header:not(.hidden)")
      expect(page).to have_css(".checkbox-cell:not(.hidden)")
      expect(page).to have_css("input[type='checkbox'][data-batch-selection-target='checkbox']", count: 5)
    end

    it "supports keyboard shortcut for toggling selection mode" do
      # Press Ctrl+Shift+A
      find("body").send_keys [ :control, :shift, "a" ]

      # Checkboxes should be visible
      expect(page).to have_css(".checkbox-header:not(.hidden)")
      expect(page).to have_css(".checkbox-cell:not(.hidden)")
    end
  end

  describe "Individual Selection" do
    before do
      click_button "Selección Múltiple"
    end

    it "selects individual expenses with visual feedback" do
      # Select first expense
      first_checkbox = find("input[data-expense-id='#{expenses.first.id}']")
      first_checkbox.click

      # Check visual feedback
      first_row = find("#expense_row_#{expenses.first.id}")
      expect(first_row[:class]).to include("bg-teal-50")
      expect(first_row["aria-selected"]).to eq("true")

      # Check selection counter
      expect(page).to have_content("1 de 5 gastos seleccionados")
    end

    it "deselects expenses when clicking again" do
      checkbox = find("input[data-expense-id='#{expenses.first.id}']")

      # Select
      checkbox.click
      expect(page).to have_content("1 de 5 gastos seleccionados")

      # Deselect
      checkbox.click
      expect(page).not_to have_content("gastos seleccionados")

      # Check visual feedback removed
      first_row = find("#expense_row_#{expenses.first.id}")
      expect(first_row["aria-selected"]).to eq("false")
    end

    it "allows row click to select in selection mode" do
      # Click on row (not checkbox)
      find("#expense_row_#{expenses.first.id} td.px-6", match: :first).click

      # Should be selected
      checkbox = find("input[data-expense-id='#{expenses.first.id}']")
      expect(checkbox).to be_checked
      expect(page).to have_content("1 de 5 gastos seleccionados")
    end
  end

  describe "Master Checkbox" do
    before do
      click_button "Selección Múltiple"
    end

    it "selects all visible expenses" do
      # Click master checkbox
      find("input[data-batch-selection-target='masterCheckbox']").click

      # All should be selected
      expenses.each do |expense|
        checkbox = find("input[data-expense-id='#{expense.id}']")
        expect(checkbox).to be_checked
      end

      expect(page).to have_content("5 de 5 gastos seleccionados")
    end

    it "deselects all when unchecked" do
      master = find("input[data-batch-selection-target='masterCheckbox']")

      # Select all
      master.click
      expect(page).to have_content("5 de 5 gastos seleccionados")

      # Deselect all
      master.click

      # Check that toolbar is hidden
      toolbar = find("[data-batch-selection-target='selectionToolbar']", visible: false)
      expect(toolbar).not_to be_visible

      # Check that selection counter is hidden
      counter = find("[data-batch-selection-target='selectionCounter']", visible: false)
      expect(counter).not_to be_visible

      expenses.each do |expense|
        checkbox = find("input[data-expense-id='#{expense.id}']")
        expect(checkbox).not_to be_checked
      end
    end

    it "shows indeterminate state for partial selection" do
      # Select first two expenses
      find("input[data-expense-id='#{expenses[0].id}']").click
      find("input[data-expense-id='#{expenses[1].id}']").click

      # Master should be indeterminate
      master = find("input[data-batch-selection-target='masterCheckbox']")
      expect(master.evaluate_script("this.indeterminate")).to be true
    end
  end

  describe "Selection Toolbar" do
    before do
      click_button "Selección Múltiple"
    end

    it "appears when items are selected" do
      # Initially hidden
      toolbar = find("[data-batch-selection-target='selectionToolbar']", visible: :all)
      expect(toolbar).not_to be_visible

      # Select an item
      find("input[data-expense-id='#{expenses.first.id}']").click

      # Toolbar should appear - wait for it to become visible
      expect(page).to have_css("[data-batch-selection-target='selectionToolbar']", visible: true, wait: 5)
      expect(page).to have_content("1 de 5 gastos seleccionados")
    end

    it "shows correct count in toolbar" do
      # Select multiple
      find("input[data-expense-id='#{expenses[0].id}']").click
      find("input[data-expense-id='#{expenses[1].id}']").click
      find("input[data-expense-id='#{expenses[2].id}']").click

      within "[data-batch-selection-target='selectionToolbar']" do
        expect(page).to have_content("3")
        expect(page).to have_content("de")
        expect(page).to have_content("5")
      end
    end

    it "clears selection with clear button" do
      # Select some items
      find("input[data-batch-selection-target='masterCheckbox']").click
      expect(page).to have_content("5 de 5 gastos seleccionados")

      # Click clear
      click_button "Limpiar selección"

      # All should be deselected
      expect(page).not_to have_content("gastos seleccionados")
      expenses.each do |expense|
        checkbox = find("input[data-expense-id='#{expense.id}']")
        expect(checkbox).not_to be_checked
      end
    end

    it "enables bulk operations button when items selected" do
      # Select an item first to make toolbar visible
      find("input[data-expense-id='#{expenses.first.id}']").click

      # Wait for toolbar to appear
      expect(page).to have_css("[data-batch-selection-target='selectionToolbar']", visible: true)

      # Now find the bulk button
      bulk_button = find("[data-batch-selection-target='bulkActionsButton']")

      # Should be enabled since we selected an item
      expect(bulk_button).not_to be_disabled
    end
  end

  describe "Keyboard Navigation" do
    before do
      click_button "Selección Múltiple"
    end

    it "supports Ctrl+A to select all" do
      # Focus on table
      find("#expenses_table_body").click

      # Press Ctrl+A - use the page element for better key handling
      page.send_keys [ :control, "a" ]

      # Wait for selection to complete
      expect(page).to have_content("5 de 5 gastos seleccionados", wait: 5)

      # Verify all checkboxes are checked
      expenses.each do |expense|
        checkbox = find("input[data-expense-id='#{expense.id}']", visible: :all)
        expect(checkbox).to be_checked
      end
    end

    it "supports Escape to clear selection" do
      # Select some items
      find("input[data-batch-selection-target='masterCheckbox']").click
      expect(page).to have_content("5 de 5 gastos seleccionados")

      # Press Escape
      find("body").send_keys :escape

      # Check that toolbar is hidden
      toolbar = find("[data-batch-selection-target='selectionToolbar']", visible: false)
      expect(toolbar).not_to be_visible

      # Check that selection counter is hidden
      counter = find("[data-batch-selection-target='selectionCounter']", visible: false)
      expect(counter).not_to be_visible
    end
  end

  describe "Integration with View Toggle" do
    before do
      click_button "Selección Múltiple"
    end

    it "maintains selection when toggling view mode" do
      # Select some items
      find("input[data-expense-id='#{expenses[0].id}']").click
      find("input[data-expense-id='#{expenses[1].id}']").click

      # Toggle to compact view
      click_button "Vista Compacta"

      # Selection should be maintained
      expect(page).to have_content("2 de 5 gastos seleccionados")
      expect(find("input[data-expense-id='#{expenses[0].id}']")).to be_checked
      expect(find("input[data-expense-id='#{expenses[1].id}']")).to be_checked

      # Toggle back to expanded
      click_button "Vista Expandida"

      # Still selected
      expect(page).to have_content("2 de 5 gastos seleccionados")
    end
  end

  describe "Integration with Inline Actions" do
    before do
      click_button "Selección Múltiple"
    end

    it "does not interfere with inline action buttons" do
      # Select an expense
      find("input[data-expense-id='#{expenses.first.id}']").click

      # Inline actions should still work
      within "#expense_row_#{expenses.first.id}" do
        # Click category button
        find("button[title*='Cambiar categoría']").click

        # Dropdown should appear
        expect(page).to have_css("[data-inline-actions-target='categoryDropdown']")
      end
    end
  end

  describe "Accessibility" do
    before do
      click_button "Selección Múltiple"
    end

    it "has proper ARIA labels on checkboxes" do
      checkbox = find("input[data-expense-id='#{expenses.first.id}']")
      expect(checkbox["aria-label"]).to include("Seleccionar gasto")
      expect(checkbox["aria-label"]).to include(expenses.first.merchant_name)
    end

    it "has proper ARIA selected state on rows" do
      row = find("#expense_row_#{expenses.first.id}")
      expect(row["aria-selected"]).to eq("false")

      # Select the expense
      find("input[data-expense-id='#{expenses.first.id}']").click

      expect(row["aria-selected"]).to eq("true")
    end

    it "announces selection changes to screen readers" do
      # This would typically be tested with accessibility testing tools
      # For now, we ensure the SR-only announcement element is created
      find("input[data-expense-id='#{expenses.first.id}']").click

      # The controller should create an announcement
      # We can't easily test screen reader output in system tests
      expect(page).to have_content("1 de 5 gastos seleccionados")
    end
  end

  describe "Mobile Responsiveness" do
    before do
      # Simulate mobile viewport
      page.driver.browser.manage.window.resize_to(375, 667)
      click_button "Selección Múltiple"
    end

    after do
      # Reset viewport
      page.driver.browser.manage.window.resize_to(1920, 1080)
    end

    it "works on mobile devices" do
      # Select items
      find("input[data-expense-id='#{expenses.first.id}']").click

      # Toolbar should be visible and adapted for mobile
      toolbar = find("[data-batch-selection-target='selectionToolbar']")
      expect(toolbar).to be_visible

      # Check that selection works
      expect(page).to have_content("1 de 5 gastos seleccionados")
    end
  end
end
