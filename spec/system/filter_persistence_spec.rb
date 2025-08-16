require 'rails_helper'

RSpec.describe "Filter Persistence", type: :system, js: true do
  let!(:category) { create(:category, name: "Food") }
  let!(:expenses) { create_list(:expense, 10, category: category) }

  describe "filter state persistence" do
    it "saves filter state to session storage" do
      visit expenses_path

      # Apply filters
      select "Food", from: "category"
      fill_in "start_date", with: "2024-01-01"
      fill_in "end_date", with: "2024-01-31"
      click_button "Filtrar"

      # Check that filters are saved
      stored_filters = page.evaluate_script("sessionStorage.getItem('expense_filters')")
      expect(stored_filters).not_to be_nil

      parsed = page.evaluate_script("JSON.parse(sessionStorage.getItem('expense_filters'))")
      expect(parsed['filters']['category']).to eq("Food")
    end

    it "restores filters on page reload" do
      visit expenses_path(category: "Food", start_date: "2024-01-01", end_date: "2024-01-31")

      # Refresh the page
      page.refresh

      # Filters should be maintained
      expect(page).to have_select("category", selected: "Food")
      expect(page).to have_field("start_date", with: "2024-01-01")
      expect(page).to have_field("end_date", with: "2024-01-31")
    end

    it "clears stored filters when requested" do
      visit expenses_path(category: "Food")

      # Clear filters
      click_link "Limpiar"

      stored_filters = page.evaluate_script("sessionStorage.getItem('expense_filters')")
      expect(stored_filters).to be_nil
    end

    it "shows notification when filters are saved" do
      visit expenses_path

      select "Food", from: "category"
      click_button "Filtrar"

      expect(page).to have_content("Filtros guardados", wait: 2)
    end

    it "expires old filter data" do
      # Set expired filter data
      expired_data = {
        filters: { category: "Food" },
        timestamp: 2.days.ago.to_i * 1000,
        url: "/expenses"
      }

      visit expenses_path
      page.execute_script("sessionStorage.setItem('expense_filters', '#{expired_data.to_json}')")

      # Refresh page
      page.refresh

      # Expired filters should not be restored
      expect(page).to have_select("category", selected: "Todas las categorías")
    end
  end

  describe "cross-tab synchronization" do
    it "syncs filters across browser tabs when using localStorage" do
      visit expenses_path

      # Switch to localStorage
      page.execute_script("document.querySelector('[data-controller=\"filter-persistence\"]').setAttribute('data-filter-persistence-storage-type-value', 'local')")

      # Apply filter in current tab
      select "Food", from: "category"
      click_button "Filtrar"

      # Open new tab
      new_window = open_new_window
      within_window new_window do
        visit expenses_path

        # Filter should be applied in new tab
        expect(page).to have_select("category", selected: "Food")
      end
    end
  end
end
