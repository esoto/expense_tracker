class ProcessEmailJob < ApplicationJob
  queue_as :default

  def perform(email_account_id, email_data)
    email_account = EmailAccount.find_by(id: email_account_id)

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      return
    end

    Rails.logger.info "Processing individual email for: #{email_account.email}"
    Rails.logger.debug "Email data: #{email_data.inspect}"

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
  end

  private

  def save_failed_parsing(email_account, email_data, errors)
    # Create a failed expense record for debugging
    Expense.create!(
      email_account: email_account,
      amount: 0.01, # Use minimal amount to satisfy validation
      transaction_date: Time.current,
      description: "Failed to parse: #{errors.join(", ")}",
      raw_email_content: email_data[:body].to_s,
      parsed_data: email_data.to_json,
      status: "failed"
    )
  rescue StandardError => e
    Rails.logger.error "Failed to save failed parsing record: #{e.message}"
  end
end
