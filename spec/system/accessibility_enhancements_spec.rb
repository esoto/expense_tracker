require 'rails_helper'

RSpec.describe "Accessibility Enhancements", type: :system, js: true do
  let(:admin_user) { create(:admin_user) }
  let!(:expense) { create(:expense, merchant_name: "Test Store", amount: 1000) }

  before { sign_in_admin_user(admin_user) }

  describe "ARIA attributes and screen reader support" do
    it "adds proper ARIA labels to expense rows" do
      visit expenses_path

      row = find("tr[data-expense-id='#{expense.id}']")
      expect(row).to have_css('[role="article"]')
      expect(row['aria-label']).to include("Test Store")
    end

    it "includes ARIA live regions for dynamic updates" do
      visit expenses_path

      expect(page).to have_css('[role="status"][aria-live="polite"]', visible: false)
      expect(page).to have_css('[role="alert"][aria-live="assertive"]', visible: false)
    end

    it "provides skip links for keyboard navigation" do
      visit expenses_path

      # Skip links are typically hidden but focusable
      skip_link = find('a[href="#expense-actions"]', visible: false)
      expect(skip_link.text).to include("Saltar a acciones")
    end

    it "adds descriptive labels to action buttons" do
      visit expenses_path

      within("tr[data-expense-id='#{expense.id}']") do
        buttons = all('button')
        buttons.each do |button|
          expect(button['aria-label']).not_to be_nil
        end
      end
    end
  end

  describe "keyboard navigation" do
    it "allows navigation with arrow keys" do
      visit expenses_path

      # Focus on first action
      page.send_keys(:alt, 'a')

      # Navigate with arrow keys
      page.send_keys(:arrow_down)
      page.send_keys(:arrow_up)

      # Should maintain focus within actions
      expect(page).to have_css(':focus')
    end

    it "supports escape key to close menus" do
      visit expenses_path

      # Open a menu
      first('[data-action*="click->"]').click

      # Press escape
      page.send_keys(:escape)

      # Menu should be closed
      expect(page).not_to have_css('[data-action-menu]:visible')
    end

    it "provides keyboard shortcuts for common actions" do
      visit expenses_path

      # Focus on expense row
      find("tr[data-expense-id='#{expense.id}']").click

      # Try edit shortcut (Ctrl+E)
      page.send_keys([ :control, 'e' ])

      # Should trigger edit action
      expect(current_path).to eq(edit_expense_path(expense))
    end
  end

  describe "high contrast mode support" do
    it "applies high contrast styles when detected" do
      visit expenses_path

      # Simulate high contrast mode
      page.execute_script("document.body.classList.add('high-contrast-mode')")

      # Check for enhanced focus indicators
      expect(page).to have_css('.high-contrast-mode')

      # Focus indicators should be more prominent
      first('button').click
      expect(page).to have_css(':focus')
    end
  end

  describe "reduced motion support" do
    it "respects prefers-reduced-motion setting" do
      visit expenses_path

      # Simulate reduced motion preference
      page.execute_script("document.body.classList.add('reduce-motion')")

      # Animations should be disabled
      expect(page).to have_css('.reduce-motion')

      # Check that transitions are instant
      transition_duration = page.evaluate_script("getComputedStyle(document.querySelector('button')).transitionDuration")
      expect(transition_duration).to eq("0.01ms")
    end
  end

  describe "focus management" do
    it "traps focus within modals" do
      visit expenses_path

      # Open a modal
      click_button "Selección Múltiple"

      # Tab through focusable elements
      page.send_keys(:tab)
      page.send_keys(:tab)

      # Focus should remain within modal
      expect(page.evaluate_script("document.activeElement.closest('[data-controller]')")).not_to be_nil
    end

    it "restores focus after closing dialogs" do
      visit expenses_path

      # Remember original focus
      trigger_button = first('button')
      trigger_button.click

      # Open and close a dialog
      page.send_keys(:escape)

      # Focus should return to trigger
      expect(page.evaluate_script("document.activeElement")).to eq(trigger_button.native)
    end
  end

  describe "screen reader announcements" do
    it "announces filter changes" do
      visit expenses_path

      select "Food", from: "category"
      click_button "Filtrar"

      # Check for announcement in live region
      announcement = find('[role="status"]', visible: false)
      expect(announcement.text).to include("filtro")
    end

    it "announces bulk operation results" do
      visit expenses_path

      # Perform bulk operation
      click_button "Selección Múltiple"
      check first('input[type="checkbox"]')
      click_button "Operaciones en Lote"

      # Should announce result
      announcement = find('[role="status"]', visible: false)
      expect(announcement).not_to be_nil
    end
  end
end
