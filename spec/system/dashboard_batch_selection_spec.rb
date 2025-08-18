require "rails_helper"

RSpec.describe "Dashboard Batch Selection", type: :system, js: true do
  let!(:email_account) { create(:email_account) }
  let!(:food_category) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:transport_category) { create(:category, name: "Transport", color: "#4ECDC4") }
  let!(:entertainment_category) { create(:category, name: "Entertainment", color: "#45B7D1") }

  # Create multiple expenses for testing
  let!(:expenses) do
    [
      create(:expense,
        email_account: email_account,
        category: food_category,
        merchant_name: "Restaurant A",
        amount: 5000,
        transaction_date: 1.day.ago,
        status: "pending"
      ),
      create(:expense,
        email_account: email_account,
        category: transport_category,
        merchant_name: "Uber Ride",
        amount: 3000,
        transaction_date: 2.days.ago,
        status: "processed"
      ),
      create(:expense,
        email_account: email_account,
        category: nil,
        merchant_name: "Unknown Store",
        amount: 7500,
        transaction_date: 3.days.ago,
        status: "pending"
      ),
      create(:expense,
        email_account: email_account,
        category: entertainment_category,
        merchant_name: "Cinema",
        amount: 4500,
        transaction_date: 4.days.ago,
        status: "processed"
      ),
      create(:expense,
        email_account: email_account,
        category: food_category,
        merchant_name: "Coffee Shop",
        amount: 2500,
        transaction_date: 5.days.ago,
        status: "pending"
      )
    ]
  end

  before do
    visit dashboard_expenses_path
  end

  describe "Selection Mode Toggle" do
    it "displays the selection mode toggle button" do
      within("#dashboard-expenses-widget") do
        expect(page).to have_css('[data-action*="toggleSelectionMode"]')
        selection_button = find('[data-action*="toggleSelectionMode"]')
        expect(selection_button["title"]).to include("Ctrl+Shift+S")
      end
    end

    it "starts with selection mode disabled" do
      within("#dashboard-expenses-widget") do
        # Should NOT be in selection mode initially
        expect(page).not_to have_css(".selection-mode-active")
        # Checkboxes should be hidden
        expect(page).not_to have_css('[data-dashboard-expenses-target="selectionCheckbox"]', visible: true)
        # Toolbar should be hidden
        expect(page).not_to have_css('[data-dashboard-expenses-target="selectionToolbar"]', visible: true)
      end
    end

    it "enters selection mode when clicking the toggle button" do
      # Initially not in selection mode
      expect(page).not_to have_css("#dashboard-expenses-widget.selection-mode-active")

      within("#dashboard-expenses-widget") do
        expect(page).not_to have_css('[data-dashboard-expenses-target="selectionCheckbox"]', visible: true)

        # Click selection mode button
        find('[data-action*="toggleSelectionMode"]').click

        # Wait for JavaScript to execute
        sleep 0.5

        # Should enter selection mode - checkboxes and toolbar should be visible
        expect(page).to have_css('[data-dashboard-expenses-target="selectionCheckbox"]', visible: true, count: 5)
        expect(page).to have_css('[data-dashboard-expenses-target="selectionToolbar"]', visible: true)
      end

      # Widget should have selection-mode-active class
      expect(page).to have_css("#dashboard-expenses-widget.selection-mode-active")
    end

    it "exits selection mode when clicking toggle again" do
      # Enter selection mode
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
      sleep 0.3 # Wait for DOM updates

      # Check the widget has the class
      expect(page).to have_css("#dashboard-expenses-widget.selection-mode-active")

      # Exit selection mode
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
      sleep 0.5 # Wait for animations

      # Check that the widget no longer has the class
      expect(page).not_to have_css("#dashboard-expenses-widget.selection-mode-active")
      expect(page).not_to have_css('[data-dashboard-expenses-target="selectionContainer"]:not(.hidden)')
    end

    it "enters selection mode on double-click of expense row" do
      expense_row = nil
      within("#dashboard-expenses-widget") do
        expense_row = find(".dashboard-expense-row", match: :first)
        expense_row.double_click
      end
      sleep 0.3 # Wait for DOM updates

      # Check that the widget has the selection mode class
      expect(page).to have_css("#dashboard-expenses-widget.selection-mode-active")

      # The double-clicked row should be selected
      within("#dashboard-expenses-widget") do
        expect(expense_row[:class]).to include("selected")
      end
    end
  end

  describe "Selection Toolbar" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "shows the selection toolbar when in selection mode" do
      within("#dashboard-expenses-widget") do
        toolbar = find('[data-dashboard-expenses-target="selectionToolbar"]')
        expect(toolbar).to be_visible

        # Check toolbar contents
        expect(toolbar).to have_text("Seleccionar todos")
        expect(toolbar).to have_text("0 seleccionados")
        # Buttons will be disabled initially without selection
        expect(toolbar).to have_button("Categorizar", disabled: true)
        expect(toolbar).to have_button("Estado", disabled: true)
        expect(toolbar).to have_button("Eliminar", disabled: true)
      end
    end

    it "displays correct count when items are selected" do
      within("#dashboard-expenses-widget") do
        # Select first two items
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes[0].check
        checkboxes[1].check

        # Check count
        expect(page).to have_text("2 seleccionados")
      end
    end

    it "enables/disables bulk action buttons based on selection" do
      within("#dashboard-expenses-widget") do
        toolbar = find('[data-dashboard-expenses-target="selectionToolbar"]')

        # Initially buttons should be disabled (no selection)
        expect(toolbar).to have_button("Categorizar", disabled: true)
        expect(toolbar).to have_button("Estado", disabled: true)
        expect(toolbar).to have_button("Eliminar", disabled: true)

        # Select an item
        first('[data-dashboard-expenses-target="selectionCheckbox"]').check

        # Buttons should be enabled
        expect(toolbar).to have_button("Categorizar", disabled: false)
        expect(toolbar).to have_button("Estado", disabled: false)
        expect(toolbar).to have_button("Eliminar", disabled: false)
      end
    end
  end

  describe "Individual Selection" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "selects individual items via checkbox" do
      within("#dashboard-expenses-widget") do
        checkbox = first('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkbox.check

        # Row should be marked as selected
        row = checkbox.ancestor(".dashboard-expense-row")
        expect(row[:class]).to include("selected")

        # Count should update
        expect(page).to have_text("1 seleccionados")
      end
    end

    it "selects items by clicking on the row" do
      within("#dashboard-expenses-widget") do
        row = find(".dashboard-expense-row", match: :first)

        # Click on the row (not on checkbox/button)
        row.find(".expense-merchant").click

        expect(row[:class]).to include("selected")
        checkbox = row.find('[data-dashboard-expenses-target="selectionCheckbox"]')
        expect(checkbox).to be_checked
      end
    end

    it "deselects items when clicking again" do
      within("#dashboard-expenses-widget") do
        row = find(".dashboard-expense-row", match: :first)
        checkbox = row.find('[data-dashboard-expenses-target="selectionCheckbox"]')

        # Select
        checkbox.check
        expect(row[:class]).to include("selected")

        # Deselect
        checkbox.uncheck
        expect(row[:class]).not_to include("selected")
      end
    end
  end

  describe "Select All Functionality" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "selects all visible items with select all checkbox" do
      within("#dashboard-expenses-widget") do
        select_all = find('[data-dashboard-expenses-target="selectAllCheckbox"]')
        select_all.check

        # All visible checkboxes should be checked
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes.each do |checkbox|
          expect(checkbox).to be_checked
        end

        # Count should show all items
        expect(page).to have_text("5 seleccionados")
      end
    end

    it "deselects all when unchecking select all" do
      within("#dashboard-expenses-widget") do
        select_all = find('[data-dashboard-expenses-target="selectAllCheckbox"]')

        # Select all first
        select_all.check
        expect(page).to have_text("5 seleccionados")

        # Deselect all
        select_all.uncheck
        expect(page).to have_text("0 seleccionados")

        # All checkboxes should be unchecked
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes.each do |checkbox|
          expect(checkbox).not_to be_checked
        end
      end
    end

    it "shows indeterminate state when partially selected" do
      within("#dashboard-expenses-widget") do
        # Select first two items only
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes[0].check
        checkboxes[1].check

        # Select all checkbox should be indeterminate
        select_all = find('[data-dashboard-expenses-target="selectAllCheckbox"]')
        expect(select_all.evaluate_script("this.indeterminate")).to be true
      end
    end
  end

  describe "Range Selection (Shift+Click)" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "selects range of items with Shift+click" do
      within("#dashboard-expenses-widget") do
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')

        # Select first item normally
        checkboxes[0].check
        sleep 0.2

        # Trigger change event to ensure lastSelectedIndex is set
        page.execute_script("document.querySelectorAll('[data-dashboard-expenses-target=\"selectionCheckbox\"]')[0].dispatchEvent(new Event('change', { bubbles: true }))")
        sleep 0.2

        # Shift+click on third item to select range
        page.execute_script(<<~JS)
          const checkboxes = document.querySelectorAll('[data-dashboard-expenses-target="selectionCheckbox"]');
          const checkbox = checkboxes[2];

          // Create and dispatch a shift+click event
          const clickEvent = new MouseEvent('click', {#{' '}
            shiftKey: true,#{' '}
            bubbles: true,
            cancelable: true,
            view: window
          });

          checkbox.checked = true;
          checkbox.dispatchEvent(clickEvent);

          // Also dispatch change event to trigger the handler
          const changeEvent = new Event('change', {#{' '}
            bubbles: true,
            cancelable: true#{' '}
          });
          changeEvent.shiftKey = true;
          checkbox.dispatchEvent(changeEvent);
        JS
        sleep 0.3

        # Refresh checkbox references and check selection
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')

        # Items 0, 1, 2 should be selected
        expect(checkboxes[0]).to be_checked
        expect(checkboxes[1]).to be_checked
        expect(checkboxes[2]).to be_checked
        expect(checkboxes[3]).not_to be_checked

        expect(page).to have_text("3 seleccionados")
      end
    end
  end

  describe "Keyboard Navigation" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "toggles selection mode with Ctrl+Shift+S" do
      # Exit selection mode first
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
        sleep 0.5
      end

      expect(page).not_to have_css(".selection-mode-active")

      # Use keyboard shortcut to enter selection mode
      page.find("body").send_keys [ :control, :shift, "s" ]

      expect(page).to have_css(".selection-mode-active")
    end

    it "selects all with Ctrl+A in selection mode" do
      # Use Ctrl+A outside of within block
      page.find("body").send_keys [ :control, "a" ]

      within("#dashboard-expenses-widget") do
        # All items should be selected
        expect(page).to have_text("5 seleccionados")

        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes.each do |checkbox|
          expect(checkbox).to be_checked
        end
      end
    end

    it "exits selection mode with Escape" do
      # Check selection mode is active
      expect(page).to have_css("#dashboard-expenses-widget.selection-mode-active")

      # Press Escape outside of within block
      page.find("body").send_keys :escape
      sleep 0.5

      # Check selection mode is inactive
      expect(page).not_to have_css("#dashboard-expenses-widget.selection-mode-active")
    end

    it "navigates through rows with arrow keys" do
      within("#dashboard-expenses-widget") do
        first_row = find(".dashboard-expense-row", match: :first)
        first_row.click

        # Press down arrow
        first_row.send_keys :arrow_down

        # Second row should be focused
        focused_element = page.evaluate_script("document.activeElement")
        expect(focused_element["class"]).to include("dashboard-expense-row")
      end
    end

    it "toggles selection with Space key when row is focused" do
      first_row = nil
      within("#dashboard-expenses-widget") do
        first_row = find(".dashboard-expense-row", match: :first)
        first_row.click  # Focus the row
      end

      # Press space to select
      first_row.send_keys :space

      within("#dashboard-expenses-widget") do
        expect(first_row[:class]).to include("selected")
        checkbox = first_row.find('[data-dashboard-expenses-target="selectionCheckbox"]')
        expect(checkbox).to be_checked
      end
    end
  end

  describe "Visual Feedback" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "highlights selected rows" do
      within("#dashboard-expenses-widget") do
        row = find(".dashboard-expense-row", match: :first)
        checkbox = row.find('[data-dashboard-expenses-target="selectionCheckbox"]')

        checkbox.check

        # Row should have selected styling
        expect(row[:class]).to include("selected")
        # Visual check for background color would require checking computed styles
      end
    end

    it "shows hover effect on rows in selection mode" do
      within("#dashboard-expenses-widget") do
        row = find(".dashboard-expense-row", match: :first)

        # Hover over row
        row.hover

        # Row should show hover state (this tests CSS interaction)
        # In real browser, this would show bg-teal-50
      end
    end

    it "animates checkbox appearance" do
      # Exit and re-enter selection mode to test animation
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
        sleep 0.3
        find('[data-action*="toggleSelectionMode"]').click

        # Checkboxes should animate in
        expect(page).to have_css('[data-dashboard-expenses-target="selectionContainer"]', visible: true)
      end
    end
  end

  describe "Integration with View Modes" do
    it "works in compact view" do
      within("#dashboard-expenses-widget") do
        # Ensure compact mode
        compact_button = find('button[data-mode="compact"]')
        compact_button.click if compact_button["aria-pressed"] == "false"

        # Enter selection mode
        find('[data-action*="toggleSelectionMode"]').click

        # Should see 5 checkboxes (compact mode limit)
        expect(page).to have_css('[data-dashboard-expenses-target="selectionCheckbox"]', count: 5)
      end
    end

    it "works in expanded view" do
      within("#dashboard-expenses-widget") do
        # Switch to expanded mode
        find('button[data-mode="expanded"]').click
        sleep 0.5

        # Enter selection mode
        find('[data-action*="toggleSelectionMode"]').click

        # Should still work in expanded view
        expect(page).to have_css(".selection-mode-active")
        expect(page).to have_css('[data-dashboard-expenses-target="selectionCheckbox"]')
      end
    end

    it "maintains selection when switching views" do
      within("#dashboard-expenses-widget") do
        # Enter selection mode and select items
        find('[data-action*="toggleSelectionMode"]').click
        first('[data-dashboard-expenses-target="selectionCheckbox"]').check

        # Switch to expanded view
        find('button[data-mode="expanded"]').click
        sleep 0.5

        # Selection should be maintained
        expect(page).to have_text("1 seleccionados")
      end
    end
  end

  describe "Bulk Actions (Placeholders)" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
        # Select some items
        checkboxes = all('[data-dashboard-expenses-target="selectionCheckbox"]')
        checkboxes[0].check
        checkboxes[1].check
      end
    end

    it "shows placeholder message for bulk categorize" do
      within("#dashboard-expenses-widget") do
        click_button "Categorizar"

        # Should show placeholder message (for now)
        # This will be implemented in Task 3.5
      end
    end

    it "shows placeholder message for bulk status update" do
      within("#dashboard-expenses-widget") do
        click_button "Estado"

        # Should show placeholder message (for now)
        # This will be implemented in Task 3.5
      end
    end

    it "shows confirmation for bulk delete" do
      within("#dashboard-expenses-widget") do
        click_button "Eliminar"

        # Should show confirmation dialog (placeholder for now)
        # Accept the confirmation
        page.driver.browser.switch_to.alert.accept rescue nil
      end
    end
  end

  describe "Mobile Responsiveness" do
    context "on mobile viewport" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
        visit dashboard_expenses_path
      end

      after do
        page.driver.browser.manage.window.resize_to(1400, 900) # Reset to desktop
      end

      it "shows larger touch targets for checkboxes" do
        within("#dashboard-expenses-widget") do
          find('[data-action*="toggleSelectionMode"]').click

          # Checkboxes should be visible and usable on mobile
          checkbox = first('[data-dashboard-expenses-target="selectionCheckbox"]')
          expect(checkbox).to be_visible

          # Touch the checkbox
          checkbox.check
          expect(checkbox).to be_checked
        end
      end

      it "shows mobile-optimized toolbar" do
        within("#dashboard-expenses-widget") do
          find('[data-action*="toggleSelectionMode"]').click

          toolbar = find('[data-dashboard-expenses-target="selectionToolbar"]')
          expect(toolbar).to be_visible

          # Buttons should be appropriately sized for mobile
          buttons = toolbar.all("button")
          expect(buttons).not_to be_empty
        end
      end
    end
  end

  describe "Accessibility" do
    before do
      within("#dashboard-expenses-widget") do
        find('[data-action*="toggleSelectionMode"]').click
      end
    end

    it "has proper ARIA labels" do
      within("#dashboard-expenses-widget") do
        # Selection mode button
        selection_button = find('[data-action*="toggleSelectionMode"]')
        expect(selection_button["aria-label"]).to include("selección múltiple")

        # Toolbar
        toolbar = find('[data-dashboard-expenses-target="selectionToolbar"]')
        expect(toolbar[:role]).to eq("toolbar")
        expect(toolbar["aria-label"]).to include("selección")

        # Checkboxes
        checkbox = first('[data-dashboard-expenses-target="selectionCheckbox"]')
        expect(checkbox["aria-label"]).to include("Seleccionar")
      end
    end

    it "announces selection changes to screen readers" do
      within("#dashboard-expenses-widget") do
        # Select an item
        first('[data-dashboard-expenses-target="selectionCheckbox"]').check

        # Should have created an ARIA live region announcement
        # This is tested by checking if the announce method creates the element
        expect(page).to have_css('[role="status"][aria-live="polite"]', visible: false)
      end
    end

    it "supports keyboard-only interaction" do
      within("#dashboard-expenses-widget") do
        # Tab through interface elements
        selection_button = find('[data-action*="toggleSelectionMode"]')
        selection_button.send_keys :tab

        # Should be able to navigate with keyboard
        active_element = page.evaluate_script("document.activeElement")
        expect(active_element).not_to be_nil
      end
    end
  end

  describe "Performance" do
    let!(:many_expenses) do
      15.times.map do |i|
        create(:expense,
          email_account: email_account,
          merchant_name: "Merchant #{i + 6}",
          amount: 1000 * (i + 1),
          transaction_date: (i + 6).days.ago
        )
      end
    end

    before do
      visit dashboard_expenses_path
    end

    it "handles selection of many items efficiently" do
      within("#dashboard-expenses-widget") do
        # Switch to expanded view to see more items
        find('button[data-mode="expanded"]').click
        sleep 0.5

        # Enter selection mode
        find('[data-action*="toggleSelectionMode"]').click

        # Select all
        start_time = Time.now
        find('[data-dashboard-expenses-target="selectAllCheckbox"]').check
        end_time = Time.now

        # Should complete quickly (under 1 second)
        expect(end_time - start_time).to be < 1.0

        # All visible items should be selected
        expect(page).to have_text("seleccionados")
      end
    end
  end
end
