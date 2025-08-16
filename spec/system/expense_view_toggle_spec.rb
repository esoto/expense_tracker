require 'rails_helper'

RSpec.describe "Expense View Toggle", type: :system, js: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category, name: "Food", color: "#10B981") }

  before do
    # Create test expenses with varying levels of detail
    @expense_with_full_details = create(:expense,
      email_account: email_account,
      category: category,
      transaction_date: Date.current,
      amount: 5000,
      merchant_name: "Restaurant ABC",
      description: "Lunch meeting with client",
      bank_name: "BAC",
      status: "processed",
      ml_confidence: 0.95,
      ml_confidence_explanation: "High confidence based on merchant pattern"
    )

    @expense_minimal = create(:expense,
      email_account: email_account,
      category: nil,
      transaction_date: Date.current - 1.day,
      amount: 2500,
      merchant_name: "Store XYZ",
      description: nil,
      bank_name: "Manual Entry",
      status: "pending"
    )

    @expense_with_low_confidence = create(:expense,
      email_account: email_account,
      category: category,
      transaction_date: Date.current - 2.days,
      amount: 7500,
      merchant_name: "Unknown Shop",
      description: "Purchase",
      bank_name: "BAC",
      status: "processed",
      ml_confidence: 0.35,
      ml_confidence_explanation: "Low confidence - needs review"
    )
  end

  describe "View Toggle Button" do
    it "displays the toggle button with correct initial state" do
      visit expenses_path

      toggle_button = find('[data-view-toggle-target="toggleButton"]')
      expect(toggle_button).to have_content("Vista Compacta")
      expect(page).to have_css('[data-view-toggle-target="compactIcon"]:not(.hidden)')
      expect(page).to have_css('[data-view-toggle-target="expandedIcon"].hidden', visible: false)
    end

    it "toggles between compact and expanded views when clicked" do
      visit expenses_path

      # Initially in expanded view
      expect(page).to have_selector('[data-view-toggle-target="expandedColumns"]')

      # Click to switch to compact view
      find('[data-view-toggle-target="toggleButton"]').click

      # Verify compact view
      expect(page).not_to have_selector('[data-view-toggle-target="expandedColumns"]:not(.hidden)')
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Expandida")

      # Click to switch back to expanded view
      find('[data-view-toggle-target="toggleButton"]').click

      # Verify expanded view
      expect(page).to have_selector('[data-view-toggle-target="expandedColumns"]')
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Compacta")
    end
  end

  describe "Compact View Mode" do
    before do
      visit expenses_path
      find('[data-view-toggle-target="toggleButton"]').click # Switch to compact mode
    end

    it "hides expanded columns (Bank, Status, Actions)" do
      within 'thead' do
        expect(page.text.upcase).to include("FECHA")
        expect(page.text.upcase).to include("COMERCIO")
        expect(page.text.upcase).to include("CATEGORÍA")
        expect(page.text.upcase).to include("MONTO")

        # These should be hidden
        expect(page).not_to have_selector('th:not(.hidden)', text: /banco/i)
        expect(page).not_to have_selector('th:not(.hidden)', text: /estado/i)
        expect(page).not_to have_selector('th:not(.hidden)', text: /acciones/i)
      end
    end

    it "hides expense descriptions" do
      # Description should be hidden in compact mode
      expect(page).not_to have_selector('.expense-description:not(.hidden)', text: "Lunch meeting with client")
    end

    it "displays essential information only" do
      within 'tbody' do
        # Should show essential fields
        expect(page).to have_content("Restaurant ABC")
        expect(page).to have_content("₡5,000")
        expect(page).to have_content("Food")
        expect(page).to have_content(Date.current.strftime("%d/%m/%Y"))

        # Should not show expanded information
        expect(page).not_to have_selector('td:not(.hidden)', text: "BAC")
        expect(page).not_to have_selector('td:not(.hidden)', text: "Procesado")
        expect(page).not_to have_selector('a:not(.hidden)', text: "Ver")
      end
    end

    it "reduces row height for more density" do
      row = find('tbody tr', match: :first)
      expect(row[:class]).to include("h-12") if row[:class]
    end
  end

  describe "Expanded View Mode" do
    before do
      visit expenses_path
      # Ensure we're in expanded mode (default)
    end

    it "shows all columns" do
      within 'thead' do
        expect(page.text.upcase).to include("FECHA")
        expect(page.text.upcase).to include("COMERCIO")
        expect(page.text.upcase).to include("CATEGORÍA")
        expect(page.text.upcase).to include("MONTO")
        expect(page.text.upcase).to include("BANCO")
        expect(page.text.upcase).to include("ESTADO")
        expect(page.text.upcase).to include("ACCIONES")
      end
    end

    it "displays expense descriptions" do
      expect(page).to have_content("Lunch meeting with client")
    end

    it "shows confidence badges for categorization" do
      # Should show confidence percentage for high confidence expense
      expect(page).to have_content("95%")

      # Should show low confidence indicator
      expect(page).to have_content("35%")
    end

    it "displays action buttons" do
      within 'tbody' do
        expect(page).to have_link("Ver")
        expect(page).to have_link("Editar")
        expect(page).to have_button("Eliminar")
      end
    end
  end

  describe "Session Persistence" do
    it "remembers the view mode preference across page reloads" do
      visit expenses_path

      # Switch to compact mode
      find('[data-view-toggle-target="toggleButton"]').click
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Expandida")

      # Reload the page
      visit expenses_path

      # Should still be in compact mode
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Expandida")
      expect(page).not_to have_selector('[data-view-toggle-target="expandedColumns"]:not(.hidden)')
    end

    it "maintains view mode when navigating between pages" do
      visit expenses_path

      # Switch to compact mode
      find('[data-view-toggle-target="toggleButton"]').click

      # Navigate to a specific expense
      first_expense = @expense_with_full_details
      visit expense_path(first_expense)

      # Navigate back to index
      visit expenses_path

      # Should still be in compact mode
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Expandida")
    end
  end

  describe "Keyboard Shortcuts" do
    it "toggles view with Ctrl+Shift+V" do
      visit expenses_path

      # Initial state - expanded view
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Compacta")

      # Press keyboard shortcut
      page.driver.browser.action.key_down(:control).key_down(:shift).send_keys('v').key_up(:shift).key_up(:control).perform

      # Should switch to compact view
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Expandida")

      # Press again to toggle back
      page.driver.browser.action.key_down(:control).key_down(:shift).send_keys('v').key_up(:shift).key_up(:control).perform

      # Should switch back to expanded view
      expect(find('[data-view-toggle-target="buttonText"]')).to have_content("Vista Compacta")
    end
  end

  describe "Responsive Behavior" do
    context "on mobile devices" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
        visit expenses_path
      end

      after do
        page.driver.browser.manage.window.resize_to(1400, 900) # Reset to desktop size
      end

      it "automatically uses compact mode on small screens" do
        # Should be in compact mode by default on mobile
        expect(page).not_to have_selector('[data-view-toggle-target="expandedColumns"]:not(.hidden)')
      end

      it "hides less important columns on mobile" do
        within 'thead' do
          expect(page.text.upcase).to include("FECHA")
          expect(page.text.upcase).to include("COMERCIO")
          expect(page.text.upcase).to include("CATEGORÍA")
          expect(page.text.upcase).to include("MONTO")

          # These should be hidden on mobile
          expect(page).not_to have_selector('th:not(.hidden)', text: /banco/i)
          expect(page).not_to have_selector('th:not(.hidden)', text: /estado/i)
          expect(page).not_to have_selector('th:not(.hidden)', text: /acciones/i)
        end
      end
    end
  end

  describe "Accessibility" do
    it "has proper ARIA labels" do
      visit expenses_path

      toggle_button = find('[data-view-toggle-target="toggleButton"]')
      expect(toggle_button['aria-label']).to eq("Cambiar modo de vista")
      expect(toggle_button['title']).to include("Ctrl+Shift+V")
    end

    it "maintains keyboard navigation in both modes" do
      visit expenses_path

      # Tab through elements in expanded mode
      toggle_button = find('[data-view-toggle-target="toggleButton"]')
      toggle_button.send_keys(:tab)

      # Switch to compact mode
      find('[data-view-toggle-target="toggleButton"]').click

      # Should still be able to tab through visible elements
      toggle_button.send_keys(:tab)
      expect(page).to have_css(':focus')
    end
  end

  describe "Performance" do
    before do
      # Create many expenses to test performance
      20.times do |i|
        create(:expense,
          email_account: email_account,
          category: category,
          transaction_date: Date.current - i.days,
          amount: 1000 * (i + 1),
          merchant_name: "Store #{i}",
          status: [ "processed", "pending", "duplicate" ].sample
        )
      end
    end

    it "toggles quickly between views with many expenses" do
      visit expenses_path

      start_time = Time.current

      # Toggle multiple times
      3.times do
        find('[data-view-toggle-target="toggleButton"]').click
        sleep 0.1 # Small delay to ensure rendering
      end

      elapsed_time = Time.current - start_time

      # Should complete all toggles within 2 seconds even with many expenses
      expect(elapsed_time).to be < 2.seconds
    end
  end
end
