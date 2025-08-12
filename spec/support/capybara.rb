# frozen_string_literal: true

require 'capybara/rails'
require 'capybara/rspec'
require 'selenium-webdriver'

# Configure Capybara for system tests
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    # Use headless Chrome for JavaScript tests
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
  end
end

# Configure Capybara settings
Capybara.configure do |config|
  # Wait up to 5 seconds for elements to appear
  config.default_max_wait_time = 5

  # Ignore hidden elements by default
  config.ignore_hidden_elements = true

  # Default selector
  config.default_selector = :css

  # Server settings
  config.server = :puma, { Silent: true }

  # Asset compilation for tests
  config.automatic_label_click = true
end

# Configure Chrome options for headless testing
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--window-size=1400,900')
  options.add_argument('--disable-web-security') # Allow cross-origin requests for CDN assets
  options.add_argument('--allow-insecure-localhost')

  # Enable JavaScript console logging for debugging
  options.add_preference(:loggingPrefs, { browser: 'ALL' })

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options
  )
end

# Ensure assets are compiled for system tests
RSpec.configure do |config|
  config.before(:suite) do
    # Ensure test environment compiles assets
    Rails.application.config.assets.compile = true if defined?(Rails)
    Rails.application.config.assets.debug = false if defined?(Rails)

    # Precompile assets for tests if needed
    if defined?(Propshaft)
      Rails.application.config.assets.prefix = '/test-assets'
    end
  end

  config.before(:each, type: :system) do
    # Clear any cached JavaScript
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  config.before(:each, type: :system, js: true) do
    # Use JavaScript driver for JS tests
    Capybara.current_driver = :selenium_chrome_headless
  end

  config.after(:each, type: :system, js: true) do |example|
    # Take screenshot on failure for debugging
    if example.exception
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      screenshot_name = "failure_#{example.full_description.parameterize(separator: '_')[0..99]}_#{timestamp}.png"
      page.save_screenshot(Rails.root.join('tmp', 'capybara', screenshot_name))
      puts "Screenshot saved: tmp/capybara/#{screenshot_name}"
    end
  end
end
