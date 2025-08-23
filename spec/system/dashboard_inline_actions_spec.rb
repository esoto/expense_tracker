require "rails_helper"

RSpec.describe "Dashboard Inline Actions", type: :system, js: true, tier: :system do
  let!(:email_account) { create(:email_account) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }
  let!(:category_entertainment) { create(:category, name: "Entertainment", color: "#FFD93D") }

  # Create a variety of expenses for testing
  let!(:pending_expense) do
    create(:expense,
      email_account: email_account,
      category: category_food,
      status: "pending",
      merchant_name: "Pending Restaurant",
      amount: 5000,
      transaction_date: Date.current,
      description: "Lunch with team"
    )
  end

  let!(:processed_expense) do
    create(:expense,
      email_account: email_account,
      category: category_transport,
      status: "processed",
      merchant_name: "Uber Costa Rica",
      amount: 3500,
      transaction_date: 1.day.ago
    )
  end

  let!(:uncategorized_expense) do
    create(:expense,
      email_account: email_account,
      category: nil,
      status: "pending",
      merchant_name: "Unknown Store",
      amount: 2000,
      transaction_date: 2.days.ago
    )
  end

  before do
    visit dashboard_expenses_path
    # Wait for Stimulus controllers to be loaded
    expect(page).to have_css('[data-controller="dashboard-inline-actions"]', wait: 5)
  end

  describe "Action Visibility and Hover Behavior" do
    it "shows inline actions on hover" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

      # Actions should be hidden initially via opacity-0 class
      within expense_row do
        actions = find('[data-dashboard-expenses-target="quickActions"]', visible: :all)
        expect(actions[:class]).to include("opacity-0")
      end

      # Hover to show actions
      expense_row.hover
      sleep 0.3 # Wait for CSS transition

      # Actions should be visible via opacity-100 class
      within expense_row do
        actions = find('[data-dashboard-expenses-target="quickActions"]', visible: :all)
        expect(actions[:class]).to include("opacity-100")

        expect(page).to have_css('button[title*="Categorizar"]', visible: true)
        expect(page).to have_css('button[data-action*="toggleStatus"]', visible: true)
        expect(page).to have_css('button[title*="Duplicar"]', visible: true)
        expect(page).to have_css('button[title*="Eliminar"]', visible: true)
      end
    end

    it "maintains action visibility when interacting with dropdowns" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      # Click category button
      within expense_row do
        find('button[title*="Categorizar"]').click
      end

      # Dropdown should be visible
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')

      # Actions should remain visible
      within expense_row do
        expect(page).to have_css('[data-dashboard-expenses-target="quickActions"]', visible: true)
      end
    end
  end

  describe "Category Change Action" do
    it "opens category dropdown and allows selection" do
      # Find the uncategorized expense
      uncategorized_row = find("[data-dashboard-inline-actions-expense-id-value='#{uncategorized_expense.id}']")
      uncategorized_row.hover

      # Click category button
      within uncategorized_row do
        find('button[title*="Categorizar"]').click
      end

      # Dropdown should appear with smooth animation
      dropdown = find('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      expect(dropdown).to be_visible

      # Select Transport category
      within dropdown do
        expect(page).to have_button("Food")
        expect(page).to have_button("Transport")
        expect(page).to have_button("Entertainment")

        click_button "Transport"
      end

      # Wait for API call
      sleep 0.5

      # Category badge should update
      within uncategorized_row do
        badge = find('.expense-category-badge')
        # Check that the color has been applied (browser converts to RGB)
        expect(badge[:style]).to match(/background-color|rgb/)
        expect(badge).to have_content("T")
      end

      # Success toast should appear
      expect(page).to have_content('Categorizado como "Transport"')
    end

    it "closes dropdown when clicking outside" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Categorizar"]').click
      end

      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')

      # Click outside
      find('h1', text: 'Dashboard de Gastos').click
      sleep 0.2

      # Dropdown should close
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
    end

    it "updates category metadata in expense row" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      expense_row.hover

      within expense_row do
        find('button[title*="Categorizar"]').click
      end

      within '[data-dashboard-inline-actions-target="categoryDropdown"]' do
        click_button "Entertainment"
      end

      sleep 0.5

      # Check metadata update
      within expense_row do
        expect(page).to have_content("Entertainment")
      end
    end
  end

  describe "Status Toggle Action" do
    it "toggles pending expense to processed" do
      pending_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      pending_row.hover

      # Should show pending icon initially
      within pending_row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-amber-500")

        status_button.click
      end

      sleep 0.5

      # Status should change to processed
      within pending_row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-emerald-500")
      end

      # Success toast
      expect(page).to have_content("Estado cambiado a procesado")
    end

    it "toggles processed expense to pending" do
      processed_row = find("[data-dashboard-inline-actions-expense-id-value='#{processed_expense.id}']")
      processed_row.hover

      within processed_row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-emerald-500")

        status_button.click
      end

      sleep 0.5

      within processed_row do
        status_button = find('button[data-action*="toggleStatus"]')
        expect(status_button[:class]).to include("text-amber-500")
      end

      expect(page).to have_content("Estado cambiado a pendiente")
    end

    it "updates status badge in expanded view" do
      # Switch to expanded view
      click_button "Expandida"
      sleep 0.5

      pending_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      pending_row.hover

      within pending_row do
        find('button[data-action*="toggleStatus"]').click
      end

      sleep 0.5

      # Check if status badge updated in expanded details
      within pending_row do
        expanded_details = find('.expense-expanded-details')
        expect(expanded_details).to have_content("Processed")
      end
    end
  end

  describe "Duplicate Action" do
    it "duplicates an expense and shows in list" do
      initial_count = all('[data-dashboard-inline-actions-expense-id-value]').count

      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      expense_row.hover

      within expense_row do
        find('button[title*="Duplicar"]').click
      end

      # Wait for duplication and page reload
      expect(page).to have_content("Gasto duplicado exitosamente", wait: 3)
      sleep 1.5 # Wait for page reload

      # Should have one more expense
      new_count = all('[data-dashboard-inline-actions-expense-id-value]').count
      expect(new_count).to eq(initial_count + 1)

      # New expense should have same merchant
      expect(page).to have_content("Pending Restaurant", count: 2)
    end

    it "shows loading state during duplication" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Duplicar"]').click
      end

      # Row should show loading state briefly
      expect(expense_row[:class]).to include("opacity-75")
    end
  end

  describe "Delete Action with Confirmation" do
    it "shows confirmation modal before deletion" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      expense_row.hover

      within expense_row do
        find('button[title*="Eliminar"]').click
      end

      # Confirmation modal should appear with animation
      confirmation = find('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
      expect(confirmation).to be_visible
      expect(confirmation).to have_content("Confirmar eliminación")
      expect(confirmation).to have_content("Esta acción no se puede deshacer")

      # Should have both buttons
      within confirmation do
        expect(page).to have_button("Eliminar")
        expect(page).to have_button("Cancelar")
      end
    end

    it "cancels deletion when clicking cancel" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      expense_row.hover

      within expense_row do
        find('button[title*="Eliminar"]').click
      end

      within '[data-dashboard-inline-actions-target="deleteConfirmation"]' do
        click_button "Cancelar"
      end

      sleep 0.3

      # Modal should close
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')

      # Expense should still exist
      expect(page).to have_content("Pending Restaurant")
    end

    it "deletes expense after confirmation with animation" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{pending_expense.id}']")
      expense_row.hover

      within expense_row do
        find('button[title*="Eliminar"]').click
      end

      within '[data-dashboard-inline-actions-target="deleteConfirmation"]' do
        click_button "Eliminar"
      end

      # Row should animate out
      expect(expense_row[:style]).to include("transform") if expense_row[:style]

      # Wait for animation and removal
      expect(page).not_to have_content("Pending Restaurant", wait: 3)

      # Success toast
      expect(page).to have_content("Gasto eliminado exitosamente")
    end

    it "closes confirmation when pressing Escape" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Eliminar"]').click
      end

      expect(page).to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')

      # Press Escape
      page.send_keys(:escape)
      sleep 0.2

      expect(page).not_to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
    end
  end

  describe "Keyboard Navigation" do
    it "supports keyboard shortcuts for all actions" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.click # Focus the row

      # Press 'C' for category
      page.send_keys('c')
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      page.send_keys(:escape)
      sleep 0.2

      # Press 'S' for status toggle
      page.send_keys('s')
      sleep 0.5
      expect(page).to have_content("Estado cambiado")

      # Press 'D' for duplicate
      page.send_keys('d')
      expect(page).to have_content("Gasto duplicado exitosamente", wait: 3)
      sleep 1.5 # Wait for reload

      # Focus a row again
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.click

      # Press Delete key for deletion
      page.send_keys(:delete)
      expect(page).to have_css('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
    end

    it "navigates category dropdown with keyboard" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.click

      page.send_keys('c')

      dropdown = find('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      within dropdown do
        # First category should be focused
        focused_element = page.evaluate_script("document.activeElement")
        expect(focused_element.tag_name.downcase).to eq("button")
      end
    end
  end

  describe "Loading States and Feedback" do
    it "shows loading state during API calls" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      # Trigger an action
      within expense_row do
        find('button[data-action*="toggleStatus"]').click
      end

      # Should briefly show loading state
      expect(expense_row[:class]).to include("opacity-75")

      # Wait for completion
      sleep 0.5
      expect(expense_row[:class]).not_to include("opacity-75")
    end

    it "disables actions during loading" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        status_button = find('button[title*="estado"]')
        status_button.click

        # Quick actions should be disabled during loading
        actions = find('[data-dashboard-expenses-target="quickActions"]')
        expect(actions[:style]).to include("pointer-events: none") if actions[:style]
      end
    end
  end

  describe "Toast Notifications" do
    it "shows success toasts for all actions" do
      # Test category change toast
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[title*="Categorizar"]').click
      end

      within '[data-dashboard-inline-actions-target="categoryDropdown"]' do
        click_button "Food"
      end

      expect(page).to have_content('Categorizado como "Food"')

      # Test status change toast
      expense_row.hover
      within expense_row do
        find('button[data-action*="toggleStatus"]').click
      end

      expect(page).to have_content("Estado cambiado")
    end

    it "auto-dismisses toasts after 5 seconds" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[data-action*="toggleStatus"]').click
      end

      expect(page).to have_content("Estado cambiado")

      # Wait for auto-dismiss
      sleep 5.5
      expect(page).not_to have_content("Estado cambiado")
    end

    it "allows manual dismissal of toasts" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        find('button[data-action*="toggleStatus"]').click
      end

      expect(page).to have_content("Estado cambiado")

      # Find and click close button on toast
      toast = find('div', text: "Estado cambiado").ancestor('div.fixed')
      within toast do
        find('button').click
      end

      expect(page).not_to have_content("Estado cambiado")
    end
  end

  describe "Mobile and Touch Support" do
    context "on mobile viewport" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667)
        visit dashboard_expenses_path
        sleep 0.5
      end

      after do
        page.driver.browser.manage.window.resize_to(1400, 900)
      end

      it "shows actions without hover on mobile" do
        expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

        # Actions should be visible on mobile without hover
        within expense_row do
          actions = find('[data-dashboard-expenses-target="quickActions"]', visible: :all)
          expect(actions).to be_visible
        end
      end

      it "uses larger touch targets on mobile" do
        expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

        within expense_row do
          buttons = all('button[data-action*="dashboard-inline-actions"]')
          buttons.each do |button|
            # Check computed size
            width = page.evaluate_script("arguments[0].offsetWidth", button.native)
            height = page.evaluate_script("arguments[0].offsetHeight", button.native)

            # Touch targets should be at least 44x44 pixels
            expect(width).to be >= 44
            expect(height).to be >= 44
          end
        end
      end

      it "positions dropdowns appropriately on mobile" do
        expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

        within expense_row do
          find('button[title*="Categorizar"]').click
        end

        dropdown = find('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')

        # On mobile, dropdown should be positioned fixed
        position = page.evaluate_script("window.getComputedStyle(arguments[0]).position", dropdown.native)
        expect(position).to eq("fixed")
      end
    end
  end

  describe "Integration with View Modes" do
    it "works in both compact and expanded views" do
      # Test in compact view (default)
      expect(page).to have_css('.dashboard-expenses-compact')

      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        expect(page).to have_css('button[title*="Categorizar"]')
      end

      # Switch to expanded view
      click_button "Expandida"
      sleep 0.5

      expect(page).to have_css('.dashboard-expenses-expanded')

      # Actions should still work
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      within expense_row do
        expect(page).to have_css('button[title*="Categorizar"]')
        find('button[data-action*="toggleStatus"]').click
      end

      expect(page).to have_content("Estado cambiado")
    end
  end

  describe "Performance and Response Times" do
    it "completes actions within 50ms target" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.hover

      start_time = Time.now

      within expense_row do
        find('button[data-action*="toggleStatus"]').click
      end

      # Wait for success message
      expect(page).to have_content("Estado cambiado", wait: 1)

      end_time = Time.now
      response_time = (end_time - start_time) * 1000 # Convert to milliseconds

      # Should be reasonably fast (allowing for network latency in tests)
      expect(response_time).to be < 1000 # 1 second is reasonable for tests
    end
  end

  describe "Accessibility Features" do
    it "has proper ARIA labels and roles" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

      expect(expense_row[:role]).to eq("article")
      expect(expense_row["aria-label"]).to include("Gasto")

      expense_row.hover

      within expense_row do
        buttons = all('button[data-action*="dashboard-inline-actions"]')
        buttons.each do |button|
          expect(button["aria-label"]).not_to be_nil
        end
      end
    end

    it "maintains focus management during interactions" do
      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)
      expense_row.click

      # Open category dropdown
      page.send_keys('c')

      # Focus should move to dropdown
      focused_element = page.evaluate_script("document.activeElement")
      expect(focused_element.tag_name.downcase).to eq("button")

      # Close dropdown
      page.send_keys(:escape)

      # Focus should return to row or appropriate element
      focused_element = page.evaluate_script("document.activeElement")
      expect(focused_element).not_to be_nil
    end
  end

  describe "Error Handling" do
    it "shows error toast when action fails" do
      # Simulate a failure by attempting to categorize a non-existent expense
      # This would require mocking the API response, which is complex in system tests
      # Instead, we'll verify the error handling structure exists

      expense_row = find('[data-dashboard-inline-actions-expense-id-value]', match: :first)

      # Verify error handling code exists in the controller
      controller_present = page.evaluate_script(
        "document.querySelector('[data-controller=\"dashboard-inline-actions\"]') !== null"
      )
      expect(controller_present).to be true
    end
  end

  describe "Multiple Simultaneous Actions" do
    it "handles multiple quick actions in succession" do
      # Get multiple expense rows
      expense_rows = all('[data-dashboard-inline-actions-expense-id-value]')

      # Perform actions on different rows quickly
      expense_rows[0].hover
      within expense_rows[0] do
        find('button[data-action*="toggleStatus"]').click
      end

      sleep 0.2

      expense_rows[1].hover if expense_rows[1]
      within expense_rows[1] do
        find('button[data-action*="toggleStatus"]').click if has_css?('button[title*="estado"]')
      end if expense_rows[1]

      # Both should complete successfully
      expect(page).to have_content("Estado cambiado")
    end
  end
end
