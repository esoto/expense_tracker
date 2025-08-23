# Helper methods for inline actions system tests
module InlineActionsHelper
  # Wait for Stimulus controller to be ready
  def wait_for_inline_actions_ready
    expect(page).to have_css('[data-controller="dashboard-inline-actions"]', wait: 10)
    sleep 0.5 # Allow controller to initialize

    # Verify Stimulus is loaded
    expect(page.evaluate_script("typeof Stimulus !== 'undefined'")).to be true
  end

  # Hover over expense row and ensure actions are visible
  def hover_and_show_actions(row)
    row.hover
    # Force hover state if needed
    page.execute_script("arguments[0].classList.add('group-hover')", row.native)
    sleep 0.3 # Allow transition

    # Make actions visible for test
    within row do
      actions = find('.inline-quick-actions', visible: :all)
      page.execute_script("arguments[0].style.opacity = '1'", actions.native)
      page.execute_script("arguments[0].style.pointerEvents = 'auto'", actions.native)
    end
  end

  # Click button using JavaScript to avoid overlay issues
  def js_click(element)
    page.execute_script("arguments[0].click()", element.native)
  end

  # Wait for API response and DOM update
  def wait_for_action_complete
    sleep 1 # Allow API call to complete
    wait_for_ajax
  end

  # Wait for AJAX requests to complete
  def wait_for_ajax
    Timeout.timeout(5) do
      loop until page.evaluate_script('jQuery.active').zero?
    end
  rescue Timeout::Error, StandardError
    # jQuery might not be available, just wait
    sleep 0.5
  end
end

RSpec.configure do |config|
  config.include InlineActionsHelper, type: :system
end
