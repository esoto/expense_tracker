require 'rails_helper'

RSpec.describe "Expense Filter Chips", type: :system, js: true do
  let(:admin_user) { create(:admin_user) }
  let!(:category1) { create(:category, name: "Food", color: "emerald") }
  let!(:category2) { create(:category, name: "Transport", color: "amber") }
  let!(:expense1) { create(:expense, category: category1, bank_name: "BAC", amount: 1000) }
  let!(:expense2) { create(:expense, category: category2, bank_name: "BCR", amount: 2000) }

  before { sign_in_admin_user(admin_user) }

  describe "Filter chips display" do
    it "shows active filters as chips" do
      visit expenses_path(category: "Food", bank: "BAC")

      within('[data-controller="filter-chips"]') do
        expect(page).to have_content("Filtros activos:")
        expect(page).to have_content("Categoría: Food")
        expect(page).to have_content("Banco: BAC")
      end
    end

    it "allows removing individual filters by clicking chips" do
      visit expenses_path(category: "Food", bank: "BAC")

      within('[data-controller="filter-chips"]') do
        # Remove category filter
        find('button[data-filter-key="category"]').click
      end

      expect(current_url).to include("bank=BAC")
      expect(current_url).not_to include("category=")
    end

    it "provides clear all filters option when multiple filters active" do
      visit expenses_path(category: "Food", bank: "BAC", status: "processed")

      within('[data-controller="filter-chips"]') do
        expect(page).to have_content("Limpiar todos")
        click_on "Limpiar todos"
      end

      expect(current_url).not_to include("category=")
      expect(current_url).not_to include("bank=")
      expect(current_url).not_to include("status=")
    end

    it "hides chips container when no filters are active" do
      visit expenses_path

      expect(page).to have_css('[data-controller="filter-chips"].hidden', visible: false)
    end

    it "displays date range filters correctly" do
      visit expenses_path(start_date: "2024-01-01", end_date: "2024-01-31")

      within('[data-controller="filter-chips"]') do
        expect(page).to have_content("01/01/2024 - 31/01/2024")
      end
    end

    it "displays amount range filters" do
      visit expenses_path(min_amount: "1000", max_amount: "5000")

      within('[data-controller="filter-chips"]') do
        expect(page).to have_content("Monto: ₡1,000 - ₡5,000")
      end
    end
  end
end
