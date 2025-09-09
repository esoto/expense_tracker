class ProcessEmailJob < ApplicationJob
  queue_as :default

  TRUNCATE_SIZE = 10_000  # Store only 10KB for large emails

  def perform(email_account_id, email_data)
    email_account = EmailAccount.find_by(id: email_account_id)

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      return
    end

    Rails.logger.info "Processing individual email for: #{email_account.email}"
    Rails.logger.debug "Email data: #{email_data.inspect}"

    # Get current sync session for metrics
    sync_session = SyncSession.active.last
    metrics_collector = SyncMetricsCollector.new(sync_session) if sync_session

    # Track expense detection operation
    if metrics_collector
      metrics_collector.track_operation(:detect_expense, email_account, { email_subject: email_data&.dig(:subject) }) do
        parse_and_save_expense(email_account, email_data)
      end
      metrics_collector.flush_buffer
    else
      parse_and_save_expense(email_account, email_data)
    end
  end

  private

  def parse_and_save_expense(email_account, email_data)
    parser = EmailProcessing::Parser.new(email_account, email_data)
    expense = parser.parse_expense

    if expense
      Rails.logger.info "Successfully created expense: #{expense.id} - #{expense.formatted_amount}"

      # Optionally notify about new expense
      # NotificationJob.perform_later(expense.id) if expense.amount > 100
    else
      Rails.logger.warn "Failed to create expense from email: #{parser.errors.join(", ")}"

      # Could save failed parsing attempts for debugging
      save_failed_parsing(email_account, email_data, parser.errors)
    end

    expense
  end

  def save_failed_parsing(email_account, email_data, errors)
    email_body = email_data&.dig(:body).to_s
    truncated = false

    if email_body.bytesize > TRUNCATE_SIZE
      email_body = email_body.byteslice(0, TRUNCATE_SIZE) + "\n... [truncated]"
      truncated = true
    end

    Expense.create!(
      email_account: email_account,
      amount: 0.01,
      transaction_date: Time.current,
      merchant_name: nil,  # Explicitly set to nil for failed parsing
      description: "Failed to parse: #{errors.first}",  # Only first error to save space
      raw_email_content: email_body,
      parsed_data: {
        errors: errors,
        truncated: truncated,
        original_size: email_data&.dig(:body).to_s.bytesize
      }.to_json,
      status: "failed",
      email_body: email_body,
      bank_name: email_account.bank_name
    )
  rescue StandardError => e
    Rails.logger.error "Failed to save failed parsing record: #{e.message}"
  end
end
