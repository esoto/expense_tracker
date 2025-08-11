# Sync Sessions Page Object for System Testing
# Handles interactions with the sync sessions management page

class SyncSessionsPage < BasePage
  def initialize
    visit sync_sessions_path
    wait_for_page_load
  end

  # Navigation
  def go_to_session_details(session_id)
    click_link href: sync_session_path(session_id)
  end

  # Page state checks
  def has_sync_sessions?
    page.has_css?('table tbody tr', wait: 5)
  end

  def has_active_sync_session?
    page.has_css?('[data-controller="sync-sessions"]', wait: 5)
  end

  def has_session_with_status?(status)
    page.has_content?(status.humanize, wait: 5)
  end

  # Active sync session interactions
  def cancel_active_sync
    within('.bg-amber-50') do
      click_button 'Cancelar'
    end
  end

  def active_session_progress
    within('.bg-amber-50') do
      find('[data-sync-sessions-target="progressBar"]')[:style].match(/width:\s*(\d+)%/)[1].to_i
    end
  rescue
    0
  end

  def active_session_processed_emails
    within('.bg-amber-50') do
      text = find('[data-sync-sessions-target="processedCount"]').text
      text.split(' / ').first.to_i
    end
  end

  def active_session_total_emails
    within('.bg-amber-50') do
      text = find('[data-sync-sessions-target="processedCount"]').text
      text.split(' / ').last.to_i
    end
  end

  # Session list interactions
  def session_rows
    all('table tbody tr')
  end

  def session_row(session_id)
    find("tr[data-session-id='#{session_id}']")
  end

  def session_status(session_id)
    within session_row(session_id) do
      find('span.px-2').text
    end
  end

  def session_duration(session_id)
    within session_row(session_id) do
      all('td')[1].text
    end
  end

  def session_accounts_count(session_id)
    within session_row(session_id) do
      all('td')[3].text.to_i
    end
  end

  def session_emails_processed(session_id)
    within session_row(session_id) do
      text = all('td')[4].text
      processed, total = text.split(' / ').map(&:to_i)
      { processed: processed, total: total }
    end
  end

  def session_expenses_detected(session_id)
    within session_row(session_id) do
      all('td')[5].text.to_i
    end
  end

  def click_session_details(session_id)
    within session_row(session_id) do
      click_link 'Ver Detalles'
    end
  end

  # Real-time updates
  def wait_for_session_status_change(session_id, expected_status, timeout: 30)
    Timeout.timeout(timeout) do
      loop do
        break if session_status(session_id).downcase.include?(expected_status.downcase)
        sleep 0.5
      end
    end
  end

  def wait_for_progress_update(session_id, timeout: 30)
    within session_row(session_id) do
      initial_text = find('[data-progress-text]').text rescue ""

      Timeout.timeout(timeout) do
        loop do
          current_text = find('[data-progress-text]').text rescue ""
          break if current_text != initial_text
          sleep 0.5
        end
      end
    end
  end

  def wait_for_expenses_count_update(session_id, expected_count, timeout: 30)
    Timeout.timeout(timeout) do
      loop do
        break if session_expenses_detected(session_id) >= expected_count
        sleep 0.5
      end
    end
  end

  # Account cards in active session
  def account_cards
    all('[data-sync-sessions-target="accountCard"]')
  end

  def account_card(account_id)
    find("[data-account-id='#{account_id}']")
  end

  def account_status_badge(account_id)
    within account_card(account_id) do
      find('[data-status-badge]')
    end
  end

  def account_processing_counts(account_id)
    within account_card(account_id) do
      text = find('[data-account-counts]').text
      processed, total = text.split(' / ')
      expenses = text.split(' ').last.gsub(' gastos', '').to_i

      {
        processed: processed.to_i,
        total: total.split(' ').first.to_i,
        expenses: expenses
      }
    end
  end

  # Statistics summary
  def total_sessions_processed
    find('[data-metric="total-processed"]').text.to_i rescue 0
  end

  def monthly_emails_processed
    find('[data-metric="monthly-emails"]').text.to_i rescue 0
  end

  def monthly_expenses_detected
    find('[data-metric="monthly-expenses"]').text.to_i rescue 0
  end

  # Filters and sorting
  def filter_by_status(status)
    select status, from: 'status_filter' if page.has_select?('status_filter')
  end

  def sort_by_column(column_name)
    click_on column_name if page.has_link?(column_name)
  end

  # Pagination
  def go_to_next_page
    click_link 'Siguiente' if page.has_link?('Siguiente')
  end

  def go_to_previous_page
    click_link 'Anterior' if page.has_link?('Anterior')
  end

  # Bulk operations
  def select_all_sessions
    check 'select_all' if page.has_field?('select_all')
  end

  def select_session(session_id)
    check "session_#{session_id}" if page.has_field?("session_#{session_id}")
  end

  def delete_selected_sessions
    click_button 'Eliminar Seleccionadas' if page.has_button?('Eliminar Seleccionadas')
  end

  # Export functionality
  def export_sessions_csv
    click_link 'Exportar CSV' if page.has_link?('Exportar CSV')
  end

  def export_sessions_pdf
    click_link 'Exportar PDF' if page.has_link?('Exportar PDF')
  end

  private

  def wait_for_realtime_update(timeout: 10)
    # Wait for any DOM changes that might indicate a real-time update
    sleep 0.1
    wait_for_javascript
  end
end
