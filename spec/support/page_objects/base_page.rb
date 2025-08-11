# Base Page Object for System Testing
# Provides common functionality for all page objects

class BasePage
  include Capybara::DSL
  include RSpec::Matchers
  include Rails.application.routes.url_helpers

  def initialize
    # Subclasses should call visit in their initialize method
  end

  # Wait for page to load completely
  def wait_for_page_load
    expect(page).to have_css('body', wait: 10)
  end

  # Check if page has loaded successfully
  def loaded?
    page.has_css?('body') && !page.has_css?('.loading', wait: 1)
  end

  # Wait for an element to appear
  def wait_for_element(selector, timeout: 10)
    expect(page).to have_css(selector, wait: timeout)
  end

  # Wait for an element to disappear
  def wait_for_element_to_disappear(selector, timeout: 10)
    expect(page).not_to have_css(selector, wait: timeout)
  end

  # Scroll to element
  def scroll_to(selector)
    element = find(selector)
    page.execute_script("arguments[0].scrollIntoView(true);", element)
    sleep 0.5 # Allow for smooth scrolling
  end

  # Take a screenshot for debugging
  def take_screenshot(name = nil)
    filename = name || "screenshot_#{Time.current.strftime('%Y%m%d_%H%M%S')}"
    page.save_screenshot("tmp/screenshots/#{filename}.png")
  end

  # Check if element is visible in viewport
  def element_in_viewport?(selector)
    element = find(selector, visible: false)
    page.evaluate_script(<<~JS)
      var element = arguments[0];
      var rect = element.getBoundingClientRect();
      rect.top >= 0 && rect.left >= 0 &&#{' '}
      rect.bottom <= window.innerHeight &&#{' '}
      rect.right <= window.innerWidth;
    JS
  end

  # Wait for JavaScript to finish executing
  def wait_for_javascript
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until page.evaluate_script('jQuery.active == 0') rescue false
    end
  end

  # Common navigation methods
  def click_link_or_button(text)
    click_on(text)
  end

  def fill_form_field(label, value)
    fill_in(label, with: value)
  end

  def select_from_dropdown(value, from:)
    select(value, from: from)
  end

  # Alert and notification helpers
  def dismiss_alert
    page.driver.browser.switch_to.alert.dismiss if alert_present?
  end

  def accept_alert
    page.driver.browser.switch_to.alert.accept if alert_present?
  end

  def alert_present?
    page.driver.browser.switch_to.alert
    true
  rescue Selenium::WebDriver::Error::NoSuchAlertError
    false
  end

  # Check for success/error messages
  def has_success_message?(message = nil)
    if message
      page.has_css?('.alert-success, .bg-emerald-50', text: message, wait: 5)
    else
      page.has_css?('.alert-success, .bg-emerald-50', wait: 5)
    end
  end

  def has_error_message?(message = nil)
    if message
      page.has_css?('.alert-danger, .bg-rose-50', text: message, wait: 5)
    else
      page.has_css?('.alert-danger, .bg-rose-50', wait: 5)
    end
  end

  # Mobile testing helpers
  def resize_to_mobile
    page.driver.browser.manage.window.resize_to(375, 667)
  end

  def resize_to_tablet
    page.driver.browser.manage.window.resize_to(768, 1024)
  end

  def resize_to_desktop
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  private

  # Retry mechanism for flaky operations
  def retry_operation(max_retries: 3, &block)
    retries = 0
    begin
      yield
    rescue StandardError => e
      retries += 1
      if retries <= max_retries
        sleep(retries * 0.5)
        retry
      else
        raise e
      end
    end
  end
end
