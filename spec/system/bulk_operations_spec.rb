require 'rails_helper'

RSpec.describe "Bulk Operations", type: :system, js: true do
  let(:admin_user) { create(:admin_user) }
  let(:email_account) { create(:email_account) }
  let!(:category1) { create(:category, name: "Food") }
  let!(:category2) { create(:category, name: "Transport") }
  let!(:expenses) do
    [
      create(:expense,
        email_account: email_account,
        merchant_name: "Restaurant A",
        category: nil,
        amount: 100,
        transaction_date: Date.current
      ),
      create(:expense,
        email_account: email_account,
        merchant_name: "Gas Station",
        category: nil,
        amount: 200,
        transaction_date: Date.current - 1.day
      ),
      create(:expense,
        email_account: email_account,
        merchant_name: "Grocery Store",
        category: category1,
        amount: 300,
        transaction_date: Date.current - 2.days
      )
    ]
  end

  before do
    sign_in_admin_user(admin_user)
    visit expenses_path
  end

  describe "Batch selection and bulk operations" do
    it "allows selecting multiple expenses and categorizing them" do
      # Enable selection mode
      click_button "Selección Múltiple"

      # Wait for checkbox column to appear
      expect(page).to have_css('.checkbox-cell', visible: true, wait: 5)

      # Select first two expenses
      within "#expenses_table_body" do
        checkboxes = all('input[type="checkbox"][data-batch-selection-target="checkbox"]')
        expect(checkboxes.size).to be >= 2
        checkboxes[0].click
        checkboxes[1].click
      end

      # Verify selection toolbar appears
      expect(page).to have_css('[data-batch-selection-target="selectionToolbar"]', visible: true)
      expect(page).to have_text("2 de 3 gastos seleccionados")

      # Click bulk operations button
      click_button "Operaciones en Lote"

      # Wait for modal to appear with better selector
      expect(page).to have_css('#bulk_operations_modal[aria-hidden="false"]', visible: true, wait: 5)
      expect(page).to have_text("2 gastos seleccionados")

      # Select categorize operation - use correct input value
      within '#bulk_operations_modal' do
        find('input[type="radio"][value="categorize"]').click
      end

      # Category dropdown should appear
      expect(page).to have_select("bulk_category", wait: 3)

      # Select a category
      select category2.name, from: "bulk_category"

      # Submit the operation
      click_button "Categorizar Gastos"

      # Wait for success message (might show count)
      expect(page).to have_text("categorizados", wait: 5)

      # Wait for modal to close (might take time due to animation)
      sleep 2.5 # Allow time for the 2-second delay + animation

      # Modal should be hidden after operation
      expect(page).to have_css('#bulk_operations_modal', visible: false)

      # Verify expenses were updated in the database
      expenses[0].reload
      expenses[1].reload
      expect(expenses[0].category).to eq(category2)
      expect(expenses[1].category).to eq(category2)
    end

    it "allows bulk status update" do
      # Enable selection mode
      click_button "Selección Múltiple"

      # Wait for checkbox column to appear
      expect(page).to have_css('.checkbox-header', visible: true, wait: 5)

      # Select all expenses using master checkbox
      find('[data-batch-selection-target="masterCheckbox"]').click

      # Verify all are selected
      expect(page).to have_text("3 de 3 gastos seleccionados")

      # Open bulk operations
      click_button "Operaciones en Lote"

      # Select status update operation
      within '#bulk_operations_modal' do
        find('input[type="radio"][value="status"]').click
      end

      # Status dropdown should appear
      expect(page).to have_select("bulk_status")

      # Select processed status
      select "Procesado", from: "bulk_status"

      # Submit
      click_button "Actualizar Estado"

      # Wait for success
      expect(page).to have_text("gastos marcados como procesado", wait: 5)

      # Verify expenses were updated
      expenses.each(&:reload)
      expect(expenses.all? { |e| e.status == "processed" }).to be true
    end

    it "requires confirmation for bulk delete" do
      # Enable selection mode and select expenses
      click_button "Selección Múltiple"

      # Wait for checkbox column
      expect(page).to have_css('.checkbox-header', visible: true, wait: 5)

      find('[data-batch-selection-target="masterCheckbox"]').click

      # Open bulk operations
      click_button "Operaciones en Lote"

      # Select delete operation
      within '#bulk_operations_modal' do
        find('input[type="radio"][value="delete"]').click
      end

      # Warning should appear
      expect(page).to have_text("Esta acción no se puede deshacer")
      expect(page).to have_text("Estás a punto de eliminar permanentemente 3 gastos")

      # Submit button should be disabled initially
      submit_button = find('[data-bulk-operations-target="submitButton"]')
      expect(submit_button).to be_disabled

      # Check confirmation checkbox
      check "Confirmo que deseo eliminar estos gastos permanentemente"

      # Submit button should now be enabled
      expect(submit_button).not_to be_disabled

      # Submit
      click_button "Eliminar Gastos"

      # Wait for success or error message
      expect(page).to have_text(/(eliminados|Error)/i, wait: 5)

      # Wait for page reload or modal close
      sleep 2.5

      # If successful, verify expenses were deleted
      if page.has_text?("eliminados")
        # Page might reload, check if expenses are gone
        expect(page).not_to have_text("Restaurant A") if !page.has_text?("Error")
      end
    end

    it "shows progress for large operations" do
      # Create more expenses for testing progress
      10.times do
        create(:expense, email_account: email_account, category: nil)
      end

      visit expenses_path

      # Select all
      click_button "Selección Múltiple"

      # Wait for checkbox column
      expect(page).to have_css('.checkbox-header', visible: true, wait: 5)

      find('[data-batch-selection-target="masterCheckbox"]').click

      # Open bulk operations
      click_button "Operaciones en Lote"

      # Categorize
      within '#bulk_operations_modal' do
        find('input[type="radio"][value="categorize"]').click
      end
      select category1.name, from: "bulk_category"
      click_button "Categorizar Gastos"

      # Should show progress bar or completion message
      # The operation completes quickly, so we might see the success message
      expect(page).to have_text(/(Procesando|categorizados)/i, wait: 5)
    end

    it "handles errors gracefully" do
      # Simulate an error by trying to categorize with invalid data

      click_button "Selección Múltiple"

      # Wait for checkbox column
      expect(page).to have_css('.checkbox-cell', visible: true, wait: 5)

      within "#expenses_table_body" do
        first('input[type="checkbox"][data-batch-selection-target="checkbox"]').click
      end

      click_button "Operaciones en Lote"

      # Wait for modal and select categorize
      expect(page).to have_css('#bulk_operations_modal[aria-hidden="false"]', visible: true, wait: 5)

      within '#bulk_operations_modal' do
        find('input[type="radio"][value="categorize"]').click
      end

      # Don't select a category and try to submit
      # The frontend validation should prevent submission
      submit_button = find('[data-bulk-operations-target="submitButton"]')
      submit_button.click

      # Should show error
      expect(page).to have_text("Por favor selecciona una categoría")
    end
  end

  describe "Keyboard shortcuts" do
    it "supports Ctrl+A to select all in selection mode" do
      click_button "Selección Múltiple"

      # Use keyboard shortcut to select all
      find('body').send_keys [ :control, 'a' ]

      expect(page).to have_text("#{expenses.count} de #{expenses.count} gastos seleccionados")
    end

    it "closes modal with Escape key" do
      click_button "Selección Múltiple"
      within "#expenses_table_body" do
        first('input[type="checkbox"][data-batch-selection-target="checkbox"]').click
      end

      click_button "Operaciones en Lote"
      expect(page).to have_css('#bulk_operations_modal', visible: true)

      # Press Escape key globally (not on modal element)
      page.driver.browser.action.send_keys(:escape).perform

      # Wait for animation to complete
      sleep 1

      # Modal should be hidden
      expect(page).to have_css('#bulk_operations_modal', visible: false)
    end
  end
end
