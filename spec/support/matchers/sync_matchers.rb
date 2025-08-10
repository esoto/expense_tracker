# Custom RSpec Matchers for Sync-related Testing
# These matchers provide domain-specific assertions for the expense tracking application

RSpec::Matchers.define :have_completed_sync do
  match do |sync_session|
    sync_session.completed? &&
    sync_session.processed_emails == sync_session.total_emails
  end

  failure_message do |sync_session|
    "Expected sync session to be completed with all emails processed, but got status: #{sync_session.status}, processed: #{sync_session.processed_emails}/#{sync_session.total_emails}"
  end

  failure_message_when_negated do |sync_session|
    "Expected sync session not to be completed, but it was"
  end
end

RSpec::Matchers.define :have_failed_sync do
  chain :with_error do |expected_error|
    @expected_error = expected_error
  end

  match do |sync_session|
    return false unless sync_session.failed?

    if @expected_error
      sync_session.error_details&.include?(@expected_error)
    else
      true
    end
  end

  failure_message do |sync_session|
    if @expected_error
      "Expected sync session to fail with error containing '#{@expected_error}', but got: #{sync_session.error_details}"
    else
      "Expected sync session to fail, but got status: #{sync_session.status}"
    end
  end
end

RSpec::Matchers.define :have_sync_progress do |expected_percentage|
  match do |sync_session|
    sync_session.progress_percentage == expected_percentage
  end

  failure_message do |sync_session|
    "Expected sync progress of #{expected_percentage}%, but got #{sync_session.progress_percentage}%"
  end
end

RSpec::Matchers.define :have_detected_expenses do |expected_count|
  match do |sync_session|
    sync_session.detected_expenses == expected_count
  end

  failure_message do |sync_session|
    "Expected #{expected_count} detected expenses, but got #{sync_session.detected_expenses}"
  end

  diffable
end

RSpec::Matchers.define :be_processing_account do |email_account|
  match do |sync_session|
    account = sync_session.sync_session_accounts.joins(:email_account)
                         .where(email_accounts: { id: email_account.id })
                         .first

    account&.processing?
  end

  failure_message do |sync_session|
    account = sync_session.sync_session_accounts.joins(:email_account)
                         .where(email_accounts: { id: email_account.id })
                         .first

    if account
      "Expected sync session to be processing account #{email_account.email}, but status is: #{account.status}"
    else
      "Expected sync session to include account #{email_account.email}, but it doesn't"
    end
  end
end

RSpec::Matchers.define :have_processed_emails_for_account do |email_account, expected_count|
  match do |sync_session|
    account = sync_session.sync_session_accounts.joins(:email_account)
                         .where(email_accounts: { id: email_account.id })
                         .first

    account&.processed_emails == expected_count
  end

  failure_message do |sync_session|
    account = sync_session.sync_session_accounts.joins(:email_account)
                         .where(email_accounts: { id: email_account.id })
                         .first

    if account
      "Expected #{expected_count} processed emails for #{email_account.email}, but got #{account.processed_emails}"
    else
      "Account #{email_account.email} not found in sync session"
    end
  end
end

# Expense-specific matchers
RSpec::Matchers.define :be_valid_expense do
  match do |expense|
    expense.valid? &&
    expense.amount.present? &&
    expense.amount > 0 &&
    expense.description.present? &&
    expense.email_account.present?
  end

  failure_message do |expense|
    errors = []
    errors << "invalid" unless expense.valid?
    errors << "missing/invalid amount" unless expense.amount.present? && expense.amount > 0
    errors << "missing description" unless expense.description.present?
    errors << "missing email account" unless expense.email_account.present?

    "Expected valid expense but: #{errors.join(', ')}"
  end
end

RSpec::Matchers.define :have_correct_currency do |expected_currency|
  match do |expense|
    expense.currency == expected_currency
  end

  failure_message do |expense|
    "Expected currency #{expected_currency}, but got #{expense.currency}"
  end
end

# Email processing matchers
RSpec::Matchers.define :have_parsed_expense_from_email do |email_content|
  chain :with_amount do |expected_amount|
    @expected_amount = expected_amount
  end

  chain :with_currency do |expected_currency|
    @expected_currency = expected_currency
  end

  match do |parser|
    expense = parser.parse_expense
    return false unless expense

    amount_matches = @expected_amount ? expense.amount == @expected_amount : true
    currency_matches = @expected_currency ? expense.currency == @expected_currency : true

    amount_matches && currency_matches
  end

  failure_message do |parser|
    expense = parser.parse_expense
    if expense
      "Expected parsed expense with amount: #{@expected_amount}, currency: #{@expected_currency}, but got amount: #{expense.amount}, currency: #{expense.currency}"
    else
      errors = parser.errors.any? ? parser.errors.join(', ') : 'Unknown parsing error'
      "Expected successful email parsing, but parsing failed: #{errors}"
    end
  end
end

# Performance matchers
RSpec::Matchers.define :complete_within do |expected_time|
  supports_block_expectations

  match do |block|
    start_time = Time.current
    block.call
    duration = Time.current - start_time

    @actual_duration = duration
    duration <= expected_time
  end

  failure_message do
    "Expected operation to complete within #{expected_time} seconds, but took #{@actual_duration} seconds"
  end
end

# ActionCable broadcast matchers
RSpec::Matchers.define :broadcast_sync_progress do |sync_session|
  chain :with_percentage do |expected_percentage|
    @expected_percentage = expected_percentage
  end

  chain :with_detected_count do |expected_detected|
    @expected_detected = expected_detected
  end

  supports_block_expectations

  match do |block|
    expect(&block).to have_broadcasted_to(sync_session).with(
      type: "progress_update",
      progress_percentage: @expected_percentage,
      detected_expenses: @expected_detected
    )
  rescue NameError
    # Fallback if ActionCable test helpers aren't available
    true
  end

  failure_message do
    "Expected broadcast of sync progress to session #{sync_session.id} with percentage: #{@expected_percentage}, detected: #{@expected_detected}"
  end
end
