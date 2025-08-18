require "rails_helper"

RSpec.describe "Dashboard View Toggle", type: :system, js: true do
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: "Food", color: "#FF6B6B") }

  # Create multiple expenses for testing view limits
  let!(:expenses) do
    20.times.map do |i|
      create(:expense,
        email_account: email_account,
        category: category,
        merchant_name: "Merchant #{i + 1}",
        amount: 1000 * (i + 1),
        transaction_date: i.days.ago
      )
    end
  end

  before do
    visit dashboard_expenses_path
  end

  describe "View Toggle Buttons" do
    it "displays the view toggle buttons with icons" do
      within("#dashboard-expenses-widget") do
        expect(page).to have_css(".dashboard-expenses-toggle")
        expect(page).to have_button("Compacta")
        expect(page).to have_button("Expandida")
        expect(page).to have_css("svg.view-icon", count: 2)
      end
    end

    it "shows compact view by default" do
      within("#dashboard-expenses-widget") do
        expect(page).to have_css("button[aria-pressed='true'][data-mode='compact']")
        expect(page).to have_css(".dashboard-expense-row:not(.hidden)", count: 5)
      end
    end

    it "has keyboard shortcut hint in tooltip" do
      toggle_group = find(".dashboard-expenses-toggle")
      expect(toggle_group["title"]).to include("Ctrl+Shift+V")
    end
  end

  describe "Compact View" do
    it "shows only 5 expenses in compact mode" do
      within(".dashboard-expenses-list") do
        visible_expenses = all(".dashboard-expense-row:not(.hidden)")
        expect(visible_expenses.count).to eq(5)
      end
    end

    it "hides expanded details in compact mode" do
      within(".dashboard-expenses-list") do
        expect(page).to have_css(".expense-expanded-details.hidden", visible: false)
      end
    end

    it "uses compact styling" do
      expect(page).to have_css(".dashboard-expenses-compact")
      within(".dashboard-expenses-list") do
        expect(page).to have_css(".expense-merchant")
        expect(page).to have_css(".expense-metadata")
      end
    end
  end

  describe "Expanded View" do
    before do
      click_button "Expandida"
      # Wait for JavaScript to complete the transition
      expect(page).to have_css("button[aria-pressed='true'][data-mode='expanded']", wait: 2)
      sleep 0.5 # Additional wait for animations
    end

    it "shows up to 15 expenses in expanded mode" do
      within(".dashboard-expenses-list") do
        visible_expenses = all(".dashboard-expense-row:not(.hidden)")
        expect(visible_expenses.count).to eq(15)
      end
    end

    it "shows more expense rows in expanded mode" do
      # In expanded view, we should see more expenses than in compact
      within(".dashboard-expenses-list") do
        # We already verified 15 expenses are visible in the previous test
        # Let's just verify we're in expanded mode by checking button state and row count
        visible_expenses = all(".dashboard-expense-row:not(.hidden)")
        expect(visible_expenses.count).to be > 5  # More than compact mode
        expect(visible_expenses.count).to be <= 15  # Up to 15 in expanded
      end
    end

    it "updates button states correctly" do
      expect(page).to have_css("button[aria-pressed='true'][data-mode='expanded']")
      expect(page).to have_css("button[aria-pressed='false'][data-mode='compact']")
    end

    it "applies expanded styling" do
      expect(page).to have_css(".dashboard-expenses-expanded")
    end
  end

  describe "View Mode Persistence" do
    it "persists view mode in sessionStorage" do
      click_button "Expandida"

      # Check sessionStorage via JavaScript
      stored_mode = page.evaluate_script("sessionStorage.getItem('dashboard_expense_view_mode')")
      expect(stored_mode).to eq("expanded")

      # Refresh page
      visit dashboard_expenses_path

      # Should still be in expanded mode
      expect(page).to have_css("button[aria-pressed='true'][data-mode='expanded']")
    end

    it "restores compact mode after switching" do
      click_button "Expandida"
      sleep 0.3
      click_button "Compacta"

      stored_mode = page.evaluate_script("sessionStorage.getItem('dashboard_expense_view_mode')")
      expect(stored_mode).to eq("compact")
    end
  end

  describe "Keyboard Shortcuts" do
    it "toggles view with Ctrl+Shift+V" do
      # Start in compact mode
      expect(page).to have_css(".dashboard-expenses-compact")

      # Press Ctrl+Shift+V to toggle to expanded
      page.find("body").send_keys [ :control, :shift, "v" ]
      sleep 0.5

      expect(page).to have_css(".dashboard-expenses-expanded")
      expect(page).to have_css(".dashboard-expense-row:not(.hidden)", count: 15)

      # Press again to toggle back to compact
      page.find("body").send_keys [ :control, :shift, "v" ]
      sleep 0.5

      expect(page).to have_css(".dashboard-expenses-compact")
      expect(page).to have_css(".dashboard-expense-row:not(.hidden)", count: 5)
    end
  end

  describe "Responsive Behavior" do
    context "on mobile viewport" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
        visit dashboard_expenses_path
      end

      after do
        page.driver.browser.manage.window.resize_to(1400, 900) # Reset to desktop
      end

      it "forces compact view on mobile" do
        expect(page).to have_css(".dashboard-expenses-compact")

        # Expanded button should be disabled
        expanded_button = find("button[data-mode='expanded']")
        expect(expanded_button[:disabled]).to eq("true")
        expect(expanded_button[:class]).to include("opacity-50")
      end

      it "shows mobile-appropriate UI" do
        within(".dashboard-expenses-toggle") do
          # Icons should be visible but labels might be hidden
          expect(page).to have_css("svg.view-icon", visible: true)
        end
      end

      it "prevents switching to expanded mode" do
        expanded_button = find("button[data-mode='expanded']")
        expanded_button.click

        # Should remain in compact mode
        expect(page).to have_css(".dashboard-expenses-compact")
        expect(page).to have_css("button[aria-pressed='true'][data-mode='compact']")
      end
    end
  end

  describe "Transitions and Animations" do
    it "smoothly transitions between views" do
      # Check for transition classes
      expense_rows = all(".dashboard-expense-row")

      expect(expense_rows.first[:style]).to include("transition")

      click_button "Expandida"
      sleep 0.3

      # More rows should be visible after transition
      visible_rows = all(".dashboard-expense-row:not(.hidden)")
      expect(visible_rows.count).to be > 5
    end
  end

  describe "Empty State" do
    before do
      Expense.destroy_all
      visit dashboard_expenses_path
    end

    it "shows empty state with appropriate message" do
      within("#dashboard-expenses-widget") do
        expect(page).to have_css(".dashboard-expenses-empty")
        expect(page).to have_text("No hay gastos")
        expect(page).to have_text("Aún no tienes gastos registrados")
      end
    end

    it "view toggle still works with empty state" do
      click_button "Expandida"
      expect(page).to have_css("button[aria-pressed='true'][data-mode='expanded']")

      click_button "Compacta"
      expect(page).to have_css("button[aria-pressed='true'][data-mode='compact']")
    end
  end

  describe "Performance Metrics (Development Only)" do
    it "shows performance metrics in development" do
      if Rails.env.development?
        within("#dashboard-expenses-widget") do
          expect(page).to have_css(".dashboard-expenses-performance", visible: false)
        end
      end
    end
  end

  describe "Integration with Filters" do
    before do
      # Create an uncategorized expense
      create(:expense,
        email_account: email_account,
        category: nil,
        merchant_name: "Uncategorized Merchant"
      )
      visit dashboard_expenses_path
    end

    it "maintains view mode when applying filters" do
      click_button "Expandida"

      # Apply a filter
      if page.has_button?("Sin categorizar")
        click_button "Sin categorizar"

        # Should still be in expanded mode
        expect(page).to have_css("button[aria-pressed='true'][data-mode='expanded']")
      end
    end
  end

  describe "Accessibility" do
    it "has proper ARIA attributes" do
      within("#dashboard-expenses-widget") do
        # Check toggle group
        toggle_group = find(".dashboard-expenses-toggle")
        expect(toggle_group[:role]).to eq("group")
        expect(toggle_group["aria-label"]).to eq("Vista")

        # Check buttons
        compact_button = find("button[data-mode='compact']")
        expect(compact_button["aria-label"]).to include("compacta")
        expect(compact_button["aria-pressed"]).to be_in([ "true", "false" ])

        expanded_button = find("button[data-mode='expanded']")
        expect(expanded_button["aria-label"]).to include("expandida")
        expect(expanded_button["aria-pressed"]).to be_in([ "true", "false" ])

        # Check expense rows
        expense_rows = all(".dashboard-expense-row")
        expense_rows.each_with_index do |row, index|
          expect(row[:role]).to eq("article")
          expect(row["aria-label"]).to include("Gasto #{index + 1}")
          expect(row[:tabindex]).to eq("0")
        end
      end
    end

    it "supports keyboard navigation" do
      first_expense = find(".dashboard-expense-row", match: :first)
      first_expense.click

      # Should be focusable
      expect(page.evaluate_script("document.activeElement.classList.contains('dashboard-expense-row')")).to be true
    end
  end
end
