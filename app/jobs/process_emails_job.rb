class ProcessEmailsJob < ApplicationJob
  queue_as :default

  def perform(email_account_id = nil, since: 1.week.ago, sync_session_id: nil)
    @sync_session = sync_session_id ? SyncSession.find_by(id: sync_session_id) : nil

    if @sync_session
      @sync_session.start! if @sync_session.pending?
    end

    if email_account_id
      process_single_account(email_account_id, since)
    else
      process_all_accounts(since)
    end

    if @sync_session && !email_account_id
      # Start monitoring job to track completion
      SyncSessionMonitorJob.set(wait: 5.seconds).perform_later(@sync_session.id)
    end
  rescue => e
    @sync_session&.fail!(e.message)
    raise
  end

  private

  def process_single_account(email_account_id, since)
    email_account = EmailAccount.find_by(id: email_account_id)
    session_account = find_or_create_session_account(email_account) if @sync_session

    # Store job ID in session account if available
    if session_account && self.class.respond_to?(:current_job_id)
      session_account.update(job_id: self.class.current_job_id)
    end

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      session_account&.fail!("Email account not found")
      return
    end

    unless email_account.active?
      Rails.logger.info "Skipping inactive email account: #{email_account.email}"
      session_account&.fail!("Email account is inactive")
      return
    end

    Rails.logger.info "Processing emails for: #{email_account.email}"
    session_account&.start_processing!

    fetcher = EmailProcessing::Fetcher.new(email_account, sync_session_account: session_account)
    result = fetcher.fetch_new_emails(since: since)

    if result.success?
      Rails.logger.info "Successfully processed emails for: #{email_account.email} - " \
                       "Found: #{result.total_emails_found}, Processed: #{result.processed_emails_count}"
      if result.has_errors?
        Rails.logger.warn "Warnings during processing: #{result.error_messages}"
      end
      session_account&.complete!
    else
      Rails.logger.error "Failed to process emails for #{email_account.email}: #{result.error_messages}"
      session_account&.fail!(result.error_messages.join(", "))
    end
  end

  def find_or_create_session_account(email_account)
    return nil unless @sync_session && email_account

    @sync_session.sync_session_accounts.find_or_create_by(email_account: email_account)
  end

  def process_all_accounts(since)
    email_accounts = EmailAccount.active

    Rails.logger.info "Processing emails for #{email_accounts.count} active accounts"

    email_accounts.find_each do |email_account|
      # Process each account in a separate job to isolate failures
      job = ProcessEmailsJob.perform_later(email_account.id, since: since, sync_session_id: @sync_session&.id)

      # Track job ID if we have a sync session
      if @sync_session && job.respond_to?(:provider_job_id)
        @sync_session.add_job_id(job.provider_job_id)
      end
    end
  end
end
