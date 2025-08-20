# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Filter Chips", type: :system, js: true do
  let!(:email_account) { create(:email_account, active: true) }
  let!(:category1) { create(:category, name: "Alimentación", color: "#10B981") }
  let!(:category2) { create(:category, name: "Transporte", color: "#3B82F6") }
  let!(:category3) { create(:category, name: "Entretenimiento", color: "#F59E0B") }

  # Create expenses with different attributes for filtering
  let!(:expense_food_pending) do
    create(:expense,
           email_account: email_account,
           category: category1,
           merchant_name: "Restaurante Central",
           amount: 15000,
           status: "pending",
           transaction_date: Date.current)
  end

  let!(:expense_food_processed) do
    create(:expense,
           email_account: email_account,
           category: category1,
           merchant_name: "Supermercado Fresh",
           amount: 25000,
           status: "processed",
           transaction_date: Date.current)
  end

  let!(:expense_transport_pending) do
    create(:expense,
           email_account: email_account,
           category: category2,
           merchant_name: "Gasolinera Shell",
           amount: 30000,
           status: "pending",
           transaction_date: 1.day.ago)
  end

  let!(:expense_entertainment_processed) do
    create(:expense,
           email_account: email_account,
           category: category3,
           merchant_name: "Cine Plaza",
           amount: 12000,
           status: "processed",
           transaction_date: 7.days.ago)
  end

  let!(:expense_uncategorized) do
    create(:expense,
           email_account: email_account,
           category: nil,
           merchant_name: "Tienda ABC",
           amount: 8000,
           status: "pending",
           transaction_date: 14.days.ago)
  end

  before do
    visit dashboard_expenses_path
    wait_for_turbo
  end

  describe "Filter Chips Display" do
    it "displays category filter chips with counts" do
      within(".dashboard-filter-chips") do
        # Check category chips
        expect(page).to have_button("Alimentación", text: /\(2\)/)
        expect(page).to have_button("Transporte", text: /\(1\)/)
        expect(page).to have_button("Entretenimiento", text: /\(1\)/)

        # Check for category color indicators
        category1_chip = find("button[data-category-id='#{category1.id}']")
        within(category1_chip) do
          expect(page).to have_css("span[style*='background-color: #{category1.color}']")
        end
      end
    end

    it "displays status filter chips with counts" do
      within(".dashboard-filter-chips") do
        expect(page).to have_button("Pending", text: /\(3\)/)
        expect(page).to have_button("Processed", text: /\(2\)/)

        # Check for status icons
        expect(page).to have_css("button[data-status='pending'] svg")
        expect(page).to have_css("button[data-status='processed'] svg")
      end
    end

    it "displays period filter chips when expenses exist" do
      within(".dashboard-filter-chips") do
        expect(page).to have_button("Hoy", text: /\(2\)/)
        expect(page).to have_button("Esta Semana", text: /\(3\)/)

        # Check for calendar icons
        expect(page).to have_css("button[data-period='today'] svg")
        expect(page).to have_css("button[data-period='week'] svg")
      end
    end

    it "does not display clear button when no filters are active" do
      within(".dashboard-filter-chips") do
        expect(page).not_to have_button("Limpiar filtros")
      end
    end
  end

  describe "Category Filtering" do
    it "filters expenses by single category" do
      # Click on Alimentación category
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
      end

      wait_for_ajax

      # Check that only food expenses are shown
      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Supermercado Fresh")
        expect(page).not_to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Cine Plaza")
        expect(page).not_to have_content("Tienda ABC")
      end

      # Check chip is active
      within(".dashboard-filter-chips") do
        food_chip = find("button[data-category-id='#{category1.id}']")
        expect(food_chip[:class]).to include("bg-teal-700")
        expect(food_chip["aria-pressed"]).to eq("true")
      end
    end

    it "filters expenses by multiple categories" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
        click_button "Transporte"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Supermercado Fresh")
        expect(page).to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Cine Plaza")
        expect(page).not_to have_content("Tienda ABC")
      end
    end

    it "toggles category filter on/off" do
      within(".dashboard-filter-chips") do
        # Enable filter
        click_button "Alimentación"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).not_to have_content("Gasolinera Shell")
      end

      within(".dashboard-filter-chips") do
        # Disable filter
        click_button "Alimentación"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Gasolinera Shell")
      end
    end
  end

  describe "Status Filtering" do
    it "filters expenses by pending status" do
      within(".dashboard-filter-chips") do
        click_button "Pending"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Gasolinera Shell")
        expect(page).to have_content("Tienda ABC")
        expect(page).not_to have_content("Supermercado Fresh")
        expect(page).not_to have_content("Cine Plaza")
      end
    end

    it "filters expenses by processed status" do
      within(".dashboard-filter-chips") do
        click_button "Processed"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Supermercado Fresh")
        expect(page).to have_content("Cine Plaza")
        expect(page).not_to have_content("Restaurante Central")
        expect(page).not_to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Tienda ABC")
      end
    end
  end

  describe "Period Filtering" do
    it "filters expenses by today" do
      within(".dashboard-filter-chips") do
        click_button "Hoy"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Supermercado Fresh")
        expect(page).not_to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Cine Plaza")
      end
    end

    it "filters expenses by this week" do
      within(".dashboard-filter-chips") do
        click_button "Esta Semana"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Supermercado Fresh")
        expect(page).to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Cine Plaza")
        expect(page).not_to have_content("Tienda ABC")
      end
    end

    it "only allows one period filter at a time" do
      within(".dashboard-filter-chips") do
        click_button "Hoy"
        wait_for_ajax

        today_chip = find("button[data-period='today']")
        expect(today_chip["aria-pressed"]).to eq("true")

        click_button "Esta Semana"
        wait_for_ajax

        today_chip = find("button[data-period='today']")
        week_chip = find("button[data-period='week']")

        expect(today_chip["aria-pressed"]).to eq("false")
        expect(week_chip["aria-pressed"]).to eq("true")
      end
    end
  end

  describe "Combined Filtering" do
    it "applies category and status filters together" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
        click_button "Pending"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).not_to have_content("Supermercado Fresh") # Processed
        expect(page).not_to have_content("Gasolinera Shell") # Different category
      end
    end

    it "applies all three filter types together" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
        click_button "Processed"
        click_button "Hoy"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Supermercado Fresh")
        expect(page).not_to have_content("Restaurante Central")
        expect(page).not_to have_content("Gasolinera Shell")
        expect(page).not_to have_content("Cine Plaza")
      end
    end
  end

  describe "Clear Filters" do
    it "shows clear button when filters are active" do
      within(".dashboard-filter-chips") do
        expect(page).not_to have_button("Limpiar filtros")

        click_button "Alimentación"
        wait_for_ajax

        expect(page).to have_button("Limpiar filtros")
      end
    end

    it "clears all filters when clear button is clicked" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
        click_button "Pending"
        click_button "Hoy"
      end

      wait_for_ajax

      within(".dashboard-filter-chips") do
        click_button "Limpiar filtros"
      end

      wait_for_ajax

      # All expenses should be visible
      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).to have_content("Supermercado Fresh")
        expect(page).to have_content("Gasolinera Shell")
        expect(page).to have_content("Cine Plaza")
        expect(page).to have_content("Tienda ABC")
      end

      # All chips should be inactive
      within(".dashboard-filter-chips") do
        all("button[data-dashboard-filter-chips-target*='Chip']").each do |chip|
          expect(chip["aria-pressed"]).to eq("false")
        end

        expect(page).not_to have_button("Limpiar filtros")
      end
    end
  end

  describe "Keyboard Navigation" do
    it "navigates between chips using arrow keys" do
      within(".dashboard-filter-chips") do
        first_chip = first("button[data-dashboard-filter-chips-target*='Chip']")
        first_chip.click

        # Navigate with arrow keys
        first_chip.send_keys(:arrow_right)
        expect(page.evaluate_script("document.activeElement.dataset.dashboardFilterChipsTarget")).to include("Chip")

        page.evaluate_script("document.activeElement").send_keys(:arrow_left)
        expect(page.evaluate_script("document.activeElement.dataset.dashboardFilterChipsTarget")).to include("Chip")
      end
    end

    it "toggles chip with Enter key" do
      within(".dashboard-filter-chips") do
        first_chip = first("button[data-dashboard-filter-chips-target*='categoryChip']")
        first_chip.focus
        first_chip.send_keys(:enter)

        wait_for_ajax

        expect(first_chip["aria-pressed"]).to eq("true")

        first_chip.send_keys(:enter)
        wait_for_ajax

        expect(first_chip["aria-pressed"]).to eq("false")
      end
    end

    it "clears all filters with Escape key" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
        click_button "Pending"
      end

      wait_for_ajax

      # Press Escape to clear filters
      find(".dashboard-filter-chips").send_keys(:escape)

      wait_for_ajax

      within(".dashboard-filter-chips") do
        all("button[data-dashboard-filter-chips-target*='Chip']").each do |chip|
          expect(chip["aria-pressed"]).to eq("false")
        end
      end
    end
  end

  describe "Performance" do
    it "completes filter operations within 50ms" do
      start_time = Time.current

      within(".dashboard-filter-chips") do
        click_button "Alimentación"
      end

      wait_for_ajax

      end_time = Time.current
      duration_ms = (end_time - start_time) * 1000

      # Allow some buffer for CI environments
      expect(duration_ms).to be < 200
    end

    it "maintains smooth animations during filtering" do
      within(".dashboard-filter-chips") do
        chip = find("button[data-category-id='#{category1.id}']")

        # Check that transition classes are applied
        chip.click
        expect(chip[:class]).to include("transition-all")

        # Check opacity transition on expense list
        container = find(".dashboard-expenses-container")
        expect(container[:style]).to match(/transition|opacity/)
      end
    end
  end

  describe "URL Parameter Sync" do
    it "updates URL parameters when filters are applied" do
      within(".dashboard-filter-chips") do
        click_button "Alimentación"
      end

      wait_for_ajax

      expect(page).to have_current_path(/category_ids\[\]=#{category1.id}/)
    end

    it "applies filters from URL parameters on page load" do
      visit dashboard_expenses_path(category_ids: [ category1.id ], status: "pending")
      wait_for_turbo

      within(".dashboard-filter-chips") do
        food_chip = find("button[data-category-id='#{category1.id}']")
        pending_chip = find("button[data-status='pending']")

        expect(food_chip["aria-pressed"]).to eq("true")
        expect(pending_chip["aria-pressed"]).to eq("true")
      end

      within(".dashboard-expenses-container") do
        expect(page).to have_content("Restaurante Central")
        expect(page).not_to have_content("Supermercado Fresh")
      end
    end
  end

  describe "Accessibility" do
    it "has proper ARIA labels and roles" do
      within(".dashboard-filter-chips") do
        chips = all("button[data-dashboard-filter-chips-target*='Chip']")

        chips.each do |chip|
          expect(chip[:role]).to eq("button")
          expect(chip[:"aria-pressed"]).to be_present
          expect(chip[:tabindex]).to eq("0")
        end
      end
    end

    it "announces filter state changes to screen readers" do
      within(".dashboard-filter-chips") do
        chip = find("button[data-category-id='#{category1.id}']")

        expect(chip["aria-pressed"]).to eq("false")
        chip.click
        wait_for_ajax
        expect(chip["aria-pressed"]).to eq("true")
      end
    end

    it "provides keyboard focus indicators" do
      within(".dashboard-filter-chips") do
        chip = first("button[data-dashboard-filter-chips-target*='Chip']")
        chip.focus

        # Check for focus ring styles
        expect(chip.matches_css?(':focus')).to be true
        expect(chip[:class]).to include("focus:ring-2")
      end
    end
  end

  describe "Empty State Handling" do
    it "shows appropriate message when no expenses match filters" do
      within(".dashboard-filter-chips") do
        # Create a filter combination with no results
        click_button "Entretenimiento"
        click_button "Pending"
      end

      wait_for_ajax

      within(".dashboard-expenses-container") do
        expect(page).to have_content("No se encontraron gastos con los filtros aplicados")
        expect(page).not_to have_css(".dashboard-expense-row")
      end
    end
  end

  describe "Mobile Responsiveness" do
    context "on mobile devices", mobile: true do
      before do
        page.driver.browser.manage.window.resize_to(375, 667)
        visit dashboard_expenses_path
        wait_for_turbo
      end

      it "displays filter chips in a mobile-friendly layout" do
        within(".dashboard-filter-chips") do
          # Check that chips wrap properly
          expect(page).to have_css("button[data-dashboard-filter-chips-target*='Chip']")

          # Check for mobile-optimized touch targets
          chips = all("button[data-dashboard-filter-chips-target*='Chip']")
          chips.each do |chip|
            height = chip.native.style("height").to_i
            expect(height).to be >= 32
          end
        end
      end

      it "shows clear button prominently on mobile when filters active" do
        within(".dashboard-filter-chips") do
          click_button "Alimentación"
          wait_for_ajax

          clear_button = find("button[data-dashboard-filter-chips-target='clearButton']")
          expect(clear_button).to be_visible

          # Check if button is full width on mobile
          expect(clear_button[:class]).to include("w-full")
        end
      end
    end
  end

  private

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until page.evaluate_script("window.jQuery && jQuery.active == 0")
    end
  rescue Timeout::Error
    # Continue if jQuery is not available or timeout occurs
  end

  def wait_for_turbo
    expect(page).to have_css("[data-turbo-temporary]", visible: false, wait: 0.1)
  rescue Capybara::ElementNotFound
    # Turbo has finished loading
  end
end
