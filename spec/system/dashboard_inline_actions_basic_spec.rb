require "rails_helper"

RSpec.describe "Dashboard Inline Actions Basic", type: :system, js: true, tier: :system do
  let!(:email_account) { create(:email_account) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }

  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category_food,
      status: "pending",
      merchant_name: "Test Restaurant",
      amount: 5000,
      transaction_date: Date.current
    )
  end

  before do
    visit dashboard_expenses_path
    # Wait for page to load and Stimulus to initialize
    sleep 1
  end

  describe "Core Inline Actions" do
    it "changes category successfully" do
      # Find the expense row
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Click category button
      within expense_row do
        category_button = find('button[data-action*="toggleCategoryDropdown"]')
        category_button.click
      end

      # Select new category
      dropdown = find('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
      within dropdown do
        click_button "Transport"
      end

      sleep 1 # Wait for API call

      # Verify category changed
      expense.reload
      expect(expense.category).to eq(category_transport)
    end

    it "toggles status from pending to processed" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Click status toggle
      within expense_row do
        status_button = find('button[data-action*="toggleStatus"]')
        status_button.click
      end

      sleep 1 # Wait for API call

      # Verify status changed
      expense.reload
      expect(expense.status).to eq("processed")
    end

    it "duplicates expense" do
      initial_count = Expense.count

      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Click duplicate button
      within expense_row do
        duplicate_button = find('button[data-action*="duplicateExpense"]')
        duplicate_button.click
      end

      sleep 2 # Wait for duplication and page reload

      # Verify expense was duplicated
      expect(Expense.count).to eq(initial_count + 1)

      # Find the new expense
      new_expense = Expense.order(created_at: :desc).first
      expect(new_expense.merchant_name).to eq(expense.merchant_name)
      expect(new_expense.status).to eq("pending")
    end

    it "deletes expense with confirmation" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Click delete button
      within expense_row do
        delete_button = find('button[data-action*="showDeleteConfirmation"]')
        delete_button.click
      end

      # Confirm deletion
      confirmation = find('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
      within confirmation do
        click_button "Eliminar"
      end

      sleep 1 # Wait for deletion

      # Verify expense was deleted
      expect(Expense.exists?(expense.id)).to be false
    end

    it "cancels deletion when clicking cancel" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Click delete button
      within expense_row do
        delete_button = find('button[data-action*="showDeleteConfirmation"]')
        delete_button.click
      end

      # Cancel deletion
      confirmation = find('[data-dashboard-inline-actions-target="deleteConfirmation"]:not(.hidden)')
      within confirmation do
        click_button "Cancelar"
      end

      sleep 1

      # Verify expense still exists
      expect(Expense.exists?(expense.id)).to be true
    end
  end

  describe "Toast Notifications" do
    it "shows toast notification on successful action" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.hover
      sleep 0.5

      # Toggle status
      within expense_row do
        status_button = find('button[data-action*="toggleStatus"]')
        status_button.click
      end

      # Look for toast notification
      expect(page).to have_content("Estado cambiado", wait: 3)
    end
  end

  describe "Keyboard Shortcuts" do
    it "opens category dropdown with 'c' key" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.click # Focus the row

      # Press 'c' to open category dropdown
      page.send_keys('c')
      sleep 0.5

      # Dropdown should be visible
      expect(page).to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')

      # Press Escape to close
      page.send_keys(:escape)
      sleep 0.5

      # Dropdown should be hidden
      expect(page).not_to have_css('[data-dashboard-inline-actions-target="categoryDropdown"]:not(.hidden)')
    end

    it "toggles status with 's' key" do
      expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")
      expense_row.click # Focus the row

      # Press 's' to toggle status
      page.send_keys('s')
      sleep 1

      # Status should have changed
      expense.reload
      expect(expense.status).to eq("processed")
    end
  end

  describe "Mobile Support" do
    context "on mobile viewport" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667)
        visit dashboard_expenses_path
        sleep 1
      end

      after do
        page.driver.browser.manage.window.resize_to(1400, 900)
      end

      it "shows actions on mobile without hover" do
        expense_row = find("[data-dashboard-inline-actions-expense-id-value='#{expense.id}']")

        # Actions should be visible without hover on mobile
        within expense_row do
          expect(page).to have_css('button[data-action*="toggleStatus"]', visible: true)
        end
      end
    end
  end
end
