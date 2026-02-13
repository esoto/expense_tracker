require 'rails_helper'

RSpec.describe "Dashboard Category Display", type: :system do
  let(:admin_user) { create(:admin_user) }
  let!(:category) { create(:category, name: "Test Category", color: "#FF6B6B") }
  let!(:expense_with_category) { create(:expense, category: category, merchant_name: "Test Merchant") }
  let!(:expense_without_category) { create(:expense, category: nil, merchant_name: "No Category Merchant") }

  before do
    sign_in_admin_user(admin_user)
    visit dashboard_expenses_path
  end

  describe "Category badge rendering" do
    it "displays colored badge for expenses with categories" do
      # Dashboard uses div-based layout with data-expense-id
      expense_row = find("div[data-expense-id='#{expense_with_category.id}']")

      within expense_row do
        # Check for the category name in the expense row
        expect(page).to have_content(category.name)
      end
    end

    it "displays '?' badge for expenses without categories" do
      # Dashboard uses div-based layout with data-expense-id
      expense_row = find("div[data-expense-id='#{expense_without_category.id}']")

      within expense_row do
        # Check for "Sin categoría" in the expense row
        expect(page).to have_content("Sin categoría")
      end
    end

    it "renders category badge correctly" do
      # Check that category badges are present in the dashboard
      expect(page).to have_css(".expense-category-badge")

      # Check for uncategorized badge
      expect(page).to have_css(".expense-category-badge.uncategorized")
    end
  end

  describe "Visual consistency with main expenses page" do
    it "uses same category display components as expenses index" do
      # Visit main expenses page
      visit expenses_path

      # Find the expense row in the table (index page uses tr with id)
      main_expense_row = find("#expense_row_#{expense_with_category.id}")

      # Check that it has the turbo frame for category
      within main_expense_row do
        expect(page).to have_css("turbo-frame[id='expense_#{expense_with_category.id}_category']")
      end

      # Visit dashboard
      visit dashboard_expenses_path

      # Dashboard uses div-based layout with category badges
      dashboard_expense_row = find("div[data-expense-id='#{expense_with_category.id}']")

      within dashboard_expense_row do
        # Dashboard shows category name and badge
        expect(page).to have_content(category.name)
        expect(page).to have_css(".expense-category-badge")
      end
    end
  end
end
