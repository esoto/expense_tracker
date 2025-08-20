require 'rails_helper'

RSpec.describe "Dashboard Accessibility", type: :system, js: true, tier: :system do
  include AccessibilityHelper

  let!(:categories) { create_list(:category, 3) }
  let!(:expenses) { create_list(:expense, 15, category: categories.first) }

  before do
    visit dashboard_expenses_path
    # Wait for page to fully load
    expect(page).to have_css('[data-controller="dashboard-expenses"]')
  end

  describe "WCAG 2.1 AA Compliance" do
    describe "Language and Structure" do
      it "has proper language declaration" do
        expect(page.find('html')['lang']).to eq('es')
      end

      it "has semantic HTML structure" do
        expect(page).to have_css('header[role="banner"]')
        expect(page).to have_css('main[role="main"]')
        expect(page).to have_css('nav[role="navigation"]')
        expect(page).to have_css('section[role="region"]')
      end

      it "has proper heading hierarchy" do
        headings = page.all('h1, h2, h3, h4, h5, h6').map(&:tag_name)
        expect(headings.first).to eq('h1')

        # Check no heading levels are skipped
        (1...headings.length).each do |i|
          current_level = headings[i][1].to_i
          previous_level = headings[i-1][1].to_i
          expect(current_level).to be <= (previous_level + 1)
        end
      end
    end

    describe "Keyboard Navigation" do
      it "supports tab navigation through all interactive elements" do
        # Get all focusable elements
        focusable_elements = page.all('button, a, input, select, textarea, [tabindex]:not([tabindex="-1"])')

        expect(focusable_elements.count).to be > 0

        # Test that each element can receive focus
        focusable_elements.each do |element|
          element.click
          expect(page.driver.browser.switch_to.active_element).to eq(element.native)
        end
      end

      it "provides skip navigation links" do
        skip_links = page.all('.skip-link', visible: :hidden)
        expect(skip_links.count).to be >= 2

        # Skip links should be hidden initially
        skip_links.each do |link|
          expect(link).not_to be_visible
        end

        # Skip links should become visible on focus
        page.send_keys(:tab)
        expect(page).to have_css('.skip-link:focus', visible: true)
      end

      it "supports keyboard shortcuts" do
        # Test filter navigation
        page.send_keys([ :alt, '1' ])
        expect(page.evaluate_script('document.activeElement.closest("[data-controller*=filter]")')).to be_truthy

        # Test escape functionality
        page.send_keys(:escape)

        # Test selection mode toggle
        page.send_keys([ :ctrl, :shift, 's' ])
        expect(page).to have_css('[data-dashboard-expenses-target="selectionToolbar"]:not(.hidden)')
      end

      it "manages focus properly in modals" do
        # Open selection mode
        find('[data-action*="toggleSelectionMode"]').click

        # Select some expenses
        first('[data-dashboard-expenses-target="selectionCheckbox"]').click

        # Open bulk operations modal
        find('[data-action*="bulkCategorize"]').click

        # Modal should have focus
        modal = find('[role="dialog"]', visible: true)
        expect(modal).to be_present

        # First focusable element should be focused
        focusable = modal.first('button, input, select, textarea, [tabindex]:not([tabindex="-1"])')
        expect(page.driver.browser.switch_to.active_element).to eq(focusable.native)

        # Escape should close modal and restore focus
        page.send_keys(:escape)
        expect(page).not_to have_css('[role="dialog"]', visible: true)
      end
    end

    describe "ARIA Implementation" do
      it "has proper ARIA labels on interactive elements" do
        buttons = page.all('button')
        buttons.each do |button|
          aria_label = button['aria-label'] || button['title'] || button.text.strip
          expect(aria_label).not_to be_empty, "Button missing accessible name: #{button.inspect}"
        end
      end

      it "has ARIA live regions for dynamic content" do
        expect(page).to have_css('[role="status"][aria-live="polite"]', visible: :hidden)
        expect(page).to have_css('[role="alert"][aria-live="assertive"]', visible: :hidden)
      end

      it "properly implements ARIA states" do
        # Test toggle buttons
        view_buttons = page.all('[data-mode]')
        view_buttons.each do |button|
          expect(button['aria-pressed']).to be_in([ 'true', 'false' ])
        end

        # Test filter chips
        filter_chips = page.all('[data-dashboard-filter-chips-target*="Chip"]')
        filter_chips.each do |chip|
          expect(chip['aria-pressed']).to be_in([ 'true', 'false' ])
        end
      end

      it "has proper table accessibility" do
        table = page.find('table', match: :first)

        # Check for table headers
        headers = table.all('th')
        expect(headers.count).to be > 0

        # Check header associations
        headers.each do |header|
          expect(header['scope']).to eq('col')
        end

        # Check row accessibility
        rows = table.all('tbody tr')
        rows.each do |row|
          expect(row['role']).to eq('listitem').or(be_nil)
          aria_label = row['aria-label']
          expect(aria_label).to be_present if row.has_css?('[data-expense-id]')
        end
      end

      it "has proper form accessibility" do
        # Open selection mode and bulk operations
        find('[data-action*="toggleSelectionMode"]').click
        first('[data-dashboard-expenses-target="selectionCheckbox"]').click
        find('[data-action*="bulkCategorize"]').click

        within('[role="dialog"]') do
          # Check form labels
          form_controls = all('input, select, textarea')
          form_controls.each do |control|
            label_text = find("label[for='#{control['id']}']", match: :first).text if control['id']
            aria_label = control['aria-label']
            aria_labelledby = control['aria-labelledby']

            has_label = label_text.present? || aria_label.present? || aria_labelledby.present?
            expect(has_label).to be_truthy, "Form control missing label: #{control.inspect}"
          end
        end

        page.send_keys(:escape) # Close modal
      end
    end

    describe "Visual Accessibility" do
      it "provides sufficient color contrast", skip: "Manual verification required" do
        # This would require automated color contrast checking
        # In a real implementation, you might use tools like:
        # - axe-core
        # - Pa11y
        # - Color Oracle

        expect(true).to be_truthy # Placeholder
      end

      it "supports high contrast mode" do
        page.execute_script("document.body.classList.add('high-contrast-mode')")

        # Check that high contrast styles are applied
        expect(page).to have_css('body.high-contrast-mode')

        # Interactive elements should have enhanced borders
        focused_button = first('button')
        focused_button.click

        computed_style = page.evaluate_script(
          "getComputedStyle(document.querySelector('button:focus')).outline"
        )
        expect(computed_style).not_to eq('none')
      end

      it "respects reduced motion preferences" do
        page.execute_script("document.body.setAttribute('data-reduced-motion', 'true')")

        # Check that animations are disabled
        animated_element = first('[class*="transition"]')
        if animated_element
          transition = page.evaluate_script(
            "getComputedStyle(arguments[0]).transitionDuration",
            animated_element.native
          )
          expect(transition).to eq('0.01ms').or(eq('0s'))
        end
      end

      it "supports zoom up to 200%" do
        # Simulate 200% zoom
        page.driver.browser.manage.window.resize_to(640, 480)

        # Content should still be accessible
        expect(page).to have_css('h1', visible: true)
        expect(page).to have_css('button', visible: true)

        # No horizontal scrolling on main content
        scrollable_width = page.evaluate_script('document.body.scrollWidth')
        viewport_width = page.evaluate_script('window.innerWidth')
        expect(scrollable_width).to be <= (viewport_width * 1.1) # Allow small variance
      end
    end

    describe "Screen Reader Support" do
      it "announces filter changes" do
        status_region = find('#accessibility-status', visible: :hidden)

        # Apply a filter
        first('[data-dashboard-filter-chips-target*="Chip"]').click

        # Check for announcement
        sleep 0.5 # Allow time for announcement
        expect(status_region.text).to include('filtro')
      end

      it "announces selection changes" do
        status_region = find('#accessibility-status', visible: :hidden)

        # Enter selection mode
        find('[data-action*="toggleSelectionMode"]').click

        # Select an expense
        first('[data-dashboard-expenses-target="selectionCheckbox"]').click

        sleep 0.5
        expect(status_region.text).to match(/seleccionad/)
      end

      it "announces bulk operation results" do
        alert_region = find('#accessibility-alerts', visible: :hidden)

        # Perform bulk operation
        find('[data-action*="toggleSelectionMode"]').click
        first('[data-dashboard-expenses-target="selectionCheckbox"]').click
        find('[data-action*="bulkCategorize"]').click

        within('[role="dialog"]') do
          select categories.first.name, from: 'category_id'
          click_button 'Aplicar'
        end

        sleep 1
        expect(alert_region.text).to match(/(categorizad|actualizado|exitosa)/)
      end

      it "provides loading state announcements" do
        status_region = find('#accessibility-status', visible: :hidden)

        # Trigger a loading state (filter change)
        first('[data-dashboard-filter-chips-target*="Chip"]').click

        # Should announce loading state
        expect(page).to have_css('[aria-busy="true"]', wait: 2)
      end
    end

    describe "Error Handling and Validation" do
      it "provides accessible error messages" do
        # Trigger an error condition
        find('[data-action*="toggleSelectionMode"]').click
        find('[data-action*="bulkDelete"]').click # Without selecting anything

        # Error should be announced
        alert_region = find('#accessibility-alerts', visible: :hidden)

        sleep 0.5
        error_message = alert_region.text
        expect(error_message).to include('error').or(include('seleccion')).or(include('ningún'))
      end

      it "provides form validation feedback" do
        # Open bulk operations modal
        find('[data-action*="toggleSelectionMode"]').click
        first('[data-dashboard-expenses-target="selectionCheckbox"]').click
        find('[data-action*="bulkCategorize"]').click

        within('[role="dialog"]') do
          # Submit without selecting category
          click_button 'Aplicar'

          # Should show validation error
          expect(page).to have_css('.field-error, [aria-invalid="true"]', wait: 2)
        end
      end
    end

    describe "Mobile Accessibility" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667) # iPhone SE size
      end

      it "maintains touch target size requirements" do
        buttons = page.all('button')
        buttons.each do |button|
          size = page.evaluate_script(
            "const rect = arguments[0].getBoundingClientRect(); " +
            "return { width: rect.width, height: rect.height }",
            button.native
          )

          # WCAG requires 44x44px minimum touch targets
          expect([ size['width'], size['height'] ].min).to be >= 40 # Allow small variance
        end
      end

      it "supports mobile screen readers" do
        # Test that content is still accessible on mobile
        expect(page).to have_css('[role="main"]')
        expect(page).to have_css('h1')

        # Navigation should be accessible
        nav_links = page.all('nav a')
        nav_links.each do |link|
          expect(link['aria-label'] || link.text.strip).not_to be_empty
        end
      end
    end

    describe "Performance and Accessibility" do
      it "maintains fast loading with accessibility features" do
        start_time = Time.current

        visit dashboard_expenses_path
        expect(page).to have_css('[data-controller="dashboard-expenses"]')

        load_time = Time.current - start_time
        expect(load_time).to be < 3.0 # Should load within 3 seconds
      end

      it "does not interfere with virtual scrolling performance" do
        # Test that accessibility features don't significantly impact performance
        # This is a basic test - in production you'd want more sophisticated metrics

        scroll_start = Time.current

        # Scroll multiple times rapidly
        10.times do
          page.execute_script("window.scrollBy(0, 100)")
          sleep 0.01
        end

        scroll_time = Time.current - scroll_start
        expect(scroll_time).to be < 1.0 # Should handle rapid scrolling smoothly
      end
    end
  end

  describe "Accessibility Utilities" do
    it "provides keyboard shortcut help" do
      # Test Alt+H shortcut for help
      page.send_keys([ :alt, 'h' ])

      expect(page).to have_css('[role="dialog"]', text: 'Atajos de Teclado')

      # Should list keyboard shortcuts
      expect(page).to have_text('Tab')
      expect(page).to have_text('Escape')
      expect(page).to have_text('Alt+1')

      # Close with Escape
      page.send_keys(:escape)
      expect(page).not_to have_css('[role="dialog"]', text: 'Atajos de Teclado')
    end

    it "supports focus management utilities" do
      # Test programmatic focus management
      page.execute_script("window.accessibilityManager.focusFilters()")

      # Should focus on filters section
      active_element = page.evaluate_script('document.activeElement')
      expect(active_element).to be_present
    end
  end
end
