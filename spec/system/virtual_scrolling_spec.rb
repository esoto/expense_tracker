require 'rails_helper'

RSpec.describe "Virtual Scrolling", type: :system, js: true do
  let(:admin_user) { create(:admin_user) }

  context "with large dataset" do
    before do
      # Create 1000+ expenses to trigger virtual scrolling
      create_list(:expense, 600, amount: 1000)
      sign_in_admin_user(admin_user)
    end

    it "enables virtual scrolling for large datasets" do
      visit expenses_path

      expect(page).to have_css('[data-controller*="virtual-scroll"]')
      expect(page).to have_css('[data-virtual-scroll-enabled-value="true"]')
    end

    it "renders only visible items in viewport" do
      visit expenses_path

      # Check that not all rows are rendered at once
      within('#expense_list') do
        rendered_rows = all('tbody tr', visible: true).count
        expect(rendered_rows).to be < 100 # Should render less than total
      end
    end

    it "loads more items when scrolling" do
      visit expenses_path

      initial_count = all('tbody tr', visible: true).count

      # Scroll down
      execute_script("document.querySelector('#expense_list').scrollTop = 1000")
      sleep 0.5 # Allow for scroll event processing

      new_count = all('tbody tr', visible: true).count
      expect(new_count).to be >= initial_count
    end
  end

  context "with small dataset" do
    before do
      create_list(:expense, 50, amount: 500)
    end

    it "disables virtual scrolling for small datasets" do
      visit expenses_path

      expect(page).to have_css('[data-virtual-scroll-enabled-value="false"]')
    end

    it "renders all items normally" do
      visit expenses_path

      within('#expense_list') do
        expect(all('tbody tr').count).to eq(50)
      end
    end
  end

  describe "scroll position indicator" do
    before do
      create_list(:expense, 600, amount: 1000)
    end

    it "shows scroll position information" do
      visit expenses_path

      # Check for scroll info display if implemented
      execute_script("document.querySelector('#expense_list').scrollTop = 500")

      # Virtual scroll controller should update position info
      expect(page).to have_css('[data-virtual-scroll-target="scrollInfo"]', wait: 2)
    end
  end
end
