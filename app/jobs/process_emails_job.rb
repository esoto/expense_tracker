class ProcessEmailsJob < ApplicationJob
  queue_as :default

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

    fetcher = EmailFetcher.new(email_account)
    success = fetcher.fetch_new_emails(since: since)

    if success
      Rails.logger.info "Successfully processed emails for: #{email_account.email}"
    else
      Rails.logger.error "Failed to process emails for #{email_account.email}: #{fetcher.errors.join(", ")}"
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
end
