class ProcessEmailsJob < ApplicationJob
  queue_as :email_processing

  # Add retry logic
  retry_on ImapConnectionService::ConnectionError, wait: :exponentially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: 5.seconds, attempts: 2

  # Add performance monitoring
  around_perform do |job, block|
    start_time = Time.current
    account_id = job.arguments.first

    Rails.logger.info "[ProcessEmailsJob] Starting for account #{account_id}"

    block.call

    duration = Time.current - start_time
    Rails.logger.info "[ProcessEmailsJob] Completed in #{duration.round(2)}s"

    # Alert on slow processing
    if duration > 30.seconds
      Rails.logger.warn "[ProcessEmailsJob] Slow processing: #{duration.round(2)}s for account #{account_id}"
    end
  end

  def perform(email_account_id = nil, since: 1.week.ago)
    if email_account_id
      process_single_account(email_account_id, since)
    else
      process_all_accounts(since)
    end
  end

  private

  def process_single_account(email_account_id, since)
    email_account = EmailAccount.find_by(id: email_account_id)

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      return
    end

    unless email_account.active?
      Rails.logger.info "Skipping inactive email account: #{email_account.email}"
      return
    end

    Rails.logger.info "Processing emails for: #{email_account.email}"

    fetcher = EmailProcessing::Fetcher.new(email_account)
    result = fetcher.fetch_new_emails(since: since)

    if result.success?
      Rails.logger.info "Successfully processed emails for: #{email_account.email} - " \
                       "Found: #{result.total_emails_found}, Processed: #{result.processed_emails_count}"
      if result.has_errors?
        Rails.logger.warn "Warnings during processing: #{result.error_messages}"
      end
    else
      Rails.logger.error "Failed to process emails for #{email_account.email}: #{result.error_messages}"
    end
  end

  def process_all_accounts(since)
    email_accounts = EmailAccount.active

    Rails.logger.info "Processing emails for #{email_accounts.count} active accounts"

    email_accounts.find_each do |email_account|
      # Process each account in a separate job to isolate failures
      ProcessEmailsJob.perform_later(email_account.id, since: since)
    end
  end

  def process_all_accounts_in_batches(since)
    EmailAccount.active.find_in_batches(batch_size: 5) do |batch|
      batch.each do |email_account|
        ProcessEmailsJob.perform_later(email_account.id, since: since)
      end

      # Prevent IMAP server overload
      sleep(1) if batch.size == 5
    end
  end
end
