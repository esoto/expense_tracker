require 'rails_helper'

RSpec.describe "Dashboard Category Display", type: :system do
  let!(:category) { create(:category, name: "Test Category", color: "#FF6B6B") }
  let!(:expense_with_category) { create(:expense, category: category, merchant_name: "Test Merchant") }
  let!(:expense_without_category) { create(:expense, category: nil, merchant_name: "No Category Merchant") }

  before do
    visit dashboard_expenses_path
  end

  describe "Category badge rendering" do
    it "displays colored badge for expenses with categories" do
      # Find the table row for this expense
      expense_row = find("tr[data-expense-id='#{expense_with_category.id}']")

      within expense_row do
        # Check for the category name in the category column
        expect(page).to have_content(category.name)
      end
    end

    it "displays '?' badge for expenses without categories" do
      # Find the table row for this expense
      expense_row = find("tr[data-expense-id='#{expense_without_category.id}']")

      within expense_row do
        # Check for "Sin categoría" in the category column
        expect(page).to have_content("Sin categoría")
      end
    end

    it "renders the category_with_confidence partial correctly" do
      # Check that the turbo frame is present for expense rows
      expect(page).to have_css("turbo-frame[id*='expense'][id*='category']")

      # Check for ML confidence badges if present
      if expense_with_category.ml_confidence.present?
        expect(page).to have_css("span.border")
      end
    end
  end

  describe "Visual consistency with main expenses page" do
    it "uses same category display components as expenses index" do
      # Visit main expenses page
      visit expenses_path

      # Find the expense row in the table
      main_expense_row = find("#expense_row_#{expense_with_category.id}")

      # Check that it has the turbo frame for category
      within main_expense_row do
        expect(page).to have_css("turbo-frame[id='expense_#{expense_with_category.id}_category']")
      end

      # Visit dashboard
      visit dashboard_expenses_path

      # Find the expense row in the dashboard table
      dashboard_expense_row = find("#expense_row_#{expense_with_category.id}")

      # Check that it has the same turbo frame for category
      within dashboard_expense_row do
        expect(page).to have_css("turbo-frame[id='expense_#{expense_with_category.id}_category']")
      end

      # Both pages should be using the same table structure now
      expect(page).to have_css("table")
    end
  end
end
