require 'rails_helper'

RSpec.describe "Dashboard Bulk Operations", type: :system, js: true do
  let(:email_account) { create(:email_account) }
  let(:category1) { create(:category, name: "Food", color: "#FF5733") }
  let(:category2) { create(:category, name: "Transport", color: "#33FF57") }
  let(:category3) { create(:category, name: "Entertainment", color: "#3357FF") }
  
  let!(:expenses) do
    [
      create(:expense, email_account: email_account, merchant_name: "Restaurant A", amount: 50.00, status: "pending", category: nil),
      create(:expense, email_account: email_account, merchant_name: "Uber Ride", amount: 25.00, status: "processed", category: category1),
      create(:expense, email_account: email_account, merchant_name: "Movie Theater", amount: 35.00, status: "pending", category: nil),
      create(:expense, email_account: email_account, merchant_name: "Grocery Store", amount: 80.00, status: "processed", category: category2),
      create(:expense, email_account: email_account, merchant_name: "Gas Station", amount: 45.00, status: "pending", category: nil)
    ]
  end
  
  before do
    # Ensure categories exist
    category1
    category2
    category3
    
    visit dashboard_expenses_path
    # Wait for page to load
    expect(page).to have_css('.dashboard-expense-row', wait: 5)
  end
  
  describe "Selection Mode" do
    it "enables selection mode when clicking the batch selection button" do
      # Click batch selection toggle
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Verify selection mode is active
      expect(page).to have_css('.selection-mode-active')
      expect(page).to have_css('[data-dashboard-expenses-target="selectionToolbar"]')
      expect(page).to have_css('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]', visible: true, count: 5)
    end
    
    it "shows selection toolbar with bulk action buttons" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Check toolbar elements
      within '[data-dashboard-expenses-target="selectionToolbar"]' do
        expect(page).to have_css('[data-dashboard-expenses-target="selectAllCheckbox"]')
        expect(page).to have_text('0 seleccionados')
        expect(page).to have_button('Categorizar')
        expect(page).to have_button('Estado')
        expect(page).to have_button('Eliminar')
      end
    end
    
    it "selects individual expenses" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Select first two expenses
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click
      checkboxes[1].click
      
      # Verify selection count
      expect(page).to have_text('2 seleccionados')
      expect(page).to have_css('.dashboard-expense-row.selected', count: 2)
    end
    
    it "selects all visible expenses" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Click select all
      find('[data-dashboard-expenses-target="selectAllCheckbox"]').click
      
      # Verify all are selected
      expect(page).to have_text('5 seleccionados')
      expect(page).to have_css('.dashboard-expense-row.selected', count: 5)
    end
    
    it "exits selection mode with Escape key" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      expect(page).to have_css('.selection-mode-active')
      
      # Press Escape
      find('body').send_keys(:escape)
      
      # Verify selection mode is disabled
      expect(page).not_to have_css('.selection-mode-active')
      expect(page).not_to have_css('[data-dashboard-expenses-target="selectionToolbar"]', visible: true)
    end
  end
  
  describe "Bulk Categorization" do
    before do
      # Enable selection mode and select uncategorized expenses
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click # Restaurant A (uncategorized)
      checkboxes[2].click # Movie Theater (uncategorized)
      checkboxes[4].click # Gas Station (uncategorized)
    end
    
    it "shows bulk categorize modal" do
      # Click categorize button
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Verify modal appears
      expect(page).to have_css('.bulk-modal-overlay[data-bulk-modal="categorize"]')
      within '.bulk-modal-container' do
        expect(page).to have_text('Categorizar Gastos')
        expect(page).to have_text('3 gastos')
        expect(page).to have_select('category_id')
        expect(page).to have_button('Aplicar Categoría')
        expect(page).to have_button('Cancelar')
      end
    end
    
    it "applies category to selected expenses" do
      # Mock the bulk categorize endpoint
      allow_any_instance_of(BulkOperations::CategorizationService).to receive(:call).and_return({
        success: true,
        message: "3 gastos categorizados exitosamente",
        affected_count: 3
      })
      
      # Click categorize button
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Select category and apply
      within '.bulk-modal-container' do
        select 'Food', from: 'category_id'
        click_button 'Aplicar Categoría'
      end
      
      # Verify success toast
      expect(page).to have_text('3 gastos categorizados exitosamente')
      
      # Verify modal closes and selection mode exits
      expect(page).not_to have_css('.bulk-modal-overlay')
      expect(page).not_to have_css('.selection-mode-active')
    end
    
    it "closes modal with Escape key" do
      # Open modal
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      expect(page).to have_css('.bulk-modal-overlay')
      
      # Press Escape
      find('body').send_keys(:escape)
      
      # Verify modal closes
      expect(page).not_to have_css('.bulk-modal-overlay')
    end
  end
  
  describe "Bulk Status Update" do
    before do
      # Enable selection mode and select expenses
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click # pending
      checkboxes[2].click # pending
    end
    
    it "shows bulk status update modal" do
      # Click status button
      find('[data-action="click->dashboard-expenses#bulkUpdateStatus"]').click
      
      # Verify modal appears
      expect(page).to have_css('.bulk-modal-overlay[data-bulk-modal="status"]')
      within '.bulk-modal-container' do
        expect(page).to have_text('Actualizar Estado')
        expect(page).to have_text('2 gastos')
        expect(page).to have_css('input[type="radio"][value="pending"]')
        expect(page).to have_css('input[type="radio"][value="processed"]')
        expect(page).to have_button('Actualizar Estado')
      end
    end
    
    it "updates status of selected expenses" do
      # Mock the bulk status update endpoint
      allow_any_instance_of(BulkOperations::StatusUpdateService).to receive(:call).and_return({
        success: true,
        message: "2 gastos actualizados exitosamente",
        affected_count: 2
      })
      
      # Click status button
      find('[data-action="click->dashboard-expenses#bulkUpdateStatus"]').click
      
      # Select processed status and apply
      within '.bulk-modal-container' do
        choose 'processed'
        click_button 'Actualizar Estado'
      end
      
      # Verify success toast
      expect(page).to have_text('2 gastos actualizados exitosamente')
      
      # Verify modal closes
      expect(page).not_to have_css('.bulk-modal-overlay')
    end
  end
  
  describe "Bulk Deletion" do
    before do
      # Enable selection mode and select expenses
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click
      checkboxes[1].click
    end
    
    it "shows bulk delete confirmation modal" do
      # Click delete button
      find('[data-action="click->dashboard-expenses#bulkDelete"]').click
      
      # Verify modal appears
      expect(page).to have_css('.bulk-modal-overlay[data-bulk-modal="delete"]')
      within '.bulk-modal-container' do
        expect(page).to have_text('Confirmar Eliminación')
        expect(page).to have_text('2 gastos')
        expect(page).to have_text('Esta acción no se puede deshacer')
        expect(page).to have_button('Eliminar 2 Gastos')
        expect(page).to have_button('Cancelar')
      end
    end
    
    it "deletes selected expenses with confirmation" do
      # Mock the bulk delete endpoint
      allow_any_instance_of(BulkOperations::DeletionService).to receive(:call).and_return({
        success: true,
        message: "2 gastos eliminados exitosamente",
        affected_count: 2
      })
      
      # Click delete button
      find('[data-action="click->dashboard-expenses#bulkDelete"]').click
      
      # Confirm deletion
      within '.bulk-modal-container' do
        click_button 'Eliminar 2 Gastos'
      end
      
      # Verify success toast
      expect(page).to have_text('2 gastos eliminados exitosamente')
      
      # Verify expenses are removed from DOM
      expect(page).to have_css('.dashboard-expense-row', count: 3)
      
      # Verify modal closes and selection mode exits
      expect(page).not_to have_css('.bulk-modal-overlay')
      expect(page).not_to have_css('.selection-mode-active')
    end
    
    it "cancels deletion when clicking cancel" do
      # Click delete button
      find('[data-action="click->dashboard-expenses#bulkDelete"]').click
      
      # Click cancel
      within '.bulk-modal-container' do
        click_button 'Cancelar'
      end
      
      # Verify modal closes but expenses remain
      expect(page).not_to have_css('.bulk-modal-overlay')
      expect(page).to have_css('.dashboard-expense-row', count: 5)
      
      # Selection mode should still be active
      expect(page).to have_css('.selection-mode-active')
    end
  end
  
  describe "Keyboard Shortcuts" do
    it "toggles selection mode with Ctrl+Shift+S" do
      # Press Ctrl+Shift+S
      find('body').send_keys([:control, :shift, 's'])
      
      # Verify selection mode is enabled
      expect(page).to have_css('.selection-mode-active')
      
      # Press again to disable
      find('body').send_keys([:control, :shift, 's'])
      
      # Verify selection mode is disabled
      expect(page).not_to have_css('.selection-mode-active')
    end
    
    it "selects all with Ctrl+A in selection mode" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Press Ctrl+A
      find('body').send_keys([:control, 'a'])
      
      # Verify all are selected
      expect(page).to have_text('5 seleccionados')
    end
  end
  
  describe "Performance" do
    it "handles bulk operations within 50ms" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Select all
      find('[data-dashboard-expenses-target="selectAllCheckbox"]').click
      
      # Measure bulk categorize performance
      start_time = Time.now
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      modal_load_time = (Time.now - start_time) * 1000
      
      expect(modal_load_time).to be < 50
      
      # Close modal
      find('body').send_keys(:escape)
    end
  end
  
  describe "Toast Notifications" do
    it "shows appropriate toast messages for operations" do
      # Enable selection mode without selecting anything
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Try to categorize without selection
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Should show warning toast
      expect(page).to have_css('#toast-container')
      expect(page).to have_text('Por favor selecciona al menos un gasto')
    end
    
    it "auto-dismisses toast after 5 seconds" do
      # Enable selection mode and trigger a toast
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Verify toast appears
      expect(page).to have_css('#toast-container')
      
      # Wait for auto-dismiss
      sleep 5.5
      
      # Verify toast is gone
      expect(page).not_to have_css('#toast-container')
    end
  end
  
  describe "Mobile Responsiveness" do
    it "adjusts modal layout for mobile" do
      # Simulate mobile viewport
      page.driver.browser.manage.window.resize_to(375, 667)
      
      # Enable selection mode and open modal
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Verify mobile-optimized layout
      within '.bulk-modal-container' do
        # Buttons should be full width on mobile
        expect(page).to have_css('button.w-full')
      end
      
      # Reset viewport
      page.driver.browser.manage.window.resize_to(1024, 768)
    end
  end
  
  describe "Accessibility" do
    it "supports screen reader announcements" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Check for ARIA live region
      expect(page).to have_css('[role="status"][aria-live="polite"]', visible: false)
      
      # Select an expense
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click
      
      # Should announce selection
      live_region = find('[role="status"][aria-live="polite"]', visible: false)
      expect(live_region.text).to include('1 elemento seleccionado')
    end
    
    it "has proper ARIA labels on buttons" do
      # Enable selection mode
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      
      # Check ARIA labels
      expect(page).to have_css('input[aria-label*="Seleccionar"]')
      expect(page).to have_css('[aria-label="Seleccionar todos"]')
    end
    
    it "supports keyboard navigation in modals" do
      # Enable selection mode and open modal
      find('[data-action="click->dashboard-expenses#toggleSelectionMode"]').click
      checkboxes = all('input[type="checkbox"][data-dashboard-expenses-target="selectionCheckbox"]')
      checkboxes[0].click
      find('[data-action="click->dashboard-expenses#bulkCategorize"]').click
      
      # Tab through modal elements
      within '.bulk-modal-container' do
        select_element = find('select[name="category_id"]')
        select_element.send_keys(:tab)
        
        # Should focus on cancel button
        expect(page).to have_css('button:focus', text: 'Cancelar')
      end
    end
  end
  
end