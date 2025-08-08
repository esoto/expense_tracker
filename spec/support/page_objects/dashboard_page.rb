# Dashboard Page Object for System Testing
# Handles interactions with the main expenses dashboard

class DashboardPage < BasePage
  def initialize
    visit dashboard_expenses_path
    wait_for_page_load
  end

  # Page elements
  def sync_widget
    find('[data-controller="sync-widget"]')
  end

  def sync_all_button
    find('input[type="submit"][value*="Sincronizar Todos"]')
  end

  def progress_bar
    find('[data-sync-widget-target="progressBar"]')
  end

  def progress_percentage
    find('[data-sync-widget-target="progressPercentage"]')
  end

  def processed_count
    find('[data-sync-widget-target="processedCount"]')
  end

  def detected_count
    find('[data-sync-widget-target="detectedCount"]')
  end

  def time_remaining
    find('[data-sync-widget-target="timeRemaining"]')
  end

  # Page state checks
  def has_sync_widget?
    page.has_css?('[data-controller="sync-widget"]')
  end

  def has_active_sync?
    page.has_css?('[data-sync-widget-active-value="true"]')
  end

  def sync_in_progress?
    page.has_css?('.animate-spin', wait: 2) &&
    page.has_content?('Sincronizando')
  end

  def sync_completed?
    page.has_content?('Sincronización completada') ||
    progress_percentage_value == 100
  end

  # Actions
  def start_sync_all
    sync_all_button.click
    wait_for_sync_to_start
  end

  def start_sync_for_account(account_name)
    within('.border-t') do
      click_button(account_name.truncate(30))
    end
    wait_for_sync_to_start
  end

  def wait_for_sync_to_start(timeout: 10)
    expect(page).to have_css('.animate-spin', wait: timeout)
  end

  def wait_for_sync_completion(timeout: 60)
    expect(page).to have_content('Sincronización completada', wait: timeout)
  end

  def wait_for_progress_update(expected_progress = nil, timeout: 30)
    if expected_progress
      expect(page).to have_content("#{expected_progress}%", wait: timeout)
    else
      # Wait for any progress change
      initial_progress = progress_percentage_value
      Timeout.timeout(timeout) do
        loop do
          break if progress_percentage_value != initial_progress
          sleep 0.5
        end
      end
    end
  end

  # Data extraction
  def progress_percentage_value
    progress_percentage.text.gsub('%', '').to_i
  rescue Capybara::ElementNotFound
    0
  end

  def processed_count_value
    processed_count.text.gsub(/[^\d]/, '').to_i
  rescue Capybara::ElementNotFound
    0
  end

  def detected_expenses_count
    detected_count.text.to_i
  rescue Capybara::ElementNotFound
    0
  end

  def time_remaining_text
    time_remaining.text
  rescue Capybara::ElementNotFound
    nil
  end

  # Account status checks
  def account_syncing?(account_email)
    within account_row(account_email) do
      page.has_css?('.animate-spin', wait: 2)
    end
  end

  def account_completed?(account_email)
    within account_row(account_email) do
      page.has_css?('.bg-emerald-400', wait: 2)
    end
  end

  def account_last_sync_time(account_email)
    within account_row(account_email) do
      find('[data-progress-text]').text.gsub('Último: ', '')
    end
  end

  # Notifications and messages
  def has_notification?(message)
    page.has_css?('.fixed.top-4.right-4', text: message, wait: 10)
  end

  def dismiss_notification
    within('.fixed.top-4.right-4') do
      find('button').click
    end
  end

  # Responsive design helpers
  def mobile_view?
    page.evaluate_script('window.innerWidth < 768')
  end

  def desktop_view?
    page.evaluate_script('window.innerWidth >= 1024')
  end

  # Real-time testing helpers
  def enable_websocket_monitoring
    page.evaluate_script(<<~JS
      window.websocketMessages = [];
      if (window.consumer && window.consumer.connection) {
        const originalReceive = window.consumer.connection.receive;
        window.consumer.connection.receive = function(data) {
          window.websocketMessages.push(data);
          return originalReceive.call(this, data);
        };
      }
    JS
    )
  end

  def websocket_messages
    page.evaluate_script('window.websocketMessages || []')
  end

  def wait_for_websocket_message(type, timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        messages = websocket_messages
        break if messages.any? { |msg| JSON.parse(msg)['type'] == type rescue false }
        sleep 0.5
      end
    end
  end

  # Dashboard metrics
  def total_expenses_count
    find('[data-metric="total-expenses"]').text.to_i
  rescue Capybara::ElementNotFound
    0
  end

  def this_month_expenses
    find('[data-metric="monthly-expenses"]').text.to_i
  rescue Capybara::ElementNotFound
    0
  end

  def active_accounts_count
    find('[data-metric="active-accounts"]').text.to_i
  rescue Capybara::ElementNotFound
    0
  end

  private

  def account_row(account_email)
    find('[data-account-id]', text: account_email)
  end
end
