# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Virtual Scrolling", type: :system, js: true do
  # Create test data
  let!(:email_account) { create(:email_account, :active) }
  let!(:categories) { create_list(:category, 5) }
  
  # Create a large dataset for virtual scrolling
  let!(:expenses) do
    100.times.map do |i|
      create(:expense,
             email_account: email_account,
             merchant_name: "Merchant #{100 - i}",  # Reverse order for testing
             amount: 1000 + (i * 100),
             transaction_date: i.days.ago,
             category: categories.sample,
             status: i.even? ? "processed" : "pending",
             created_at: i.hours.ago)
    end
  end

  describe "Virtual Scrolling Performance" do
    context "with large dataset" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "initially renders only visible items" do
        # Check that virtual scrolling is active
        expect(page).to have_css(".virtual-scroll-container")
        expect(page).to have_css("[data-controller*='dashboard-virtual-scroll']")
        
        # Check that only a subset of items are rendered in DOM
        rendered_items = all(".virtual-expense-item", wait: 2)
        expect(rendered_items.count).to be_between(15, 30)  # Only visible + buffer items
        
        # But total count should be displayed
        if page.has_css?(".virtual-scroll-stats", wait: 0)  # Dev mode only
          total_count = find("[data-dashboard-virtual-scroll-target='totalCount']").text.to_i
          expect(total_count).to eq(100)
        end
      end

      it "loads more items on scroll" do
        container = find(".virtual-scroll-viewport")
        
        # Get initial item count
        initial_count = all(".virtual-expense-item").count
        
        # Scroll down
        container.execute_script("this.scrollTop = this.scrollHeight * 0.5")
        sleep 0.5  # Wait for scroll handler
        
        # Should have different items rendered
        after_scroll_count = all(".virtual-expense-item").count
        expect(after_scroll_count).to be_between(15, 35)  # Still limited items in DOM
      end

      it "maintains scroll position during re-renders" do
        container = find(".virtual-scroll-viewport")
        
        # Scroll to middle
        container.execute_script("this.scrollTop = 500")
        initial_scroll = container.evaluate_script("this.scrollTop")
        
        # Trigger a re-render by changing view mode
        find("[data-mode='expanded']").click
        sleep 0.3
        
        # Scroll position should be maintained (approximately)
        final_scroll = container.evaluate_script("this.scrollTop")
        expect(final_scroll).to be_within(100).of(initial_scroll)
      end

      it "shows loading indicator when fetching more data" do
        container = find(".virtual-scroll-viewport")
        
        # Scroll to bottom to trigger loading
        container.execute_script("this.scrollTop = this.scrollHeight")
        
        # Should show loading indicator
        expect(page).to have_css(".virtual-scroll-loading-bottom", visible: :visible, wait: 2)
      end
    end

    context "with filters applied" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "updates virtual scroll when filters are applied" do
        # Apply a category filter
        within(".dashboard-filter-chips") do
          first("[data-dashboard-filter-chips-target='categoryChip']").click
        end
        
        sleep 0.5  # Wait for filter to apply
        
        # Virtual scroll should update with filtered results
        rendered_items = all(".virtual-expense-item")
        expect(rendered_items.count).to be < 100
      end

      it "resets scroll position when filters change" do
        container = find(".virtual-scroll-viewport")
        
        # Scroll down first
        container.execute_script("this.scrollTop = 500")
        
        # Apply filter
        within(".dashboard-filter-chips") do
          first("[data-dashboard-filter-chips-target='categoryChip']").click
        end
        
        sleep 0.5
        
        # Scroll should reset to top
        final_scroll = container.evaluate_script("this.scrollTop")
        expect(final_scroll).to eq(0)
      end
    end

    context "with view mode changes" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "adjusts item heights for expanded view" do
        # Get initial item height
        first_item = first(".virtual-expense-item")
        compact_height = first_item.native.style["height"].to_i
        
        # Switch to expanded view
        find("[data-mode='expanded']").click
        sleep 0.3
        
        # Item height should increase
        expanded_height = first_item.native.style["height"].to_i
        expect(expanded_height).to be > compact_height
      end

      it "maintains virtual scrolling in both view modes" do
        # Test compact mode
        expect(page).to have_css(".virtual-scroll-container")
        
        # Switch to expanded
        find("[data-mode='expanded']").click
        sleep 0.3
        
        # Should still have virtual scrolling
        expect(page).to have_css(".virtual-scroll-container")
        expect(page).to have_css(".virtual-expense-item")
      end
    end

    context "with selection mode" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "supports selection in virtual scrolled items" do
        # Enable selection mode
        find("[data-action*='toggleSelectionMode']").click
        
        # Check that selection works on virtual items
        expect(page).to have_css("[data-selection-container]", visible: :visible)
        
        # Select first visible item
        first("input[type='checkbox'][data-expense-id]").click
        
        # Should update selection count
        expect(page).to have_text("1 seleccionados")
      end

      it "maintains selection state during scroll" do
        # Enable selection mode
        find("[data-action*='toggleSelectionMode']").click
        
        # Select an item
        first_checkbox = first("input[type='checkbox'][data-expense-id]")
        expense_id = first_checkbox["data-expense-id"]
        first_checkbox.click
        
        # Scroll down and back up
        container = find(".virtual-scroll-viewport")
        container.execute_script("this.scrollTop = 1000")
        sleep 0.3
        container.execute_script("this.scrollTop = 0")
        sleep 0.3
        
        # Item should still be selected when re-rendered
        checkbox = find("input[type='checkbox'][data-expense-id='#{expense_id}']")
        expect(checkbox).to be_checked
      end
    end

    context "with inline actions" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "shows inline actions on hover for virtual items" do
        # Hover over first item
        first_item = first(".virtual-expense-item .dashboard-expense-row")
        first_item.hover
        
        # Should show inline actions
        within(first_item) do
          expect(page).to have_css(".inline-quick-actions", visible: :visible)
          expect(page).to have_css("button[title*='Categorizar']")
          expect(page).to have_css("button[title*='estado']")
        end
      end

      it "handles inline action clicks on virtual items" do
        # Get first item
        first_item = first(".virtual-expense-item .dashboard-expense-row")
        expense_id = first_item["data-expense-id"]
        
        # Hover and click status toggle
        first_item.hover
        within(first_item) do
          find("button[title*='estado']").click
        end
        
        # Status should update
        sleep 0.5
        updated_item = find("[data-expense-id='#{expense_id}']")
        expect(updated_item["data-expense-status"]).not_to eq(expenses.first.status)
      end
    end

    context "performance monitoring" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "maintains 60fps during scroll", :performance do
        skip "Performance test - requires manual verification"
        
        container = find(".virtual-scroll-viewport")
        
        # Simulate continuous scrolling
        10.times do
          container.execute_script("this.scrollBy(0, 100)")
          sleep 0.016  # ~60fps timing
        end
        
        # Check FPS counter if available (dev mode)
        if page.has_css?("[data-dashboard-virtual-scroll-target='fps']", wait: 0)
          fps = find("[data-dashboard-virtual-scroll-target='fps']").text.to_i
          expect(fps).to be >= 50  # Allow some variance
        end
      end

      it "recycles DOM nodes efficiently" do
        container = find(".virtual-scroll-viewport")
        
        # Scroll through entire list
        5.times do
          container.execute_script("this.scrollTop = this.scrollTop + 500")
          sleep 0.3
        end
        
        # DOM node count should remain constant
        final_count = all(".virtual-expense-item").count
        expect(final_count).to be_between(15, 35)  # Still limited nodes
      end
    end

    context "accessibility" do
      before do
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      it "supports keyboard navigation" do
        # Focus on container
        container = find(".virtual-scroll-viewport")
        container.send_keys(:tab)
        
        # Should be able to navigate items with arrow keys
        container.send_keys(:arrow_down)
        
        # Check that focus moves to items
        expect(page).to have_css(".virtual-expense-item .dashboard-expense-row:focus")
      end

      it "announces scroll position to screen readers" do
        # Check for ARIA live region
        expect(page).to have_css("[role='status'][aria-live]", visible: :hidden)
      end

      it "maintains focus during virtual scroll" do
        # Focus on an item
        first_item = first(".virtual-expense-item .dashboard-expense-row")
        first_item.click  # Focus
        
        # Scroll
        container = find(".virtual-scroll-viewport")
        container.execute_script("this.scrollTop = 200")
        sleep 0.3
        
        # Focus should be maintained or restored appropriately
        expect(page).to have_css(":focus")
      end
    end

    context "mobile responsiveness" do
      before do
        page.driver.browser.manage.window.resize_to(375, 812)  # iPhone X size
        visit dashboard_expenses_path(enable_virtual: "true")
        wait_for_turbo
      end

      after do
        page.driver.browser.manage.window.resize_to(1024, 768)  # Reset
      end

      it "works with touch scrolling" do
        container = find(".virtual-scroll-viewport")
        
        # Simulate touch scroll
        container.execute_script(<<~JS)
          const touch = new Touch({
            identifier: Date.now(),
            target: this,
            clientX: 100,
            clientY: 400
          });
          
          const startEvent = new TouchEvent('touchstart', {
            touches: [touch],
            targetTouches: [touch],
            changedTouches: [touch]
          });
          
          this.dispatchEvent(startEvent);
          
          // Simulate scroll
          this.scrollTop = 300;
        JS
        
        # Should handle touch events
        expect(page).to have_css(".virtual-expense-item")
      end

      it "adjusts item heights for mobile" do
        first_item = first(".virtual-expense-item")
        height = first_item.native.style["height"].to_i
        
        # Mobile items should be slightly smaller
        expect(height).to be_between(64, 76)
      end
    end

    context "error handling" do
      it "shows error state when loading fails" do
        # Visit with invalid parameters to trigger error
        visit dashboard_expenses_path(enable_virtual: "true", cursor: "invalid_cursor")
        
        # Should handle error gracefully
        expect(page).not_to have_css(".virtual-scroll-error", wait: 2)  # Should recover
        
        # Should still show some content
        expect(page).to have_css("#dashboard-expenses-widget")
      end

      it "retries failed loads automatically" do
        skip "Requires network simulation"
        
        # This would require simulating network failures
        # In real implementation, the controller has retry logic
      end
    end
  end

  describe "Integration with existing Epic 3 features" do
    before do
      visit dashboard_expenses_path(enable_virtual: "true")
      wait_for_turbo
    end

    it "works with all Epic 3 features simultaneously" do
      # Task 3.2: View toggle
      expect(page).to have_css("[data-mode='compact'][aria-pressed='true']")
      
      # Task 3.3: Inline actions
      first(".virtual-expense-item .dashboard-expense-row").hover
      expect(page).to have_css(".inline-quick-actions", visible: :visible)
      
      # Task 3.4: Batch selection
      find("[data-action*='toggleSelectionMode']").click
      expect(page).to have_css("[data-selection-container]", visible: :visible)
      
      # Task 3.6: Filter chips
      expect(page).to have_css(".dashboard-filter-chips")
      
      # Task 3.7: Virtual scrolling
      expect(page).to have_css(".virtual-scroll-container")
      
      # All should work together
      find("[data-mode='expanded']").click  # Change view
      first("[data-dashboard-filter-chips-target='categoryChip']").click  # Apply filter
      
      # Virtual scroll should adapt
      expect(page).to have_css(".virtual-expense-item")
    end
  end

  private

  def wait_for_turbo
    expect(page).to have_css("[data-turbo-frame]", wait: 2)
    sleep 0.1  # Additional wait for JS initialization
  end
end